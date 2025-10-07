# // Stripe global configuration (reads keys from ENV)
# // Required ENV (we'll add them next):
# //   STRIPE_SECRET_KEY         → server-side key (starts with "sk_")
# //   STRIPE_PUBLISHABLE_KEY    → client key (starts with "pk_")  [used later in views if needed]
# //   STRIPE_SIGNING_SECRET     → webhook signing secret (starts with "whsec_") [used in webhooks]
#
# // Tip: in development, put them in .env (dotenv-rails already in your project)

Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY", nil)

# // Optional but recommended: pin API version for consistent behavior
Stripe.api_version = "2024-06-20"  # // pick a recent, stable version

# // Identify your app in Stripe logs
Stripe.set_app_info(
  "TR AutoParts",
  version: "1.0.0",
  url: "https://example.com" # // update when you deploy
)

# // Convenience accessor so you can use it in views (if ever needed)
Rails.application.config.x.stripe_publishable_key = ENV["STRIPE_PUBLISHABLE_KEY"]

# // Safety: warn loudly in development if keys are missing
if Rails.env.development?
  missing = []
  missing << "STRIPE_SECRET_KEY"      if ENV["STRIPE_SECRET_KEY"].blank?
  missing << "STRIPE_PUBLISHABLE_KEY" if ENV["STRIPE_PUBLISHABLE_KEY"].blank?
  # STRIPE_SIGNING_SECRET will be needed when we wire webhooks
  Rails.logger.warn("[Stripe] Missing ENV: #{missing.join(', ')}") if missing.any?
end
