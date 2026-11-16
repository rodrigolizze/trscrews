require "test_helper"

# Teste (d) da Fase 3: revisitar a página de "obrigado" (success URL do Stripe
# Checkout) NÃO deve alterar payment_status.
#
# Escrito como controller test (ActionController::TestCase) para injetar
# session[:last_order_id] e passar pela Via 3 do authorize_thank_you!,
# reproduzindo o fluxo REAL do comprador guest (os pedidos pagos em produção
# não têm user_id). Ver STRIPE_FIX_PLAN.md §4.4 e a análise de terreno.
class OrdersThankYouTest < ActionController::TestCase
  tests OrdersController
  include Devise::Test::ControllerHelpers  # user_signed_in?/current_user seguros (guest => false/nil)
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  test "revisiting the thank_you page as a guest does not change payment_status" do
    order = orders(:one)
    assert_equal "pending", order.payment_status

    assert_enqueued_emails 0 do
      2.times do
        get :thank_you,
            params:  { id: order.id },
            session: { last_order_id: order.id }
        assert_response :success
      end
    end

    assert_equal "pending", order.reload.payment_status,
                 "a página de sucesso é somente-leitura; não deve escrever no banco"
  end

  # Back from Stripe with Pix: the order is still pending until the money arrives.
  # Showing "Pagar agora" there invited a second payment for the same order.
  test "returning from Stripe before the payment is confirmed shows confirming, not a pay button" do
    order = orders(:one)

    get :thank_you, params: { id: order.id, paid: 1 }, session: { last_order_id: order.id }

    assert_response :success
    assert_match "Pagamento em confirmação", response.body
    assert_no_match(/Pagar agora/, response.body)
  end

  test "the pay=1 link does not auto-open Stripe while a Pix is pending" do
    order = orders(:one)
    order.update!(payment_reference: "pi_pending_pix")

    get :thank_you, params: { id: order.id, pay: 1 }, session: { last_order_id: order.id }

    assert_response :success
    assert_match "Pagamento em confirmação", response.body
    assert_no_match(/Pagar agora/, response.body)
    assert_no_match(/auto-submit/, response.body)
  end
end
