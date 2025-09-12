class Admin::BaseController < ApplicationController
  before_action :require_admin_basic_auth  # // enforce auth on all admin pages

  private

  def require_admin_basic_auth
    user = ENV.fetch("ADMIN_USER", "admin")
    pass = ENV.fetch("ADMIN_PASS", "admin")

    authenticate_or_request_with_http_basic("Trscrews Admin") do |u, p|
      ActiveSupport::SecurityUtils.secure_compare(u.to_s, user.to_s) &&
        ActiveSupport::SecurityUtils.secure_compare(p.to_s, pass.to_s)
    end
  end
end
