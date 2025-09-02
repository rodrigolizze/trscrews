require "test_helper"

class CartControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get cart_show_url
    assert_response :success
  end

  test "should get add" do
    get cart_add_url
    assert_response :success
  end

  test "should get set" do
    get cart_set_url
    assert_response :success
  end

  test "should get remove" do
    get cart_remove_url
    assert_response :success
  end

  test "should get clear" do
    get cart_clear_url
    assert_response :success
  end
end
