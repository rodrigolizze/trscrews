require "test_helper"

class OrderTest < ActiveSupport::TestCase
  test "expire_and_restock! cancels an unpaid order and puts its items back in stock" do
    order = orders(:one) # placed, pending; items: screw one x2, screw two x1
    stock_one = screws(:one).stock
    stock_two = screws(:two).stock

    assert order.expire_and_restock!, "esperava true na primeira chamada"

    order.reload
    assert order.cancelled?
    assert_equal "failed", order.payment_status
    assert_equal stock_one + 2, screws(:one).reload.stock
    assert_equal stock_two + 1, screws(:two).reload.stock
  end

  test "expire_and_restock! is idempotent and does not restock twice" do
    order = orders(:one)
    stock_one = screws(:one).stock

    assert order.expire_and_restock!
    assert_not order.reload.expire_and_restock!, "segunda chamada deve ser no-op"
    assert_equal stock_one + 2, screws(:one).reload.stock
  end

  test "expire_and_restock! leaves a paid order untouched" do
    order = orders(:one)
    order.mark_paid!(method: "stripe", reference: "pi_paid")
    stock_one = screws(:one).stock

    assert_not order.expire_and_restock!
    assert order.reload.paid?
    assert order.placed?
    assert_equal stock_one, screws(:one).reload.stock
  end

  test "expired_unpaid only returns pending orders past the payment window plus grace" do
    old = orders(:one)
    old.update_columns(placed_at: (Order::PAYMENT_WINDOW + Order::EXPIRY_GRACE + 1.minute).ago)
    fresh = orders(:two) # placed now

    ids = Order.expired_unpaid.pluck(:id)
    assert_includes ids, old.id
    assert_not_includes ids, fresh.id
  end

  test "payment_deadline is placed_at plus the payment window" do
    order = orders(:one)
    assert_equal order.placed_at + Order::PAYMENT_WINDOW, order.payment_deadline
  end

  # Regression: shipping is priced by the UF, which the server used to take from the
  # form. A Manaus CEP with UF "SP" paid the Sudeste fee and still shipped to Manaus.
  test "a new order takes its state from the CEP, not from what was typed" do
    order = orders(:one).dup
    order.order_number = nil
    order.cep = "69005-010"   # Manaus/AM
    order.state = "SP"

    assert order.valid?, order.errors.full_messages.to_sentence
    assert_equal "AM", order.state
  end

  test "rejects a new order with an unassigned CEP" do
    order = orders(:one).dup
    order.order_number = nil
    order.cep = "00999-999"

    assert_not order.valid?
    assert_match "CEP não encontrado", order.errors.full_messages.join
  end

  test "still lets an existing order with a mismatched address be marked paid" do
    order = orders(:one)
    order.update_columns(cep: "69005-010", state: "SP") # legacy data, before the check

    assert_nothing_raised { order.mark_paid!(method: "stripe", reference: "pi_legacy") }
    assert order.reload.paid?
  end
end
