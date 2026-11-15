require "test_helper"

class UsersSessionsControllerTest < ActionDispatch::IntegrationTest
  setup { Users::SessionsController::RATE_LIMIT_STORE.clear }

  test "throttles sign-in attempts after 10 tries (audit A3)" do
    10.times do
      post user_session_url, params: { user: { email: "nobody@test.com", password: "wrong-password" } }
    end

    post user_session_url, params: { user: { email: "nobody@test.com", password: "wrong-password" } }
    assert_redirected_to new_user_session_path
    assert_equal "Muitas tentativas de login. Aguarde alguns minutos e tente de novo.", flash[:alert]
  end
end
