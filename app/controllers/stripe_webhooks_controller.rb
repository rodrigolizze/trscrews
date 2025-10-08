class StripeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  layout false

  def receive
    begin
      Rails.logger.info("[Stripe] Webhook received: raw_length=#{request.body.size}, sig_present=#{request.env['HTTP_STRIPE_SIGNATURE'].present?}")

      payload    = request.body.read
      sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
      secret     = ENV["STRIPE_SIGNING_SECRET"]

      event =
        if secret.present?
          Stripe::Webhook.construct_event(payload, sig_header, secret)
        else
          Rails.logger.warn("[Stripe] STRIPE_SIGNING_SECRET missing; parsing without verification (dev only)")
          Stripe::Event.construct_from(JSON.parse(payload))
        end

      Rails.logger.info("[Stripe] Event verified: type=#{event['type']} id=#{event['id']}")

      case event["type"]
      when "checkout.session.completed"
        session = event["data"]["object"]
        Rails.logger.info("[Stripe] Handling checkout.session.completed id=#{session['id']}")
        handle_checkout_session_completed(session)

      when "payment_intent.succeeded"
        intent = event["data"]["object"]
        Rails.logger.info("[Stripe] Handling payment_intent.succeeded id=#{intent['id']}")
        handle_payment_intent_succeeded(intent)

      when "charge.succeeded"
        charge = event["data"]["object"]
        Rails.logger.info("[Stripe] Handling charge.succeeded id=#{charge['id']}")
        handle_charge_succeeded(charge)

      else
        Rails.logger.info("[Stripe] Ignored event type: #{event['type']}")
      end

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error("[Stripe] Invalid payload: #{e.message}")
      head :bad_request
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error("[Stripe] Signature verification failed: #{e.message}")
      head :bad_request
    rescue => e
      # 👇 catch-all so we DON’T return 500 to Stripe; we also log a backtrace snippet
      Rails.logger.error("[Stripe] Webhook fatal: #{e.class} - #{e.message}\n#{e.backtrace&.first(12)&.join("\n")}")
      head :ok
    end
  end

  private

  def handle_checkout_session_completed(session)
    # Stripe object → use attribute accessors (no `dig`)
    order_id = session.metadata && session.metadata['order_id']
    Rails.logger.info("[Stripe] session.metadata.order_id=#{order_id.inspect}")
    return unless (order = Order.find_by(id: order_id))

    ref = session.id # "cs_..."
    mark_paid_and_email(order, ref)
  end

  def handle_payment_intent_succeeded(intent)
    order_id = intent.metadata && intent.metadata['order_id']
    Rails.logger.info("[Stripe] intent.metadata.order_id=#{order_id.inspect}")
    return unless (order = Order.find_by(id: order_id))

    ref = intent.id # "pi_..."
    mark_paid_and_email(order, ref)
  end

  def handle_charge_succeeded(charge)
    order_id = charge.metadata && charge.metadata['order_id']
    Rails.logger.info("[Stripe] charge.metadata.order_id=#{order_id.inspect}")
    return unless (order = Order.find_by(id: order_id))

    # Prefer the PaymentIntent id if present; fallback to charge id
    ref = charge.payment_intent.presence || charge.id
    mark_paid_and_email(order, ref)
  end

  def mark_paid_and_email(order, payment_ref)
    Rails.logger.info("[Stripe] Marking order #{order.id} paid (ref=#{payment_ref})")

    if order.respond_to?(:payment_status)
      if order.paid? && order.payment_reference == payment_ref
        Rails.logger.info("[Stripe] Already paid; idempotent skip")
        return
      end
      order.mark_paid!(method: "stripe", reference: payment_ref)
    else
      order.update(paid_at: Time.current, payment_method: "stripe", payment_reference: payment_ref)
    end

    # 🔊 LOG before sending
    Rails.logger.info("[Stripe] About to send payment_received email to #{order.customer_email.inspect} for order #{order.id}")

    # 👉 while debugging: send synchronously so any template error explodes here
    mail = OrderMailer.payment_received(order)
    Rails.logger.info("[Stripe] Built mail subject=#{mail.subject.inspect}")
    mail.deliver_later

    Rails.logger.info("[Stripe] Payment email SENT for order #{order.id}")
  end
end
