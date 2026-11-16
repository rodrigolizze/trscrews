# Be sure to restart your server when you modify this file.
#
# Content Security Policy — security audit M1.
# Phase 1 (2026-11-15): report-only, to tune the policy on every page.
# Phase 2 (2026-11-16): ENFORCED. Checked on production before switching: every
# resource loaded by home (3D screw), catalog, cart and policy pages comes from an
# allowed origin, inline scripts carry the nonce (also on a first, cookieless
# visit) and the views have no inline event handlers. A new external origin
# (analytics, chat widget, Pix QR code host...) must be added here or it will be
# blocked. To go back to observing only, flip the flag below to true.
#
# External origins in use:
#   cdn.jsdelivr.net      Bootstrap (CSS/JS), Bootstrap Icons, three.js + Draco decoder (importmap)
#   cdnjs.cloudflare.com  AOS (CSS/JS)
#   fonts.googleapis.com  Google Fonts CSS (Aldrich, Anton, Inter)
#   fonts.gstatic.com     Google Fonts files
#   dl.polyhaven.org      HDR environment map for the 3D screw
#   res.cloudinary.com    product images (Active Storage on Cloudinary)
#   checkout.stripe.com   payment redirect after POST /checkout_sessions (form-action)
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.object_src      :none
    policy.frame_ancestors :none
    policy.form_action     :self, "https://checkout.stripe.com"
    # 'wasm-unsafe-eval': the Draco decoder (3D model) is WebAssembly.
    policy.script_src      :self, "https://cdn.jsdelivr.net", "https://cdnjs.cloudflare.com", "'wasm-unsafe-eval'"
    # Inline style="" attributes are used across the views (and by Turbo's
    # progress bar); nonces cannot cover attributes, so styles stay permissive.
    policy.style_src       :self, :unsafe_inline, "https://fonts.googleapis.com", "https://cdn.jsdelivr.net", "https://cdnjs.cloudflare.com"
    policy.font_src        :self, :data, "https://fonts.gstatic.com", "https://cdn.jsdelivr.net"
    policy.img_src         :self, :data, :blob, "https://res.cloudinary.com"
    # blob: GLTFLoader reads the textures embedded in screw.glb through blob URLs.
    policy.connect_src     :self, :blob, "https://cdn.jsdelivr.net", "https://dl.polyhaven.org"
    policy.worker_src      :self, :blob
  end

  # Nonce for inline <script> tags (importmap tags get it automatically).
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w(script-src)

  config.content_security_policy_report_only = false
end
