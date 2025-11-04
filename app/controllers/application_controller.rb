class ApplicationController < ActionController::Base
  include Pagy::Backend   # # gives us the pagy(...) method in controllers

  # // Expose helpers to views
  helper_method :cart_count

  before_action :load_cart

  # // Allow Devise to accept :name on sign up / profile update
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :ensure_first_address_created

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
    map = Rails.configuration.x.shipping.uf_region_map
    map[uf.to_s.upcase] || :sudeste   # // fallback stays sudeste
  end

  # // Frete por região + grátis ≥ R$150
  def shipping_for(subtotal, uf:)
    free_limit = Rails.configuration.x.shipping.free_limit
    return 0.to_d if subtotal.to_d >= free_limit

    table = Rails.configuration.x.shipping.region_fee_table
    table.fetch(region_for_uf(uf), table[:sudeste])  # // fallback fee
  end

  def ensure_first_address_created
    # // Only enforce for authenticated users
    return unless defined?(user_signed_in?) && user_signed_in?

    # // Let Devise routes work (sign in/out/up, confirmations, etc.)
    return if respond_to?(:devise_controller?) && devise_controller?

    # // If the user has zero addresses, only allow shipping_addresses#new/create
    if current_user.shipping_addresses.none?
      is_addresses = controller_path == "shipping_addresses"
      is_allowed_action = %w[new create].include?(action_name)

      return if is_addresses && is_allowed_action  # // allow the form + submit

      # // Otherwise, push them to create the first address
      redirect_to new_shipping_address_path(return_to: "checkout"),
                  alert: "Cadastre seu primeiro endereço para continuar." and return
    end
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
