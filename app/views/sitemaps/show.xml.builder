# // XML Sitemap listing: home, catalog, each product page.
# // Uses request.base_url + *_path so it works in development without extra host config.

xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset "xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9" do
  host = request.base_url # // e.g., "http://localhost:3000"

  # -- Homepage --
  xml.url do
    xml.loc       host + root_path
    xml.lastmod   Time.zone.now.to_date.iso8601
    xml.changefreq "weekly"
    xml.priority  "0.8"
  end

  # -- Catalog index --
  xml.url do
    xml.loc       host + screws_path
    xml.lastmod   (@screws.maximum(:updated_at)&.to_date || Date.today).iso8601
    xml.changefreq "daily"
    xml.priority  "0.7"
  end

  # -- Each product (Screw) --
  @screws.find_each do |s|
    xml.url do
      xml.loc       host + screw_path(s) # // uses slugs via FriendlyId
      xml.lastmod   s.updated_at.to_date.iso8601
      xml.changefreq "weekly"
      xml.priority  "0.6"
    end
  end
end
