class ApplicationController < ActionController::Base
  include Pagy::Backend   # # gives us the pagy(...) method in controllers

  # // Expose helpers to views
  helper_method :cart_count

  before_action :load_cart

  private

  # // Ensure a Hash in the session: { "screw_id" => qty }
  def load_cart
    session[:cart] ||= {}
  end

  # // Total item count for navbar badge
  def cart_count
    session[:cart].values.map(&:to_i).sum
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
end
