# // Small helper to manage <title> and meta description (and OG/Twitter fallbacks)
module MetaHelper
  # // ---- Defaults (safe fallbacks used if a page doesn't override) ----
  def site_name
    "TR AutoParts"
  end

  def default_meta_title
    "Parafusos automotivos | #{site_name}"
  end

  def default_meta_description
    "Compre parafusos automotivos por rosca, montadora e modelo. Envio rápido em todo o Brasil."
  end

  def default_og_image
    # // Optional: put a hosted image (logo or hero) for link previews.
    # // If you don't have one yet, leave nil and the tag won't render.
    nil
  end

  # // ---- Public setters/getters used from views/controllers ----
  # // Usage in a view:
  # //   <% meta_title       "Parafuso HEX M6x20 para VW" %>
  # //   <% meta_description "Parafuso de alta resistência M6x20, tratamento zincado..." %>
  #
  def meta_title(text = nil)
    content_for(:meta_title, text) if text.present?
    content_for?(:meta_title) ? content_for(:meta_title) : default_meta_title
  end

  def meta_description(text = nil)
    content_for(:meta_description, text) if text.present?
    content_for?(:meta_description) ? content_for(:meta_description) : default_meta_description
  end

  # // OpenGraph/Twitter: we keep these minimal (optional but nice for sharing)
  def meta_image(url = nil)
    content_for(:meta_image, url) if url.present?
    content_for?(:meta_image) ? content_for(:meta_image) : default_og_image
  end

  # // Convenience: build a full page title like "Page | Site"
  def full_title
    t = meta_title.to_s.strip
    return site_name if t.blank?
    t =~ /#{Regexp.escape(site_name)}/i ? t : "#{t} | #{site_name}"
  end

  # // Render tags (to be called from the layout head)
  def render_basic_meta_tags
    tags = []
    # <title>
    tags << content_tag(:title, full_title)
    # Description
    tags << tag.meta(name: "description", content: meta_description)

    # Open Graph (for WhatsApp/Facebook)
    tags << tag.meta(property: "og:site_name", content: site_name)
    tags << tag.meta(property: "og:title", content: meta_title)
    tags << tag.meta(property: "og:description", content: meta_description)
    if (img = meta_image).present?
      tags << tag.meta(property: "og:image", content: img)
    end

    # Twitter Card (summary)
    tags << tag.meta(name: "twitter:card", content: "summary")
    tags << tag.meta(name: "twitter:title", content: meta_title)
    tags << tag.meta(name: "twitter:description", content: meta_description)
    tags << tag.meta(name: "twitter:image", content: meta_image) if meta_image.present?

    safe_join(tags, "\n")
  end
end
