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
    qty   = params[:quantity].to_i
    qty   = 1 if qty <= 0

    key = screw.id.to_s
    session[:cart][key] = session[:cart].fetch(key, 0).to_i + qty

    redirect_to cart_path, notice: "Adicionado ao carrinho."
  end

  def set
    key = params[:screw_id].to_s
    qty = params[:quantity].to_i
    qty <= 0 ? session[:cart].delete(key) : session[:cart][key] = qty
    redirect_to cart_path, notice: "Quantidade atualizada."
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
