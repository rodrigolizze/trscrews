require "test_helper"

class ScrewsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get screws_index_url
    assert_response :success
  end

  test "should get show" do
    get screws_show_url
    assert_response :success
  end
end
