class OrdersController < ApplicationController
  # // Step 1: Show checkout form with a summary of the session cart
  def new
    if session[:cart].blank?
      redirect_to screws_path, alert: "Seu carrinho está vazio." and return
    end

    # // Same build as in cart, but local to checkout
    ids = session[:cart].keys
    @screws = Screw.includes(images_attachments: :blob).where(id: ids)

    @lines = @screws.map do |s|
      qty = session[:cart][s.id.to_s].to_i
      { screw: s, qty: qty, unit_price: s.price, line_total: s.price * qty }
    end

    @subtotal = @lines.sum { |l| l[:line_total] }
    @shipping = 0.to_d  # // placeholder
    @total    = @subtotal + @shipping

    # // For the customer form
    @order = Order.new
  end

  # // Step 2: Persist order + items; clear session cart; show confirmation
  def create
    if session[:cart].blank?
      redirect_to screws_path, alert: "Seu carrinho está vazio." and return
    end

    @order = Order.new(order_params)
    @order.status = :placed
    @order.placed_at = Time.current

    # // Build items from the session snapshot
    ids = session[:cart].keys
    screws = Screw.where(id: ids).index_by(&:id)

    session[:cart].each do |screw_id_str, qty|
      screw = screws[screw_id_str.to_i]
      next unless screw
      @order.add_item!(screw, qty)
    end

    # // Compute totals server-side
    @order.recalc_totals!

    if @order.save
      # // Clear the cart after successful order
      session[:cart] = {}

      # Send confirmation (dev: goes to /letter_opener)
      OrderMailer.confirmation(@order).deliver_later
      
      redirect_to @order, notice: "Pedido realizado com sucesso!"
    else
      # // Re-render new with the summary again
      rebuild_summary_for_render
      flash.now[:alert] = "Corrija os dados para continuar."
      render :new, status: :unprocessable_entity
    end
  end

  # // Step 3: Confirmation page
  def show
    @order = Order.includes(order_items: [screw: { images_attachments: :blob }]).find(params[:id])
  end

  private

  def order_params
    params.require(:order).permit(:customer_name, :customer_email)
  end

  # // Helper to rebuild checkout summary if we need to re-render :new
  def rebuild_summary_for_render
    ids = session[:cart].keys
    @screws = Screw.includes(images_attachments: :blob).where(id: ids)
    @lines = @screws.map do |s|
      qty = session[:cart][s.id.to_s].to_i
      { screw: s, qty: qty, unit_price: s.price, line_total: s.price * qty }
    end
    @subtotal = @lines.sum { |l| l[:line_total] }
    @shipping = 0.to_d
    @total    = @subtotal + @shipping
  end
end
