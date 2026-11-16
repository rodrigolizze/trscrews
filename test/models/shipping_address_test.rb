require "test_helper"

class ShippingAddressTest < ActiveSupport::TestCase
  def build_address(cep:, state:)
    users(:one).shipping_addresses.new(
      recipient_name: "Cliente", cep: cep, street: "Rua A", number: "1",
      district: "Centro", city: "Cidade", state: state
    )
  end

  test "takes its state from the CEP, not from what was typed" do
    address = build_address(cep: "69005-010", state: "SP")
    assert address.valid?, address.errors.full_messages.to_sentence
    assert_equal "AM", address.state
  end

  test "fills the state from the CEP when none is given" do
    address = build_address(cep: "40026-032", state: nil)
    assert address.valid?, address.errors.full_messages.to_sentence
    assert_equal "BA", address.state
  end

  test "rejects an unassigned CEP" do
    address = build_address(cep: "00999-999", state: nil)
    assert_not address.valid?
    assert_match "CEP não encontrado", address.errors.full_messages.join
  end
end
