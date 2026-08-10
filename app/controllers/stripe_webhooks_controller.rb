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
      else
        Rails.logger.warn "[Stripe] Dev env: parsing event sem checar assinatura"
        Stripe::Event.construct_from(JSON.parse(payload))
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

    mark_order_paid(order_id,
                    payment_reference: session["payment_intent"] || session["id"],
                    source: "checkout.session.completed")
  end

  def handle_payment_intent_succeeded(intent)
    metadata = intent["metadata"] || {}
    order_id = metadata["order_id"]

    mark_order_paid(
      order_id,
      payment_reference: intent["id"],
      source: "payment_intent.succeeded"
    )
  end

  # ---------- Core logic: marcar pedido como pago -------------------------

  def mark_order_paid(order_id, payment_reference:, source:)
    unless order_id.present?
      Rails.logger.warn "[Stripe] #{source}: missing order_id metadata"
      return
    end

    order = Order.find_by(id: order_id)
    unless order
      Rails.logger.warn "[Stripe] #{source}: Order #{order_id} not found"
      return
    end

    # Check-and-act atômico: o lock serializa entregas concorrentes de eventos
    # distintos do mesmo pedido (checkout.session.completed + payment_intent.succeeded),
    # evitando e-mail de confirmação duplicado.
    newly_paid = false
    order.with_lock do
      if order.paid?
        Rails.logger.info "[Stripe] #{source}: Order #{order.id} already paid – skipping"
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
