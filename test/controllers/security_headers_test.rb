require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "sends the content security policy in report-only mode (audit M1)" do
    get root_url
    assert_response :success
    csp = response.headers["Content-Security-Policy-Report-Only"]
    assert csp.present?, "esperava o cabeçalho CSP report-only"
    assert_includes csp, "object-src 'none'"
    assert_includes csp, "form-action 'self' https://checkout.stripe.com"
  end

  test "password reset does not reveal whether the e-mail has an account (audit B1)" do
    post user_password_url, params: { user: { email: "ninguem-cadastrado@test.com" } }
    assert_redirected_to new_user_session_path
    assert_equal I18n.t("devise.passwords.send_paranoid_instructions"), flash[:notice]
  end

  test "throttles CEP lookups per IP (audit B2)" do
    # Invalid CEPs answer locally (no ViaCEP call) but still count for the limit.
    30.times { get cep_lookup_url(cep: "123") }
    get cep_lookup_url(cep: "123")
    assert_response :too_many_requests
  end
end
