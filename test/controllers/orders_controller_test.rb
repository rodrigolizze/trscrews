require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  # Regression for the recalc_totals! bug: `order_items.sum(:line_total)` issues a
  # SQL SUM() against an association whose rows are not inserted yet (recalc_totals!
  # runs before @order.save), so it returned 0 and every order was persisted with
  # subtotal = 0 and total = shipping. See RECALC_TOTALS_FIX.md.
  test "create persists subtotal matching the sum of its order items" do
    screw = screws(:one)   # price 15.00, stock 10
    quantity = 2

    post add_cart_url(screw_id: screw.id), params: { quantity: quantity }

    assert_difference "Order.count", 1 do
      post orders_url, params: {
        order: {
          customer_name:  "Cliente Teste",
          customer_email: "cliente@test.com",
          cep:            "01310-100",
          street:         "Avenida Paulista",
          number:         "1000",
          complement:     "",
          district:       "Bela Vista",
          city:           "São Paulo",
          state:          "SP"
        }
      }
    end

    order = Order.order(:id).last
    expected_subtotal = screw.price * quantity

    assert_equal expected_subtotal, order.order_items.sum(:line_total),
                 "os itens deveriam somar #{expected_subtotal}"
    assert_equal expected_subtotal, order.subtotal,
                 "subtotal gravado deveria refletir a soma dos itens, nao 0"
    assert_equal order.subtotal + order.shipping, order.total,
                 "total deveria ser subtotal + frete, nao apenas o frete"
  end

  test "create goes straight to payment and does not send the pending e-mail" do
    screw = screws(:one)
    post add_cart_url(screw_id: screw.id), params: { quantity: 1 }

    assert_no_enqueued_emails do
      post orders_url, params: {
        order: {
          customer_name: "Cliente Teste", customer_email: "cliente@test.com",
          cep: "01310-100", street: "Avenida Paulista", number: "1000", complement: "",
          district: "Bela Vista", city: "São Paulo", state: "SP"
        }
      }
    end

    order = Order.order(:id).last
    assert_redirected_to thank_you_order_path(order, pay: 1)
  end

  # Regression: the shipping fee came from the UF the customer picked, not from the
  # CEP, so a Manaus CEP with UF "SP" was charged the cheaper Sudeste fee.
  test "create rejects a CEP from another state and keeps the stock" do
    screw = screws(:one)
    post add_cart_url(screw_id: screw.id), params: { quantity: 1 }

    assert_no_difference ["Order.count", -> { screw.reload.stock }] do
      post orders_url, params: {
        order: {
          customer_name: "Cliente Teste", customer_email: "cliente@test.com",
          cep: "69005-010", street: "Avenida Eduardo Ribeiro", number: "10", complement: "",
          district: "Centro", city: "Manaus", state: "SP"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "não corresponde", response.body
  end

  test "create charges the fee of the region the CEP belongs to" do
    screw = screws(:one)
    post add_cart_url(screw_id: screw.id), params: { quantity: 1 }

    post orders_url, params: {
      order: {
        customer_name: "Cliente Teste", customer_email: "cliente@test.com",
        cep: "69005-010", street: "Avenida Eduardo Ribeiro", number: "10", complement: "",
        district: "Centro", city: "Manaus", state: "AM"
      }
    }

    order = Order.order(:id).last
    assert_equal Rails.configuration.x.shipping.region_fee_table[:norte], order.shipping_fee
  end
end
