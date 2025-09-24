class CartsController < ApplicationController
  def show
    ids = session[:cart].keys
    @screws = Screw.includes(images_attachments: :blob).where(id: ids)

    # // Build lines for the table; stays valid even when the cart is empty
    @lines = @screws.map do |s|
      qty = session[:cart][s.id.to_s].to_i
      { screw: s, qty: qty, line_total: s.price * qty }
    end

    @subtotal = @lines.sum { |l| l[:line_total] }
    @shipping = 0.to_d
    @total    = @subtotal + @shipping
  end

  def add
    screw = Screw.find(params[:screw_id])
    requested = params[:quantity].to_i
    requested = 1 if requested <= 0

    # // Current qty in cart for this screw
    key = screw.id.to_s
    current = session[:cart].fetch(key, 0).to_i

    # // Max we can have is the stock
    max_allowed = screw.stock

    if max_allowed <= 0
      redirect_back fallback_location: screws_path, alert: "Produto sem estoque." and return
    end

    new_qty = [current + requested, max_allowed].min
    session[:cart][key] = new_qty

    # // If we had to clamp, tell the user
    if new_qty < current + requested
      redirect_to cart_path, alert: "Quantidade ajustada para #{new_qty} (estoque limitado)."
    else
      redirect_to cart_path, notice: "Adicionado ao carrinho."
    end
  end

  def set
    screw = Screw.find(params[:screw_id])
    key = screw.id.to_s

    requested = params[:quantity].to_i
    requested = 0 if requested < 0

    max_allowed = screw.stock

    if requested == 0
      session[:cart].delete(key)
      redirect_to cart_path, notice: "Item removido." and return
    end

    if max_allowed <= 0
      session[:cart].delete(key)
      redirect_to cart_path, alert: "Produto sem estoque. Item removido." and return
    end

    new_qty = [requested, max_allowed].min
    session[:cart][key] = new_qty

    if new_qty < requested
      redirect_to cart_path, alert: "Quantidade ajustada para #{new_qty} (estoque limitado)."
    else
      redirect_to cart_path, notice: "Quantidade atualizada."
    end
  end

  def remove
    session[:cart].delete(params[:screw_id].to_s)
    redirect_to cart_path, notice: "Item removido."
  end

  def clear
    session[:cart] = {}
    redirect_to cart_path, notice: "Carrinho limpo."
  end
end
