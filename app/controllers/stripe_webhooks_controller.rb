class StripeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def receive
    payload    = request.raw_post
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
    secret     = ENV["STRIPE_SIGNING_SECRET"]

    Rails.logger.info "[Stripe] Webhook received bytes=#{payload.bytesize} sig_present=#{sig_header.present?}"

    event =
      if secret.present?
        begin
          Stripe::Webhook.construct_event(payload, sig_header, secret)
        rescue JSON::ParserError, Stripe::SignatureVerificationError => e
          Rails.logger.warn "[Stripe] Webhook verify error: #{e.class} - #{e.message}"
          return head :bad_request
        end
      elsif Rails.env.local?
        # Only development/test may skip the signature (no whsec_ locally).
        Rails.logger.warn "[Stripe] Dev env: parsing event sem checar assinatura"
        Stripe::Event.construct_from(JSON.parse(payload))
      else
        # Fail closed (audit A1): without the signing secret anyone could POST a
        # fake "payment succeeded" event. 500 makes Stripe retry, so events are
        # not lost once the secret is restored.
        Rails.logger.error "[Stripe] STRIPE_SIGNING_SECRET missing – rejecting unsigned webhook"
        return head :internal_server_error
      end

    Rails.logger.info "[Stripe] Event id=#{event['id']} type=#{event['type']}"

    # Idempotência: não processar duas vezes o mesmo evento
    if processed_event?(event.id)
      Rails.logger.info "[Stripe] Duplicate event id=#{event.id} – skipping"
      return head :ok
    end

    case event["type"]
    when "checkout.session.completed"
      session = event["data"]["object"]
      handle_checkout_session_completed(session)

    when "payment_intent.succeeded"
      intent = event["data"]["object"]
      handle_payment_intent_succeeded(intent)

    when "checkout.session.expired"
      session = event["data"]["object"]
      handle_checkout_session_expired(session)

    # Async methods (Pix, boleto): the money arrives after "completed".
    when "checkout.session.async_payment_succeeded"
      session = event["data"]["object"]
      handle_checkout_session_async_payment_succeeded(session)

    when "checkout.session.async_payment_failed"
      session = event["data"]["object"]
      handle_checkout_session_async_payment_failed(session)

    else
      Rails.logger.info "[Stripe] Ignored event type: #{event['type']}"
    end

    mark_event_processed(event.id)
    head :ok

  rescue StandardError => e
    Rails.logger.error "[Stripe] Webhook fatal: #{e.class} - #{e.message}\n#{(e.backtrace || [])[0,10].join("\n")}"
    head :internal_server_error
  end

  private

  # ---------- Event handlers ----------------------------------------------

  def handle_checkout_session_completed(session)
    metadata = session["metadata"] || {}
    order_id = metadata["order_id"]
    Rails.logger.info "[Stripe] checkout.session.completed order_id=#{order_id} session_id=#{session['id']}"

    # With Pix/boleto, "completed" only means the code was generated: the money
    # has not arrived yet (payment_status "unpaid"). The order is marked paid by
    # checkout.session.async_payment_succeeded (or payment_intent.succeeded).
    unless session["payment_status"] == "paid"
      Rails.logger.info "[Stripe] checkout.session.completed: Order #{order_id} awaiting async payment " \
                        "(payment_status=#{session['payment_status'].inspect})"
      return
    end

    mark_order_paid(order_id,
                    payment_reference: session["payment_intent"] || session["id"],
                    amount_cents: session["amount_total"],
                    currency: session["currency"],
                    source: "checkout.session.completed")
  end

  def handle_payment_intent_succeeded(intent)
    metadata = intent["metadata"] || {}
    order_id = metadata["order_id"]

    mark_order_paid(
      order_id,
      payment_reference: intent["id"],
      amount_cents: intent["amount_received"] || intent["amount"],
      currency: intent["currency"],
      source: "payment_intent.succeeded"
    )
  end

  # Pix/boleto paid: same path as a card payment (amount check, lock, e-mail).
  def handle_checkout_session_async_payment_succeeded(session)
    mark_order_paid((session["metadata"] || {})["order_id"],
                    payment_reference: session["payment_intent"] || session["id"],
                    amount_cents: session["amount_total"],
                    currency: session["currency"],
                    source: "checkout.session.async_payment_succeeded")
  end

  # Pix code expired (or the payment failed): same as an expired session.
  def handle_checkout_session_async_payment_failed(session)
    handle_checkout_session_expired(session)
  end

  # The payment window closed without payment: cancel and give the stock back.
  # expire_and_restock! is a no-op for paid/already-cancelled orders, so a late
  # event for an order paid through a second session is harmless.
  def handle_checkout_session_expired(session)
    order_id = (session["metadata"] || {})["order_id"]
    order = order_id.present? && Order.find_by(id: order_id)
    unless order
      Rails.logger.warn "[Stripe] checkout.session.expired: Order #{order_id.inspect} not found"
      return
    end

    if order.expire_and_restock!
      Rails.logger.info "[Stripe] checkout.session.expired: Order #{order.id} cancelled and restocked"
    else
      Rails.logger.info "[Stripe] checkout.session.expired: Order #{order.id} not pending – skipping"
    end
  end

  # ---------- Core logic: marcar pedido como pago -------------------------

  def mark_order_paid(order_id, payment_reference:, amount_cents:, currency:, source:)
    unless order_id.present?
      Rails.logger.warn "[Stripe] #{source}: missing order_id metadata"
      return
    end

    order = Order.find_by(id: order_id)
    unless order
      Rails.logger.warn "[Stripe] #{source}: Order #{order_id} not found"
      return
    end

    # Audit M3: only mark paid when Stripe charged exactly this order's total in
    # BRL. A mismatch (wrong amount, other currency, missing data) is logged and
    # the order stays pending for manual review.
    expected_cents = (order.total_amount * 100).round.to_i
    unless amount_cents.to_i == expected_cents && currency.to_s.downcase == "brl"
      Rails.logger.error "[Stripe] #{source}: Order #{order.id} amount/currency mismatch " \
                         "(got #{amount_cents.inspect} #{currency.inspect}, expected #{expected_cents} brl) – NOT marking paid"
      return
    end

    # Check-and-act atômico: o lock serializa entregas concorrentes de eventos
    # distintos do mesmo pedido (checkout.session.completed + payment_intent.succeeded),
    # evitando e-mail de confirmação duplicado.
    newly_paid = false
    order.with_lock do
      if order.paid?
        Rails.logger.info "[Stripe] #{source}: Order #{order.id} already paid – skipping"
      elsif order.cancelled?
        # Paid after the reservation ended and the stock went back: do not flip it
        # to paid (the items may be sold again). Needs a manual refund or re-order.
        Rails.logger.error "[Stripe] #{source}: Order #{order.id} is CANCELLED but a payment arrived " \
                           "(ref=#{payment_reference}) – NOT marking paid, review and refund manually"
      else
        # mark_paid! continua sendo o ÚNICO ponto de escrita de payment_status=paid
        order.mark_paid!(method: "stripe", reference: payment_reference)
        newly_paid = true
        Rails.logger.info "[Stripe] #{source}: Order #{order.id} marcado como PAID, ref=#{payment_reference}"
      end
    end

    # Só envia e-mail se ESTE handler efetivou o pagamento (fora do lock)
    return unless newly_paid

    # Envia o e-mail de confirmação de pagamento
    begin
      OrderMailer.payment_confirmed(order).deliver_later
      Rails.logger.info "[Stripe] Sent payment confirmation email for order #{order.id}"
    rescue StandardError => e
      Rails.logger.error "[Stripe] Email error for order #{order.id}: #{e.class} - #{e.message}"
    end
  end

  # ---------- Idempotência com StripeWebhookEvent -------------------------

  def processed_event?(stripe_event_id)
    StripeWebhookEvent.exists?(stripe_event_id: stripe_event_id)
  end

  def mark_event_processed(stripe_event_id)
    StripeWebhookEvent.create!(stripe_event_id: stripe_event_id, processed_at: Time.current)
  rescue ActiveRecord::RecordNotUnique
    # Race condition: outro processo já gravou; idempotência garantida
    Rails.logger.info "[Stripe] Event #{stripe_event_id} already recorded (race)"
  end
end
