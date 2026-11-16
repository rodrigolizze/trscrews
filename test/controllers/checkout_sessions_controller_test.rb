require "test_helper"
require "minitest/mock"

class CheckoutSessionsControllerTest < ActionDispatch::IntegrationTest
  # Creates an order through the real checkout so session[:last_order_id] lets
  # this browser pay it, then captures the params sent to Stripe (never called).
  def place_order
    post add_cart_url(screw_id: screws(:one).id), params: { quantity: 1 }
    post orders_url, params: { order: {
      customer_name: "Cliente", customer_email: "cliente@test.com", cep: "01310-100",
      street: "Avenida Paulista", number: "1000", district: "Bela Vista", city: "São Paulo"
    } }
    Order.order(:id).last
  end

  def create_session_capturing_params(order)
    captured = nil
    fake = Struct.new(:url).new("https://checkout.stripe.com/c/pay/test")
    Stripe::Checkout::Session.stub(:create, ->(params, *_) { captured = params; fake }) do
      post checkout_sessions_url(order_id: order.id)
    end
    captured
  end

  test "the Pix code expires before the stock reservation does" do
    order = place_order
    params = create_session_capturing_params(order)

    assert_redirected_to "https://checkout.stripe.com/c/pay/test"
    pix_seconds = params.dig(:payment_method_options, :pix, :expires_after_seconds)
    assert pix_seconds, "esperava a validade do Pix definida"
    assert Time.current + pix_seconds <= order.payment_deadline,
           "o Pix não pode valer além da reserva de estoque"
  end
end
