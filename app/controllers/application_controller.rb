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
end
