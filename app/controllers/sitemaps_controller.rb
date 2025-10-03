class SitemapsController < ApplicationController
  layout false  # // never use the HTML layout for XML

  # // GET /sitemap.xml
  def show
    # // Load products ordered by update time (good for <lastmod>)
    @screws = Screw.order(updated_at: :desc)

    # // Public cache hint
    expires_in 12.hours, public: true

    respond_to do |format|
      format.xml    # // renders app/views/sitemaps/show.xml.builder
      # // If someone hits without .xml (e.g., Accept: text/html), send them to the XML URL
      format.any { redirect_to sitemap_url(format: :xml) }
    end
  end
end
