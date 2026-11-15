require "test_helper"
require "minitest/mock"

class Admin::BaseControllerTest < ActionDispatch::IntegrationTest
  setup { Admin::BaseController::AUTH_FAILURE_STORE.clear }

  def basic_auth(user, pass)
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, pass) }
  end

  test "asks for credentials without counting a failure" do
    get admin_screws_url
    assert_response :unauthorized
  end

  test "blocks an IP after too many wrong passwords (audit A3)" do
    Admin::BaseController::MAX_AUTH_FAILURES.times do
      get admin_screws_url, headers: basic_auth("admin", "wrong-password")
      assert_response :unauthorized
    end

    get admin_screws_url, headers: basic_auth("admin", "wrong-password")
    assert_response :too_many_requests
  end

  test "locks the admin in production when credentials are not configured (audit A2)" do
    previous_user = ENV.delete("ADMIN_USER")
    previous_pass = ENV.delete("ADMIN_PASSWORD")
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      get admin_screws_url, headers: basic_auth("admin", "admin")
    end
    ENV["ADMIN_USER"] = previous_user if previous_user
    ENV["ADMIN_PASSWORD"] = previous_pass if previous_pass

    assert_response :service_unavailable
  end
end
