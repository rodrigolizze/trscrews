class Admin::BaseController < ApplicationController
  # // Protect /admin with HTTP Basic. In production, set ENV vars.
  if Rails.env.production?
    http_basic_authenticate_with name: ENV.fetch("ADMIN_USER"), password: ENV.fetch("ADMIN_PASS")
  else
    # // Dev fallback so you can test locally: admin / admin
    http_basic_authenticate_with name: ENV.fetch("ADMIN_USER", "admin"),
                                 password: ENV.fetch("ADMIN_PASS", "admin")
  end
end
