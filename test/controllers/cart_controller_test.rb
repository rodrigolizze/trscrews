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
end
