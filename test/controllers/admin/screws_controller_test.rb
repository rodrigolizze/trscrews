require "test_helper"

class Admin::ScrewsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_screws_index_url
    assert_response :success
  end

  test "should get edit" do
    get admin_screws_edit_url
    assert_response :success
  end

  test "should get update" do
    get admin_screws_update_url
    assert_response :success
  end
end
