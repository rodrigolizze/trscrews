class OrderMailer < ApplicationMailer
  # Garante que os helpers da app (incluindo format_price) funcionem no e-mail
  helper :application   # => usa ApplicationHelper

  # 1) E-mail enviado assim que o pedido é criado (pagamento pendente)
  def pending_order(order)
    @order = order

    mail(
      to: @order.customer_email,
      subject: "Pedido #{@order.order_number || "##{@order.id}"} recebido – pagamento pendente"
    )
  end

  # 2) E-mail enviado depois que o Stripe confirma o pagamento
  def payment_confirmed(order)
    @order = order

    mail(
      to: @order.customer_email,
      subject: "Pagamento confirmado – Pedido #{@order.order_number || "##{@order.id}"}"
    )
  end
end
