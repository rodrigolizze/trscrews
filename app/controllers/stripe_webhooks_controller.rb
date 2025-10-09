class StripeWebhooksController < ApplicationController
  # // Webhooks are machine-to-machine: no CSRF token, no HTML layout
  skip_before_action :verify_authenticity_token
  layout false

  # // Lightweight duplicate-event protection (swap to DB later if you want)
  IDEMPOTENCY_CACHE_TTL = 7.days

  # == Entry point ==========================================================
  def receive
    # // Read raw payload + signature header
    payload    = request.raw_post
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
    secret     = ENV["STRIPE_SIGNING_SECRET"]

    Rails.logger.info("[Stripe] Webhook received: bytes=#{payload.bytesize} sig_present=#{sig_header.present?}")

    # // In production we REQUIRE signature verification
    if Rails.env.production? && secret.blank?
      Rails.logger.error("[Stripe] STRIPE_SIGNING_SECRET missing in production")
      return head :unauthorized
    end

    # // Verify signature (or parse JSON in dev if no secret)
    event =
      if secret.present?
        Stripe::Webhook.construct_event(payload, sig_header, secret)
      else
        Rails.logger.warn("[Stripe] Parsing without signature verification (non-prod)")
        Stripe::Event.construct_from(JSON.parse(payload))
      end

    Rails.logger.info("[Stripe] Event verified: type=#{event['type']} id=#{event['id']}")

    # // Idempotency: skip if we already processed this event id
    if processed_event?(event.id)
      Rails.logger.info("[Stripe] Duplicate event id=#{event.id}; skipping")
      return head :ok
    end

    # -- Handle only the event types we care about --------------------------
    case event["type"]
    when "checkout.session.completed"
      session = event["data"]["object"]
      handle_checkout_session_completed(session)

    when "payment_intent.succeeded"
      intent = event["data"]["object"]
      handle_payment_intent_succeeded(intent)

    when "charge.succeeded"
      charge = event["data"]["object"]
      handle_charge_succeeded(charge)

    else
      Rails.logger.info("[Stripe] Ignored event type: #{event['type']}")
    end

    # // Mark this event as done (so retries won’t double-process)
    mark_event_processed(event.id)
    head :ok

  rescue JSON::ParserError => e
    Rails.logger.warn("[Stripe] Invalid JSON payload: #{e.message}")
    head :bad_request
  rescue Stripe::SignatureVerificationError => e
    Rails.logger.warn("[Stripe] Signature verification failed: #{e.message}")
    head :bad_request
  rescue => e
    # // Return 5xx so Stripe retries transient/unexpected failures
    Rails.logger.error("[Stripe] Webhook fatal: #{e.class} - #{e.message}\n#{(e.backtrace || [])[0,12].join("\n")}")
    head :internal_server_error
  end

  private

  # ---------- Event handlers ----------------------------------------------

  def handle_checkout_session_completed(session)
    # // Metadata lives in session.metadata (Stripe object, not a Hash)
    order_id    = safe_metadata_get(session, "order_id")
    pi_id       = normalize_payment_intent_id(session.respond_to?(:payment_intent) ? session.payment_intent : session["payment_intent"])
    payment_ref = pi_id || session_id(session)   # prefer PI id; fallback to "cs_..." if PI missing
    handle_payment_for_order!(order_id, payment_ref)
  end

  def handle_payment_intent_succeeded(intent)
    order_id    = safe_metadata_get(intent, "order_id")
    payment_ref = intent_id(intent)              # "pi_..."
    handle_payment_for_order!(order_id, payment_ref)
  end

  def handle_charge_succeeded(charge)
    order_id    = safe_metadata_get(charge, "order_id")
    pi_id       = normalize_payment_intent_id(charge.respond_to?(:payment_intent) ? charge.payment_intent : charge["payment_intent"])
    payment_ref = pi_id || charge_id(charge)     # prefer PI id; fallback to "ch_..."
    handle_payment_for_order!(order_id, payment_ref)
  end

  # ---------- Core business logic -----------------------------------------

  def handle_payment_for_order!(order_id, payment_ref)
    raise "missing_order_id_metadata" if order_id.blank?

    order = Order.find_by(id: order_id)
    raise "order_not_found #{order_id}" unless order

    # // Concurrency guard: process each order once under lock
    order.with_lock do
      Rails.logger.info("[Stripe] Marking order #{order.id} paid (ref=#{payment_ref})")

      # // Idempotency on the order: if already paid w/ same ref, skip
      already_paid =
        if order.respond_to?(:payment_status) && order.respond_to?(:paid?)
          order.paid? && order.payment_reference.to_s == payment_ref.to_s
        else
          order.payment_reference.to_s == payment_ref.to_s && order.paid_at.present?
        end
      if already_paid
        Rails.logger.info("[Stripe] Already paid; idempotent skip for order #{order.id}")
      else
        # // Prefer a public model API if present; otherwise update attrs inline
        if order.respond_to?(:mark_paid!) && order.public_methods(false).include?(:mark_paid!)
          order.mark_paid!(method: "stripe", reference: payment_ref)
        else
          attrs = {
            paid_at:           Time.current,
            payment_method:    "stripe",
            payment_reference: payment_ref
          }
          attrs[:payment_status] = :paid if order.respond_to?(:payment_status)
          order.update!(attrs)
        end
      end

      # // Enqueue the paid email (in dev with :inline, this sends immediately)
      Rails.logger.info("[Stripe] Enqueueing payment_received email for order #{order.id}")
      OrderMailer.payment_received(order).deliver_later
    end
  end

  # ---------- Helpers ------------------------------------------------------

  # // Reads metadata["key"] regardless of Stripe object vs Hash
  def safe_metadata_get(obj, key)
    md = if obj.respond_to?(:metadata)
           obj.metadata
         else
           obj["metadata"] rescue nil
         end
    md && (md.respond_to?(:[]) ? md[key] : md.try(:[], key))
  end

  def session_id(session)
    session.respond_to?(:id) ? session.id : session["id"]
  end

  def intent_id(intent)
    intent.respond_to?(:id) ? intent.id : intent["id"]
  end

  def charge_id(charge)
    charge.respond_to?(:id) ? charge.id : charge["id"]
  end

  # // Accepts a String "pi_..." or an expanded object; returns "pi_..." or nil
  def normalize_payment_intent_id(payment_intent)
    case payment_intent
    when String
      payment_intent
    else
      payment_intent.respond_to?(:id) ? payment_intent.id : (payment_intent && payment_intent["id"])
    end
  end

  # -- Very small idempotency cache (Rails.cache). Swap to DB if needed. ----
  def processed_event?(event_id)
    return false if event_id.blank?
    Rails.cache.read(cache_key_for_event(event_id)).present?
  end

  def mark_event_processed(event_id)
    return if event_id.blank?
    Rails.cache.write(cache_key_for_event(event_id), true, expires_in: IDEMPOTENCY_CACHE_TTL)
  end

  def cache_key_for_event(event_id)
    "stripe_webhook_event_processed:#{event_id}"
  end
end
