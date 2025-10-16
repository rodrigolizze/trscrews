# app/controllers/orders_controller.rb
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

    @order = Order.new

    chosen = nil

    # --------------------------------------------------------------------
    # // NOVO: pré-preencher com dados do usuário + endereço salvo
    # --------------------------------------------------------------------
    if defined?(user_signed_in?) && user_signed_in?
      # // Preenche nome/email com dados do usuário (se ainda não estiver no form)
      @order.customer_name  ||= current_user.name.presence
      @order.customer_email ||= current_user.email

      # // Carrega endereços do usuário para o próximo passo (picker na view)
      @addresses = current_user.shipping_addresses.default_first

      # // Se veio ?address_id na URL, tentamos usar esse endereço;
      # // senão, usamos o padrão (ou o primeiro da lista).
      chosen =
        if params[:address_id].present?
          @addresses.find_by(id: params[:address_id])
        else
          @addresses.find_by(is_default: true) || @addresses.first
        end

      assign_shipping_from(@order, chosen) if chosen
    end

    @shipping = shipping_for(@subtotal, uf: (chosen&.state || @order.state))
    @total    = @subtotal + @shipping
    @shipping_uf     = (chosen&.state || @order.state).to_s.upcase.presence
    @shipping_region = region_for_uf(@shipping_uf)
  end

  # // Step 2: Persist order + items; clear session cart; show confirmation
  def create
    if session[:cart].blank?
      redirect_to screws_path, alert: "Seu carrinho está vazio." and return
    end

    @order = Order.new(order_params)
    @order.status = :placed
    @order.placed_at = Time.current

    # // Se usuário logado, associa o pedido ao usuário
    if defined?(user_signed_in?) && user_signed_in?
      @order.user = current_user
    end

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

      @order.shipping_fee = shipping_for(@order.order_items.sum(&:line_total), uf: @order.state) # // calcula frete pelo subtotal atual

      @order.recalc_totals!

      unless @order.save
        # // If validations fail, rollback
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
    unless defined?(user_signed_in?) && user_signed_in?
      redirect_to new_user_session_path, alert: "Entre para ver seus pedidos." and return
    end

    @orders = current_user.orders.order(created_at: :desc).includes(order_items: :screw)
  end

  private

  def order_params
    # // Permite também os campos de endereço (já existiam quando criamos o checkout com CEP)
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
    @shipping = shipping_for(@subtotal, uf: @order&.state)
    @total    = @subtotal + @shipping

    # // Recarrega lista de endereços para mostrar o picker ao re-renderizar
    if defined?(user_signed_in?) && user_signed_in?
      @addresses = current_user.shipping_addresses.default_first
    end
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

  # ------------------------------------------------------------------------
  # // NOVO helper: copia campos de um ShippingAddress para o @order
  # // (só para pré-preenchimento no formulário do checkout)
  # ------------------------------------------------------------------------
  def assign_shipping_from(order, addr)
    # order.customer_name  ||= addr.recipient_name  # // se quiser, pode manter assim; não é necessário

    order.cep        = addr.cep        # // sem ||= (importante!)
    order.street     = addr.street
    order.number     = addr.number
    order.complement = addr.complement
    order.district   = addr.district
    order.city       = addr.city
    order.state      = addr.state
  end
end
