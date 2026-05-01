# frozen_string_literal: true

# = ===================================================================
# 🛡️ CONTENT SECURITY POLICY (Gaia 2.0 Dashboard)
# = ===================================================================
# Tightened to the actual browser-side dependencies of the codebase:
#
#   • Stack:    Phlex + Tailwind v4 + importmap-rails + Stimulus + Turbo
#   • Realtime: ActionCable / Solid Cable (same-origin WSS only)
#   • Maps:     Leaflet — JS module from ga.jspm.io, CSS from unpkg.com,
#               tile images from *.basemaps.cartocdn.com (CartoDB Dark Matter,
#               see app/javascript/controllers/map_controller.js).
#   • Decor:    transparenttextures.com (one carbon-fibre PNG used as a
#               background-image in DashboardLayout).
#   • Inline:   Leaflet sets style="" attributes on injected DOM nodes,
#               so style-src must allow 'unsafe-inline' (CSP nonces do not
#               cover inline style attributes — only <style> elements do).
#               Inline scripts use a per-request nonce (no 'unsafe-inline'
#               for script-src).
#
# Toggle:
#   CSP_ENFORCE=true  → policy is enforced (production recommended once
#                       observed for a release).
#   CSP_ENFORCE!=true → report-only (default), so violations are reported
#                       but the page still renders.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :none
    policy.frame_src       :none
    policy.object_src      :none
    policy.worker_src      :self
    policy.manifest_src    :self

    # Self-hosted via Propshaft / Tailwind. No external font CDNs.
    policy.font_src        :self, :data

    # Self + Leaflet tiles + decorative texture + inline data: URIs.
    policy.img_src         :self, :data,
                           "https://*.basemaps.cartocdn.com",
                           "https://www.transparenttextures.com"
    policy.media_src       :self, :data

    # Importmap pins leaflet to ga.jspm.io; everything else is local.
    # nonce is added below for any inline <script> we explicitly emit.
    policy.script_src      :self, "https://ga.jspm.io"

    # Leaflet ships its CSS on unpkg; Tailwind/Phlex generate style="..."
    # attributes which require 'unsafe-inline' (nonces do not cover them).
    policy.style_src       :self, :unsafe_inline, "https://unpkg.com"

    # ActionCable over Solid Cable runs same-origin (wss:// to our host),
    # and all backend XHR/fetch is same-origin too. No external connect.
    policy.connect_src     :self
  end

  # Per-request nonce for inline <script> tags only.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Default to report-only so a misconfigured CSP doesn't take down the
  # dashboard during rollout. Flip CSP_ENFORCE=true after observing reports.
  config.content_security_policy_report_only = ENV["CSP_ENFORCE"] != "true"
end
