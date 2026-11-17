# Preview at http://localhost:3000/rails/mailers/order_mailer (development only).
# Uses the most recent paid order, or any order, from the local database.
class OrderMailerPreview < ActionMailer::Preview
  def payment_confirmed
    order = Order.where(payment_status: :paid).order(:id).last || Order.order(:id).last
    OrderMailer.payment_confirmed(order)
  end
end
