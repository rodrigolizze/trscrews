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

    # // For the customer form (blank order just to reuse the shipping rule)
    @order = Order.new

    # // Preview shipping with the same rule the model will use at save time
    # // (keeps UI and DB computation consistent)
    @shipping = @order.compute_shipping(@subtotal)
    @total    = @subtotal + @shipping
  end

  # // Step 2: Persist order + items; clear session cart; show confirmation
  def create
    if session[:cart].blank?
      redirect_to screws_path, alert: "Seu carrinho está vazio." and return
    end

    @order = Order.new(order_params)
    # // If the buyer is logged in, link the order to their account
    @order.user = current_user if defined?(current_user) && current_user.present?
    @order.status = :placed
    @order.placed_at = Time.current

    # // Wrap everything in a DB transaction so stock + order are consistent
    ActiveRecord::Base.transaction do
      # // Load screws once and index by id
      screw_ids = session[:cart].keys.map!(&:to_i)
      screws_by_id = Screw.where(id: screw_ids).index_by(&:id)

      # // Track shortages to show a useful message if needed
      shortages = []

      session[:cart].each do |screw_id_str, qty|
        screw = screws_by_id[screw_id_str.to_i]
        next unless screw
        qty = qty.to_i

        # // Lock the row to avoid race conditions (two checkouts at once)
        screw.with_lock do
          if screw.stock < qty
            shortages << { description: screw.description, requested: qty, available: screw.stock }
          else
            # // Enough stock: add item snapshot and decrement stock
            @order.add_item!(screw, qty)
            screw.update!(stock: screw.stock - qty)
          end
        end
      end

      if shortages.any?
        # // Roll back everything: raise to abort the transaction
        raise ActiveRecord::Rollback
      end

      # // IMPORTANT: totals now include shipping (computed in the model)
      @order.recalc_totals!

      unless @order.save
        # // If validations fail (e.g., address/cep), rollback
        raise ActiveRecord::Rollback
      end
    end

    if @order.persisted?
      session[:cart] = {}
      OrderMailer.confirmation(@order).deliver_later
      redirect_to @order, notice: "Pedido realizado com sucesso!"
    else
      # // Rebuild summary and show a message if there was a shortage
      rebuild_summary_for_render
      flash.now[:alert] = "Alguns itens não têm estoque suficiente. Atualizamos as quantidades do carrinho."
      # // Optional: sync the cart quantities to current stock to be friendly
      sync_cart_to_stock!
      render :new, status: :unprocessable_entity
    end
  end

  # // Step 3: Confirmation page
  def show
    @order = Order.includes(order_items: [screw: { images_attachments: :blob }]).find(params[:id])
  end

  # // List the current user’s own orders (requires login)
  def mine
    # // If not logged in, send to Devise sign-in
    unless defined?(user_signed_in?) && user_signed_in?
      redirect_to new_user_session_path, alert: "Entre para ver seus pedidos." and return
    end

    # // Load orders for this user, newest first.
    # // includes(...) avoids N+1 when we render items/images in the view.
    @orders = current_user.orders
                          .order(created_at: :desc)
                          .includes(order_items: [screw: { images_attachments: :blob }])
  end

  private

  def order_params
    # // Now we also accept address fields from the checkout form
    params.require(:order).permit(
      :customer_name, :customer_email,
      :cep, :street, :number, :complement, :district, :city, :state
    )
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

    # // Recompute shipping preview consistently with the model rule
    tmp_order = @order || Order.new
    @shipping = tmp_order.compute_shipping(@subtotal)
    @total    = @subtotal + @shipping
  end

  # // If checkout failed, bring cart quantities down to available stock
  def sync_cart_to_stock!
    ids = session[:cart].keys.map!(&:to_i)
    Screw.where(id: ids).each do |s|
      key = s.id.to_s
      qty = session[:cart][key].to_i
      if s.stock <= 0
        session[:cart].delete(key)
      elsif qty > s.stock
        session[:cart][key] = s.stock
      end
    end
  end
end
