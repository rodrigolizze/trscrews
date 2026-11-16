require "test_helper"

class ShippingAddressesFormTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the address form shows the UF read-only and does not submit it" do
    sign_in users(:one)
    get new_shipping_address_path

    assert_response :success
    assert_select "input[readonly][data-cep-target=state]"
    assert_select "[name='shipping_address[state]']", count: 0
  end

  test "saving an address ignores a UF sent by hand and uses the CEP" do
    sign_in users(:one)

    post shipping_addresses_path, params: {
      shipping_address: {
        recipient_name: "Rodrigo", cep: "02340-001", street: "Avenida Nova Cantareira",
        number: "1", district: "Tucuruvi", city: "São Paulo", state: "PB"
      }
    }

    assert_equal "SP", users(:one).shipping_addresses.order(:id).last.state
  end
end
