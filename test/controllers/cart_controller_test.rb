require "test_helper"

class CartControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get cart_url
    assert_response :success
  end

  test "should get add" do
    screw = screws(:one)
    post add_cart_url(screw_id: screw.id)
    assert_redirected_to cart_url
  end

  test "should get set" do
    screw = screws(:one)
    patch set_cart_url(screw_id: screw.id), params: { quantity: 1 }
    assert_redirected_to cart_url
  end

  test "should get remove" do
    screw = screws(:one)
    delete remove_cart_url(screw_id: screw.id)
    assert_redirected_to cart_url
  end

  test "should get clear" do
    delete clear_cart_url
    assert_redirected_to cart_url
  end

  test "cart without a CEP asks for one instead of showing a guessed fee" do
    post add_cart_url(screw_id: screws(:one).id)
    get cart_url

    assert_select "form[action=?]", shipping_cart_path
    assert_match "Informe o CEP", response.body
  end

  test "shipping estimate stores the CEP and shows the fee for its region" do
    post add_cart_url(screw_id: screws(:one).id)
    post shipping_cart_url, params: { cep: "69005010" }
    assert_redirected_to cart_url

    get cart_url
    fee = Rails.configuration.x.shipping.region_fee_table[:norte]
    assert_match "69005-010", response.body
    assert_match "Norte", response.body
    assert_match ActiveSupport::NumberHelper.number_to_currency(fee, unit: "R$ ", separator: ",", delimiter: "."), response.body
  end

  test "shipping estimate rejects an unknown CEP" do
    post shipping_cart_url, params: { cep: "123" }
    assert_redirected_to cart_url
    assert_match "CEP", flash[:alert].to_s
  end
end
