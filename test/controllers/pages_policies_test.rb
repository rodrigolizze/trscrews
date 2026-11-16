require "test_helper"

class PagesPoliciesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Company data comes from ENV at boot; tests swap the config and restore it.
  def with_company(**values)
    original = Rails.configuration.x.company.dup
    values.each { |k, v| Rails.configuration.x.company[k] = v }
    yield
  ensure
    Rails.configuration.x.company = original
  end

  test "policy pages render for visitors" do
    [returns_policy_path, privacy_policy_path, terms_of_use_path].each do |path|
      get path
      assert_response :success, path
      assert_select "h1.policy-d__title"
    end
  end

  test "footer links to the three policies" do
    get root_path
    assert_select "footer a[href=?]", returns_policy_path
    assert_select "footer a[href=?]", privacy_policy_path
    assert_select "footer a[href=?]", terms_of_use_path
  end

  test "footer hides company data that is not configured" do
    with_company(legal_name: nil, cnpj: nil, address: nil, email: nil, whatsapp: nil) do
      get root_path
      assert_select ".site-footer__company", count: 0
      assert_no_match "CNPJ", response.body
    end
  end

  test "footer shows company data once configured" do
    with_company(legal_name: "Empresa Exemplo LTDA", cnpj: "00.000.000/0001-00",
                 address: "Rua Exemplo, 1 - São Paulo/SP", email: "contato@example.com", whatsapp: "(11) 90000-0000") do
      get root_path
      assert_select ".site-footer__company", text: /Empresa Exemplo LTDA, CNPJ 00\.000\.000\/0001-00/
      assert_select ".site-footer__company a[href=?]", "mailto:contato@example.com"
      assert_select ".site-footer__company a[href=?]", "https://wa.me/5511900000000"
    end
  end

  test "terms show the configured free-shipping threshold" do
    get terms_of_use_path
    limit = Rails.configuration.x.shipping.free_limit
    assert_match ActiveSupport::NumberHelper.number_to_currency(limit, unit: "R$ ", separator: ",", delimiter: "."), response.body
  end

  test "signed-in customer without an address can still read the policies" do
    user = users(:one)
    user.shipping_addresses.destroy_all
    sign_in user

    get privacy_policy_path
    assert_response :success
  end
end
