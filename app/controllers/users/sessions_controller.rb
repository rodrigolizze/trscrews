# Audit A3: throttle customer sign-in attempts (Rails 8 rate_limit, no gem).
# Per-process memory store: the app runs a single Puma process.
class Users::SessionsController < Devise::SessionsController
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE,
             with: -> { redirect_to new_user_session_path, alert: "Muitas tentativas de login. Aguarde alguns minutos e tente de novo." }
end
