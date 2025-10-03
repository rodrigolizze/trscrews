# // Minimal helper to emit a canonical URL tag.
# // Why: prevents duplicate-URL issues (e.g., same page with different querystrings),
# //      and tells search engines which URL is the “one true” URL to index.
#
# // Usage in views (optional override):
# //   <% canonical_url "https://example.com/screws/slug-bonito" %>
# //
# // Layout (next step): add `<%= render_canonical_tag %>` inside <head>.
#
module CanonicalHelper
  # // Set or get the canonical URL for the current page.
  # // If not set explicitly, it builds one from the current request, dropping query/fragment.
  def canonical_url(url = nil)
    # // Allow pages to override:
    content_for(:canonical, url) if url.present?
    return content_for(:canonical) if content_for?(:canonical)

    # // Default: current URL without query params or fragments (UTMs, pagination, etc.)
    begin
      u = URI.parse(request.original_url)
      u.query   = nil     # drop ?a=b
      u.fragment = nil    # drop #section
      u.to_s
    rescue
      nil
    end
  end

  # // Render the actual <link rel="canonical"> tag (safe to call even if nil).
  def render_canonical_tag
    href = canonical_url
    return "".html_safe if href.blank?
    tag.link(rel: "canonical", href: href)
  end
end
