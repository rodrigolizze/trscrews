require "test_helper"

class ShippingAddressTest < ActiveSupport::TestCase
  def build_address(cep:, state:)
    users(:one).shipping_addresses.new(
      recipient_name: "Cliente", cep: cep, street: "Rua A", number: "1",
      district: "Centro", city: "Cidade", state: state
    )
  end

  test "is valid when the state matches the CEP" do
    assert build_address(cep: "69005-010", state: "AM").valid?
  end

  test "rejects a state that does not match the CEP" do
    address = build_address(cep: "69005-010", state: "SP")
    assert_not address.valid?
    assert_match "não corresponde", address.errors.full_messages.join
  end
end
