# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🛡️ CONTENT SECURITY POLICY (SilkenNet Dashboard)
# = ===================================================================
# Tightened to the actual browser-side dependencies of the codebase:
#
#   • Stack:    Phlex + Tailwind v4 + importmap-rails + Stimulus + Turbo
#   • Realtime: ActionCable / Solid Cable (same-origin WSS only)
#   • Maps:     Leaflet — JS module and CSS are LOCAL (vendor/javascript +
#               vendor/assets/stylesheets/leaflet); only the tile images come
#               from *.basemaps.cartocdn.com (CartoDB Dark Matter, see
#               app/javascript/controllers/map_controller.js). [TEST.7]
#   • Decor:    the carbon-weave texture is SELF-HOSTED since 2026-08-20
#               (app/assets/images/carbon-weave.png — власна алгоритмічна
#               генерація, не чужий PNG): зовнішній хост уже флейкував
#               браузерну CI-смугу (Ferrum::PendingConnectionsError).
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
                           "https://*.basemaps.cartocdn.com"
    policy.media_src       :self, :data

    # [TEST.7] Every module is local now — leaflet included (it was the last
    # external pin). nonce is added below for any inline <script> we emit.
    policy.script_src      :self

    # Tailwind/Phlex generate style="..." attributes, which require
    # 'unsafe-inline' (nonces do not cover inline attributes, only <style>).
    policy.style_src       :self, :unsafe_inline

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
