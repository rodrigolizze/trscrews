require "test_helper"

class ScrewsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get screws_url
    assert_response :success
  end

  test "should get show" do
    screw = screws(:one)
    get screw_url(screw)
    assert_response :success
  end
end
