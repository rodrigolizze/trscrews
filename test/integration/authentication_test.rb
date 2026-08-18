require "test_helper"

# First coverage of sign_in / sign_out in this project. Before this file, no test
# authenticated at all, which left three things unexercised: current_user resolving to
# the right user, the two authenticate_user! sites (ShippingAddressesController on every
# action, OrdersController#show), and the sign_in -> signed-out round trip.
#
# What this file is NOT: a regression guard for the Rails 8.0 lazy route loading bug that
# test/test_helper.rb used to work around (Devise 4.9.4 read Devise.mappings without
# ensuring the routes had been drawn, so sign_in raised "Could not find a valid mapping";
# Devise 5.0 fixed it in heartcombo/devise#5728).
#
# It looks like it would guard that, and it does not. Measured on 2026-08-14 by pinning
# Devise back to 4.9.4 with the workaround removed: these tests stayed GREEN. The reason
# is that the fixture accessor `users(:one)` draws the routes as a side effect, so by the
# time sign_in runs the mappings are already populated and the failing condition is gone:
#
#   at test start                  -> routes loaded: false, Devise.mappings: []
#   after referencing User         -> routes loaded: false, Devise.mappings: []
#   after users(:one)              -> routes loaded: true,  Devise.mappings: [:user]
#
# Do not "fix" this by fetching the user some other way (User.order(:id).first does
# reproduce the failure on 4.9.4). That would make redness depend on an invisible
# process-wide load-order coupling that any future change silently neutralises — a guard
# that disarms itself and still reports green. The real check for that bug is a
# clean-process command, not a test in this suite. See DEVISE_50_MIGRATION.md §4.
#
# Fixture note: users(:one) owns shipping_addresses(:one), so
# ApplicationController#ensure_first_address_created does not redirect them. A user
# without an address would be bounced to the address form, which looks like an
# authentication failure but is not.
class AuthenticationTest < ActionDispatch::IntegrationTest
  # Devise::TestHelpers was removed in Devise 5.0; this is the surviving API.
  include Devise::Test::IntegrationHelpers

  test "redirects to the sign in page when a protected route is requested while signed out" do
    get shipping_addresses_path

    assert_redirected_to new_user_session_path
  end

  test "redirects to the sign in page when an order is requested while signed out" do
    # OrdersController#show is the other authenticate_user! site. The filter runs before
    # set_order, so this never reaches authorization.
    get order_path(orders(:one))

    assert_redirected_to new_user_session_path
  end

  test "reaches the protected route after signing in" do
    sign_in users(:one) # no positional scope argument: that form was removed in Devise 5.0

    get shipping_addresses_path

    assert_response :success
    # Asserting the signed-in user's own address proves current_user resolved to that
    # user, not merely that some session exists.
    assert_match shipping_addresses(:one).recipient_name, response.body
  end

  test "loses access to the protected route after signing out" do
    sign_in users(:one)
    get shipping_addresses_path
    assert_response :success

    sign_out users(:one)
    get shipping_addresses_path

    assert_redirected_to new_user_session_path
  end
end
