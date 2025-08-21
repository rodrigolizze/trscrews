class ScrewsController < ApplicationController
  def index
    # List all screws (product listing page)
    @screws = Screw.all # assuming a Screw model exists with product data
  end

  def show
    # Show a single screw's details (product detail page)
    @screw = Screw.find(params[:id])
  end
end
