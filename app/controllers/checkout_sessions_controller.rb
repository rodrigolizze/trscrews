# -- Creates a Stripe Checkout Session and redirects the user to Stripe --
# Flow:
# 1) Button on orders#show hits POST /checkout_sessions?order_id=123
# 2) We build line_items from @order.order_items snapshot (unit_price, quantity)
# 3) Redirect to Stripe-hosted page (no card data touches your server)
# 4) On success, Stripe redirects back; real confirmation comes via webhook
class CheckoutSessionsController < ApplicationController
  before_action :set_order

  def create
    # // Only block payment if the enum exists AND the order isn't pending
    if @order.respond_to?(:payment_status) && @order.payment_status.to_s != "pending"
      redirect_to @order, alert: "Este pedido não está pendente de pagamento." and return
    end

    # // Preflight validations to avoid bad payloads -----------------------
    # // No items?
    if @order.order_items.blank?
      redirect_to @order, alert: "Pedido sem itens." and return
    end

    # // Invalid prices/quantities?
    if @order.order_items.any? { |i| i.unit_price.to_d <= 0 || i.quantity.to_i <= 0 }
      redirect_to @order, alert: "Itens com preço/quantidade inválidos." and return
    end

    # // Build Stripe line items from the order snapshot -------------------
    line_items = @order.order_items.map do |item|
      {
        price_data: {
          currency: "brl",
          unit_amount: (item.unit_price.to_d * 100).to_i, # // cents
          product_data: {
            name: item.screw&.description.presence || "Item ##{item.id}",
            # // Optional: concise receipt details (keep short)
            description: [
              (t = item.screw&.thread).presence && "Rosca: #{t}",
              (st = item.screw&.surface_treatment).presence && "Tratamento: #{st}"
            ].compact.join(" · ")
          }
        },
        quantity: item.quantity
      }
    end

    # // Success/cancel URLs — user lands back on the order page -----------
    success_url = order_url(@order, paid: 1, session_id: "{CHECKOUT_SESSION_ID}")
    cancel_url  = order_url(@order, canceled: 1)

    # // Create Checkout Session ------------------------------------------
    session = Stripe::Checkout::Session.create(
      mode: "payment",
      customer_email: @order.customer_email,
      line_items: line_items,
      success_url: success_url,
      cancel_url:  cancel_url,
      locale: "pt-BR",
      shipping_address_collection: { allowed_countries: ["BR"] },

      metadata: { order_id: @order.id },              # keeps it on the Session too

      # NEW → also stamp the PaymentIntent with order_id
      payment_intent_data: {
        metadata: { order_id: @order.id }
      }
    )

    # // Redirect user to Stripe-hosted checkout ---------------------------
    redirect_to session.url, allow_other_host: true

  rescue Stripe::StripeError => e
    Rails.logger.error("[Stripe] Checkout error for order #{@order.id}: #{e.class} - #{e.message}")
    # // In development, show the exact Stripe message to speed up debugging
    msg = Rails.env.development? ? "Stripe: #{e.message}" : "Não foi possível iniciar o pagamento. Tente novamente."
    redirect_to @order, alert: msg
  end

  private

  # // Load the order; we expect ?order_id= in the POST (from orders#show button)
  def set_order
    @order = Order.find(params[:order_id])
  end
end
