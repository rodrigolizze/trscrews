class OrderMailer < ApplicationMailer
  default from: "nao-responder@screwshop.dev"  # dev placeholder

  def confirmation(order)
    @order = order
    mail to: @order.customer_email, subject: "Confirmação do pedido #{@order.order_number || "##{@order.id}"}"
  end

  def payment_received(order)
    @order = order                               # // available in the view
    @items = @order.order_items.includes(:screw) # // for the table

    # // Nice subject with order code/id
    mail to: @order.customer_email, subject: "Pagamento confirmado — Pedido ##{@order.id}"
  end
end
