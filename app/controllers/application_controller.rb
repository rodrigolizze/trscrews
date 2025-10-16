class ApplicationController < ActionController::Base
  include Pagy::Backend   # # gives us the pagy(...) method in controllers

  # // Expose helpers to views
  helper_method :cart_count

  before_action :load_cart

  # // Allow Devise to accept :name on sign up / profile update
  before_action :configure_permitted_parameters, if: :devise_controller?

  private

  # // Ensure a Hash in the session: { "screw_id" => qty }
  def load_cart
    session[:cart] ||= {}
  end

  # // Total item count for navbar badge
  def cart_count
    session[:cart].values.map(&:to_i).sum
  end

  # // UF -> região (bem simples; ajustável depois)
  def region_for_uf(uf)
    case uf.to_s.upcase
    when "SP","RJ","MG","ES"                            then :sudeste
    when "PR","SC","RS"                                 then :sul
    when "DF","GO","MT","MS"                            then :centro_oeste
    when "BA","SE","AL","PE","PB","RN","CE","PI","MA"   then :nordeste
    when "PA","AP","AM","RR","RO","AC","TO"             then :norte
    else :sudeste                                       # // fallback razoável
    end
  end

  # // Frete por região + grátis ≥ R$150
  def shipping_for(subtotal, uf:)
    return 0.to_d if subtotal.to_d >= 150.to_d          # // frete grátis
    table = {
      sudeste:       20.to_d,
      sul:           25.to_d,
      centro_oeste:  30.to_d,
      nordeste:      35.to_d,
      norte:         40.to_d
    }
    table.fetch(region_for_uf(uf), 20.to_d)             # // fallback 20
  end

  protected

  # // Basic Auth for /admin/*
  # // Reads ADMIN_USER / ADMIN_PASS from ENV (falls back to dev defaults).
  def require_admin_basic_auth
    user = ENV.fetch("ADMIN_USER", "admin")
    pass = ENV.fetch("ADMIN_PASS", "secret123")

    authenticate_or_request_with_http_basic("Admin") do |u, p|
      # // simple compare is fine for dev; we can harden later if you want
      ActiveSupport::SecurityUtils.secure_compare(u.to_s, user.to_s) &
      ActiveSupport::SecurityUtils.secure_compare(p.to_s, pass.to_s)
    end
  end

  # // Devise strong params
  def configure_permitted_parameters
    # // sign up form
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    # // account edit form
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end
end
