class PagesController < ApplicationController
  def home
    @featured_screws = Screw.limit(8)
  end
end
