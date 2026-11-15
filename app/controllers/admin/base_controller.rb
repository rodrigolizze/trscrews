class Admin::BaseController < ApplicationController
  before_action :require_admin_basic_auth  # // enforce auth on all admin pages

  # Audit A3: failed Basic Auth attempts per IP. Per-process memory store: the
  # app runs a single Puma process; move to a shared cache if it scales out.
  AUTH_FAILURE_STORE = ActiveSupport::Cache::MemoryStore.new
  MAX_AUTH_FAILURES  = 10
  AUTH_FAILURE_WINDOW = 15.minutes

  private

  def require_admin_basic_auth
    user, pass = admin_credentials
    if user.nil?
      # Audit A2: no "admin"/"admin" fallback outside development/test.
      Rails.logger.error "[Admin] ADMIN_USER/ADMIN_PASSWORD missing – admin locked"
      return head :service_unavailable
    end

    failure_key = "admin-auth-fail:#{request.remote_ip}"
    if AUTH_FAILURE_STORE.read(failure_key).to_i >= MAX_AUTH_FAILURES
      return head :too_many_requests
    end

    authenticated = authenticate_with_http_basic do |u, p|
      ActiveSupport::SecurityUtils.secure_compare(u.to_s, user) &
        ActiveSupport::SecurityUtils.secure_compare(p.to_s, pass)
    end
    if authenticated
      AUTH_FAILURE_STORE.delete(failure_key)
      return
    end

    # Count only real attempts: the browser's first request carries no credentials.
    if request.authorization.present?
      count = AUTH_FAILURE_STORE.read(failure_key).to_i + 1
      AUTH_FAILURE_STORE.write(failure_key, count, expires_in: AUTH_FAILURE_WINDOW)
    end
    request_http_basic_authentication("TR AutoFix Admin")
  end

  def admin_credentials
    user = ENV["ADMIN_USER"].presence
    pass = ENV["ADMIN_PASSWORD"].presence
    return [user, pass] if user && pass
    return [user || "admin", pass || "admin"] if Rails.env.local?

    [nil, nil]
  end
end
