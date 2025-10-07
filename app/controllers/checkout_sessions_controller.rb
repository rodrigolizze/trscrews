# // Creates a Stripe Checkout Session for an existing Order and redirects the user to Stripe.
# // Flow:
# //   - Button on orders#show hits POST /checkout_sessions?order_id=123
# //   - We build line_items from @order.order_items snapshot (unit_price, quantity)
# //   - Redirect to Stripe-hosted page (no card data touches your server)
# //   - On success, Stripe will redirect back to success_url; real confirmation will come via webhook (next step)
#
class CheckoutSessionsController < ApplicationController
  before_action :set_order

  def create
    # // Safety: only allow paying non-pending orders *only if* payment_status exists
    if @order.respond_to?(:payment_status) && @order.payment_status.to_s != "pending"
      redirect_to @order, alert: "Este pedido não está pendente de pagamento." and return
    end

    # // Build Stripe line items from the order snapshot
    line_items = @order.order_items.map do |item|
      {
        price_data: {
          currency: "brl",
          unit_amount: (item.unit_price.to_d * 100).to_i, # // cents
          product_data: {
            name:  item.screw&.description.presence || "Item ##{item.id}",
            # // Optional: send more details for better receipts (limit sizes)
            description: [
              item.screw&.thread.presence && "Rosca: #{item.screw.thread}",
              item.screw&.surface_treatment.presence && "Tratamento: #{item.screw.surface_treatment}"
            ].compact.join(" · ")
          }
        },
        quantity: item.quantity
      }
    end

    # // Success/cancel URLs — user lands back on the order page
    success_url = order_url(@order, paid: 1, session_id: "{CHECKOUT_SESSION_ID}")
    cancel_url  = order_url(@order, canceled: 1)

    # // Create Checkout Session
    session = Stripe::Checkout::Session.create(
      mode: "payment",
      customer_email: @order.customer_email,               # // helpful for receipts
      line_items: line_items,
      success_url: success_url,
      cancel_url:  cancel_url,
      locale: "pt-BR",
      shipping_address_collection: { allowed_countries: ["BR"] },
      metadata: { order_id: @order.id }                   # // we’ll use this in the webhook to find the order
    )

    # // Redirect user to Stripe-hosted checkout
    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error("[Stripe] Checkout error for order #{@order.id}: #{e.class} - #{e.message}")
    redirect_to @order, alert: "Não foi possível iniciar o pagamento. Tente novamente."
  end

  private

  # // Load the order; we expect ?order_id= in the POST (from orders#show button)
  def set_order
    @order = Order.find(params[:order_id])
  end
end
