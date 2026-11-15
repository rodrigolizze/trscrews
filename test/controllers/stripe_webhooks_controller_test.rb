require "test_helper"
require "minitest/mock"  # habilita Object#stub (usado para stubar Stripe::Webhook.construct_event)

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  WEBHOOK_PATH = "/stripe/webhooks".freeze

  # Payload no formato mínimo que o controller lê (type, id, data.object).
  def webhook_payload(id:, type:, object:)
    { "id" => id, "type" => type, "data" => { "object" => object } }
  end

  # Entrega um evento ao endpoint. A verificação de assinatura é código da
  # Stripe (não nosso), então stubamos construct_event para devolver o mesmo
  # objeto que ele devolveria em produção (Stripe::Event.construct_from).
  # O corpo/assinatura do POST são ignorados pelo stub.
  def deliver_webhook(payload)
    event = Stripe::Event.construct_from(payload)
    Stripe::Webhook.stub(:construct_event, event) do
      post WEBHOOK_PATH,
           params: payload.to_json,
           headers: { "CONTENT_TYPE"     => "application/json",
                      "Stripe-Signature" => "t=0,v1=ignored-because-stubbed" }
    end
  end

  # (a) ---------------------------------------------------------------------
  test "marks the order as paid once from a payment_intent.succeeded event" do
    order = orders(:one)
    assert_equal "pending", order.payment_status

    payload = webhook_payload(
      id:   "evt_1",
      type: "payment_intent.succeeded",
      object: { "id" => "pi_test_1", "amount" => 7200, "currency" => "brl", "metadata" => { "order_id" => order.id.to_s } }
    )

    assert_enqueued_emails 1 do
      deliver_webhook(payload)
    end

    assert_response :ok
    order.reload
    assert order.paid?, "esperava o pedido marcado como paid"
    assert_equal "pi_test_1", order.payment_reference
    assert_equal "stripe",    order.payment_method
    assert StripeWebhookEvent.exists?(stripe_event_id: "evt_1"),
           "esperava o evento registrado para idempotência"
  end

  # (b) ---------------------------------------------------------------------
  test "does not reprocess a duplicate event with the same event id" do
    order   = orders(:one)
    payload = webhook_payload(
      id:   "evt_1",
      type: "payment_intent.succeeded",
      object: { "id" => "pi_test_1", "amount" => 7200, "currency" => "brl", "metadata" => { "order_id" => order.id.to_s } }
    )

    assert_enqueued_emails 1 do
      2.times { deliver_webhook(payload) }
    end

    assert_response :ok
    assert_equal 1, StripeWebhookEvent.where(stripe_event_id: "evt_1").count,
                 "evento duplicado não deve criar 2 registros"
    assert orders(:one).reload.paid?
  end

  # (c) ---------------------------------------------------------------------
  # CASO SEQUENCIAL. O guard `order.paid?` (stripe_webhooks_controller.rb:92)
  # cobre este cenário quando os dois eventos chegam em sequência.
  #
  # A CORRIDA CONCORRENTE real (dois handlers lendo paid? == false ao mesmo
  # tempo) NÃO é reproduzida aqui — depende do with_lock (Passo 4) e exigiria
  # threads + conexões de banco separadas (use_transactional_tests = false).
  #
  # NOTA (RED até Fix 0): enquanto o bug do `.dig` em
  # handle_checkout_session_completed não for corrigido, evt_A
  # (checkout.session.completed) retorna 500 e não é registrado, fazendo a
  # asserção de "2 registros" FALHAR (conta 1, só evt_B). Vira GREEN após o Fix 0.
  test "does not send a duplicate email for two distinct events of the same order" do
    order = orders(:one)

    evt_a = webhook_payload(
      id:   "evt_A",
      type: "checkout.session.completed",
      object: { "id" => "cs_A", "amount_total" => 7200, "currency" => "brl", "metadata" => { "order_id" => order.id.to_s } }
    )
    evt_b = webhook_payload(
      id:   "evt_B",
      type: "payment_intent.succeeded",
      object: { "id" => "pi_B", "amount" => 7200, "currency" => "brl", "metadata" => { "order_id" => order.id.to_s } }
    )

    assert_enqueued_emails 1 do
      deliver_webhook(evt_a)
      deliver_webhook(evt_b)
    end

    order.reload
    assert order.paid?, "esperava o pedido marcado como paid"
    assert_equal 2, StripeWebhookEvent.where(stripe_event_id: %w[evt_A evt_B]).count,
                 "ambos os eventos distintos devem ser registrados"
  end

  # (e) ---------------------------------------------------------------------
  # Isola o bug do `.dig`: um único evento checkout.session.completed deveria
  # marcar o pedido como paid. HOJE retorna 500 (NoMethodError: StripeObject
  # não implementa #dig em handle_checkout_session_completed) => RED.
  # Vira GREEN após o Fix 0 (trocar session.dig("metadata","order_id") por
  # acesso via colchetes, como já faz handle_payment_intent_succeeded).
  test "(e) checkout.session.completed marks order paid (currently 500 due to dig bug - RED until Fix 0)" do
    order = orders(:two)
    assert_equal "pending", order.payment_status

    payload = webhook_payload(
      id:   "evt_C_only",
      type: "checkout.session.completed",
      object: { "id" => "cs_C_only", "amount_total" => 2000, # orders(:two): no items, shipping only (R$ 20,00)
                "currency" => "brl", "metadata" => { "order_id" => order.id.to_s } }
    )

    assert_enqueued_emails 1 do
      deliver_webhook(payload)
      assert_response :ok  # RED até Fix 0: hoje 500 (StripeObject não tem #dig)
    end

    order.reload
    assert order.paid?, "esperava o pedido marcado como paid via checkout.session.completed"
    assert StripeWebhookEvent.exists?(stripe_event_id: "evt_C_only"),
           "esperava o evento registrado para idempotência"
  end

  # (f) ---------------------------------------------------------------------
  test "checkout.session.expired cancels the unpaid order and restocks its items" do
    order = orders(:one)
    stock_one = screws(:one).stock

    payload = webhook_payload(
      id:   "evt_expired_1",
      type: "checkout.session.expired",
      object: { "id" => "cs_test_expired", "metadata" => { "order_id" => order.id.to_s } }
    )

    assert_enqueued_emails 0 do
      deliver_webhook(payload)
    end

    assert_response :ok
    order.reload
    assert order.cancelled?, "esperava o pedido cancelado"
    assert_equal "failed", order.payment_status
    assert_equal stock_one + 2, screws(:one).reload.stock, "esperava o estoque devolvido"
  end

  test "checkout.session.expired does nothing to an order already paid" do
    order = orders(:one)
    order.mark_paid!(method: "stripe", reference: "pi_paid_before_expiry")
    stock_one = screws(:one).stock

    payload = webhook_payload(
      id:   "evt_expired_2",
      type: "checkout.session.expired",
      object: { "id" => "cs_test_old_session", "metadata" => { "order_id" => order.id.to_s } }
    )
    deliver_webhook(payload)

    assert_response :ok
    assert order.reload.paid?
    assert_equal stock_one, screws(:one).reload.stock
  end

  # (g) audit M3 -------------------------------------------------------------
  test "does not mark paid when the charged amount differs from the order total" do
    order = orders(:one)
    payload = webhook_payload(
      id: "evt_wrong_amount", type: "payment_intent.succeeded",
      object: { "id" => "pi_cheap", "amount" => 100, "currency" => "brl",
                "metadata" => { "order_id" => order.id.to_s } }
    )

    assert_enqueued_emails 0 do
      deliver_webhook(payload)
    end
    assert_response :ok
    assert_equal "pending", order.reload.payment_status
  end

  test "does not mark paid when the currency is not BRL" do
    order = orders(:one)
    payload = webhook_payload(
      id: "evt_wrong_currency", type: "checkout.session.completed",
      object: { "id" => "cs_usd", "amount_total" => 7200, "currency" => "usd",
                "metadata" => { "order_id" => order.id.to_s } }
    )

    deliver_webhook(payload)
    assert_response :ok
    assert_equal "pending", order.reload.payment_status
  end

  # (h) audit A1 -------------------------------------------------------------
  test "rejects unsigned events in production when the signing secret is missing" do
    order = orders(:one)
    payload = webhook_payload(
      id: "evt_unsigned", type: "payment_intent.succeeded",
      object: { "id" => "pi_forged", "amount" => 7200, "currency" => "brl",
                "metadata" => { "order_id" => order.id.to_s } }
    )

    previous = ENV.delete("STRIPE_SIGNING_SECRET")
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      post WEBHOOK_PATH, params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    end
    ENV["STRIPE_SIGNING_SECRET"] = previous if previous

    assert_response :internal_server_error
    assert_equal "pending", order.reload.payment_status
    assert_not StripeWebhookEvent.exists?(stripe_event_id: "evt_unsigned")
  end
end
