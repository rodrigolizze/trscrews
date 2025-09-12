class OrderMailer < ApplicationMailer
  default from: "nao-responder@screwshop.dev"  # dev placeholder

  def confirmation(order)
    @order = order
    mail to: @order.customer_email, subject: "Confirmação do pedido #{@order.order_number || "##{@order.id}"}"
  end
end
