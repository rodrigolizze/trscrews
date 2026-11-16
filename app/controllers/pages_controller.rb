class PagesController < ApplicationController
  # Policy pages must be readable by anyone, including a signed-in customer who has
  # not registered an address yet (the address gate would redirect them away).
  skip_before_action :ensure_first_address_created, only: %i[returns privacy terms]

  def home
    @featured_screws = Screw.includes(images_attachments: :blob).all
  end

  # GET /trocas-e-devolucoes
  def returns; end

  # GET /privacidade
  def privacy; end

  # GET /termos-de-uso
  def terms; end
end
