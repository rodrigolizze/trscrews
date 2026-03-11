require "test_helper"

class Admin::ScrewsControllerTest < ActionDispatch::IntegrationTest
  def admin_auth_headers
    user = ENV.fetch("ADMIN_USER", "admin")
    pass = ENV.fetch("ADMIN_PASS", "admin")
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, pass) }
  end

  test "should get index" do
    get admin_screws_url, headers: admin_auth_headers
    assert_response :success
  end

  test "should get edit" do
    screw = screws(:one)
    get edit_admin_screw_url(screw), headers: admin_auth_headers
    assert_response :success
  end

  test "should get update" do
    screw = screws(:one)
    patch admin_screw_url(screw), params: { screw: { description: "Atualizado", price: 25, stock: 10 } }, headers: admin_auth_headers
    assert_response :redirect
    screw.reload
    assert_redirected_to admin_screw_path(screw)
  end
end
