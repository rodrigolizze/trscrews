# Fluxo:
# 1) O botão na orders#show faz POST /checkout_sessions?order_id=123
# 2) Montamos line_items a partir de @order.order_items (snapshot do carrinho)
# 3) Incluímos também o FRETE como um item separado (quando > 0)
# 4) Redirecionamos para a página segura da Stripe
# 5) A confirmação REAL vem pelo webhook (StripeWebhooksController)

class CheckoutSessionsController < ApplicationController
  before_action :set_order

  def create
    # // Only block payment if the enum exists AND the order isn't pending
    if @order.respond_to?(:payment_status) && @order.payment_status.to_s != "pending"
      redirect_to @order, alert: "Este pedido não está pendente de pagamento." and return
    end

    if @order.order_items.blank?
      redirect_to @order, alert: "Pedido sem itens." and return
    end

    if @order.order_items.any? { |i| i.unit_price.to_d <= 0 || i.quantity.to_i <= 0 }
      redirect_to @order, alert: "Itens com preço/quantidade inválidos." and return
    end

    # ----------------- ITENS DO PEDIDO -----------------
    line_items = @order.order_items.map do |item|
      {
        price_data: {
          currency: "brl",
          unit_amount: (item.unit_price.to_d * 100).to_i,
          product_data: {
            name: item.screw&.description.presence || "Item ##{item.id}",
            description: [
              (t = item.screw&.thread).presence && "Rosca: #{t}",
              (st = item.screw&.surface_treatment).presence && "Tratamento: #{st}"
            ].compact.join(" · ")
          }
        },
        quantity: item.quantity
      }
    end

    # ----------------- FRETE COMO LINHA SEPARADA -----------------
    shipping_amount =
      if @order.respond_to?(:shipping_fee) && @order.shipping_fee.present?
        @order.shipping_fee.to_d
      elsif @order.respond_to?(:shipping) && @order.shipping.present?
        @order.shipping.to_d
      else
        0.to_d
      end

    if shipping_amount > 0
      line_items << {
        price_data: {
          currency: "brl",
          unit_amount: (shipping_amount * 100).to_i,
          product_data: {
            name: "Frete"
          }
        },
        quantity: 1
      }
    end

    success_url = thank_you_order_url(@order, paid: 1, session_id: "{CHECKOUT_SESSION_ID}")
    cancel_url  = thank_you_order_url(@order, canceled: 1)

    session = Stripe::Checkout::Session.create(
      mode: "payment",
      customer_email: @order.customer_email,
      line_items: line_items,
      success_url: success_url,
      cancel_url:  cancel_url,
      locale: "pt-BR",
      shipping_address_collection: { allowed_countries: ["BR"] },

      metadata: { order_id: @order.id },

      payment_intent_data: {
        metadata: { order_id: @order.id }
      }
    )

    redirect_to session.url, allow_other_host: true

  rescue Stripe::StripeError => e
    Rails.logger.error("[Stripe] Checkout error for order #{@order.id}: #{e.class} - #{e.message}")
    msg = Rails.env.development? ? "Stripe: #{e.message}" : "Não foi possível iniciar o pagamento. Tente novamente."
    redirect_to @order, alert: msg
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end
end
