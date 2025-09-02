# config/initializers/pagy.rb
# Require the Bootstrap extra so we can use pagy_bootstrap_nav in the view
require "pagy/extras/bootstrap"

# Optional: default items per page
Pagy::DEFAULT[:items] = 12
