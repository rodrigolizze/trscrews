# app/controllers/shipping_addresses_controller.rb
class ShippingAddressesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_shipping_address, only: [:edit, :update, :destroy, :make_default]  # // use a name that matches the model

  # GET /shipping_addresses
  def index
    # // Ordena: padrão primeiro (escopo no model)
    @addresses = current_user.shipping_addresses.default_first
  end

  # GET /shipping_addresses/new
  def new
    # // Usa a variável com o nome do model para o form_with
    @shipping_address = current_user.shipping_addresses.new
  end

  # POST /shipping_addresses
  def create
    @shipping_address = current_user.shipping_addresses.new(address_params)

    if @shipping_address.save
      if params[:return_to] == "checkout"                      # // came from checkout?
        redirect_to checkout_path(address_id: @shipping_address.id),  # // go back, pre-select new address
                    notice: "Endereço salvo."
      else
        redirect_to shipping_addresses_path, notice: "Endereço salvo."
      end
    else
      flash.now[:alert] = "Não foi possível salvar o endereço."
      render :new, status: :unprocessable_entity
    end
  end

  # GET /shipping_addresses/:id/edit
  def edit
    # // @shipping_address carregado pelo before_action
  end

  # PATCH/PUT /shipping_addresses/:id
  def update
    if @shipping_address.update(address_params)
      redirect_to shipping_addresses_path, notice: "Endereço atualizado."  # // fix helper
    else
      flash.now[:alert] = "Não foi possível atualizar o endereço."
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /shipping_addresses/:id
  def destroy
    @shipping_address.destroy
    redirect_to shipping_addresses_path, notice: "Endereço excluído."  # // fix helper
  end

  # PATCH /shipping_addresses/:id/make_default
  def make_default
    if @shipping_address.update(is_default: true)
      redirect_to shipping_addresses_path, notice: "Endereço definido como padrão."  # // fix helper
    else
      redirect_to shipping_addresses_path, alert: "Não foi possível atualizar o endereço padrão."  # // fix helper
    end
  end

  private

  def set_shipping_address
    # // Garante que busca apenas do usuário atual
    @shipping_address = current_user.shipping_addresses.find(params[:id])
  end

  def address_params
    # // Mantém o namespace correto do form: shipping_address[..]
    params.require(:shipping_address).permit(
      :recipient_name, :cep, :street, :number, :complement,
      :district, :city, :state, :is_default
    )
  end
end
