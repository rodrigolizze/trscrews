require "test_helper"

class Admin::ScrewsControllerTest < ActionDispatch::IntegrationTest
  def admin_auth_headers
    # Mirror Admin::BaseController#admin_credentials: blank ENV values (e.g. an
    # empty ADMIN_PASSWORD= in .env) fall back to "admin" in development/test.
    user = ENV["ADMIN_USER"].presence || "admin"
    pass = ENV["ADMIN_PASSWORD"].presence || "admin"
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

  test "saves the 3D shape fields" do
    screw = screws(:one)
    patch admin_screw_url(screw),
          params: { screw: { head_type: "torx_countersunk", seat_type: "flat", wrench_size: 13 } },
          headers: admin_auth_headers

    screw.reload
    assert_equal ["torx_countersunk", "flat", 13], [screw.head_type, screw.seat_type, screw.wrench_size]
  end

  test "edit form shows the shape fields and the live 3D preview" do
    get edit_admin_screw_url(screws(:one)), headers: admin_auth_headers

    assert_select "select[name='screw[head_type]'] option", text: "Torx escareada (disco de freio)"
    assert_select "select[name='screw[seat_type]']"
    assert_select "[data-controller~='screw-preview'][data-screw-preview-base-value]"
    assert_select "[data-controller~='screw-viewer'][data-screw-viewer-auto-open-value='true']"
  end
end
