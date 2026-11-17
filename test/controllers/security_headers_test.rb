require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "enforces the content security policy (audit M1, phase 2)" do
    get root_url
    assert_response :success
    assert_nil response.headers["Content-Security-Policy-Report-Only"],
               "a CSP não deveria mais estar só em modo de observação"
    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "esperava o cabeçalho CSP aplicado"
    assert_includes csp, "object-src 'none'"
    assert_includes csp, "form-action 'self' https://checkout.stripe.com"
  end

  # Regression: enforcing the CSP blocked the address form's CEP autofill, which
  # fetches ViaCEP from the browser ("Failed to fetch" on /shipping_addresses/new).
  test "allows the browser to reach ViaCEP for the address autofill" do
    get root_url
    connect_src = response.headers["Content-Security-Policy"][/connect-src [^;]+/]
    assert_includes connect_src, "https://viacep.com.br"
  end

  # The old 3D model (screw.glb + Draco decoder) needed WebAssembly and blob:
  # sources; it is gone, so the policy must not keep those doors open.
  test "does not allow WebAssembly or blob: sources" do
    get root_url
    csp = response.headers["Content-Security-Policy"]
    assert_not_includes csp, "wasm-unsafe-eval"
    assert_not_includes csp, "blob:"
  end

  test "every inline script carries the CSP nonce, even on a first visit" do
    get root_url
    nonce = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]
    assert nonce.present?, "esperava um nonce no script-src"

    inline_scripts = css_select("script:not([src])")
    assert inline_scripts.any?
    inline_scripts.each do |script|
      assert_equal nonce, script["nonce"], "script inline sem nonce seria bloqueado: #{script.to_html[0, 80]}"
    end
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
