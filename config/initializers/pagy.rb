# config/initializers/pagy.rb
# Require the Bootstrap extra so we can use pagy_bootstrap_nav in the view
require "pagy/extras/bootstrap"

# A page past the last one raised Pagy::OverflowError, which Rails renders as a 500.
# Reachable by a hand-edited URL or by a crawler following a stale pagination link
# after the catalog shrinks. Serve the last page instead of raising.
require "pagy/extras/overflow"
Pagy::DEFAULT[:overflow] = :last_page

# No page-size setting here on purpose: pagy 9 renamed :items to :limit without a
# compatibility shim, so the old `DEFAULT[:items] = 12` was dead. The catalog uses
# pagy's default limit of 20.
