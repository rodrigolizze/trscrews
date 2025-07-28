class PagesController < ApplicationController
  def home
    @featured_products = Product.limit(8)
  end
end
