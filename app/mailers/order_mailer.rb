class OrderMailer < ApplicationMailer
  # Garante que os helpers da app (incluindo format_price) funcionem no e-mail
  helper :application   # => usa ApplicationHelper

  # Sent by the Stripe webhook once the payment is confirmed (card or Pix).
  def payment_confirmed(order)
    @order = order

    mail(
      to: @order.customer_email,
      subject: "Pagamento confirmado – Pedido #{@order.order_number || "##{@order.id}"}"
    )
  end
end
