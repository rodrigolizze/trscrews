ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# Throttling stores are per-process memory (audit A3); clear them between
# integration tests so one test's lockout does not leak into the next.
class ActionDispatch::IntegrationTest
  setup do
    Admin::BaseController::AUTH_FAILURE_STORE.clear
    Users::SessionsController::RATE_LIMIT_STORE.clear
  end
end
