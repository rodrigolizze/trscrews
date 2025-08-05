class PagesController < ApplicationController
  def home
    @featured_screws = Screw.includes(images_attachments: :blob).all
  end
end
