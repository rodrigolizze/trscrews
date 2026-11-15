# Safety net for the payment window (Order::PAYMENT_WINDOW): cancels unpaid
# orders past the deadline + grace and puts their stock back, in case the
# checkout.session.expired webhook never arrived. Run hourly (Heroku Scheduler):
#   bin/rails orders:expire_unpaid
namespace :orders do
  desc "Cancel unpaid orders past the payment window and restock their items"
  task expire_unpaid: :environment do
    count = 0
    Order.expired_unpaid.find_each { |order| count += 1 if order.expire_and_restock! }
    puts "[orders:expire_unpaid] cancelled and restocked #{count} order(s)"
  end
end
