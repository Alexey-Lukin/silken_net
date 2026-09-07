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
#   CSP_ENFORCE!=true → report-only (default): the page still renders. ⚠️ NOT
#                       "violations are reported" — without a `report-uri` they
#                       reach only the visitor's own console (see the ⚖️ below).

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
  # dashboard during rollout.
  #
  # 🔴 [2026-09-07] "Flip CSP_ENFORCE=true after observing reports" USED to stand
  # here, and it named a precondition that CANNOT BE MET as configured: there is
  # no `report-uri` / `report-to` directive anywhere in this policy, so a
  # violation is written to the console of whichever browser happened to hit it
  # and reaches nobody. `report_only` degrades the page-break, not the silence —
  # so "burn in for 1-2 weeks and then flip" describes a wait with no observer at
  # the end of it. The same impossible precondition also stood in `06_01
  # §DEPLOY-DAY` and `06_04`; all three said it for months.
  #
  # ✅ **⚖️ RATIFIED by the founder 2026-09-07 — exit (b): no collector, no
  # "observe reports" language. The flip is followed by a DELIBERATE MANUAL SMOKE
  # with devtools open on every rendered route.** The rejected exit (a) — wiring
  # Sentry's Security-Header endpoint — was cheap in code but adds an EXTERNAL
  # RECIPIENT of page data, i.e. a row in `ropa_art30` and in the subprocessor
  # register (`SEC.23` axis). We refused to buy an observer at that price for a
  # one-off rollout check a human can do in ten minutes.
  # ⛔ Do not restore the old sentence: it reads as a plan while being a no-op.
  # ⛔ Do NOT re-point this at SEC.23: that item carries CSP only as an example of a
  # high-precision allowlist for a different gate — it has never held this verdict.
  # (The runbook step in 06_01 §DEPLOY-DAY Фаза 5 points HERE for the choice, so a
  # second wrong address closes a ring and leaves the ⚖️ homeless.)
  #
  # ⚠️ **The price of exit (b), named aloud so nobody re-opens it as an oversight:**
  # after the flip we learn about a violation only from a HUMAN walking the routes,
  # or from a user reporting a broken page. There is no channel and there will not
  # be one. That is acceptable for a rollout gate and NOT acceptable as a standing
  # security control — so if CSP ever becomes evidence rather than hygiene, exit (a)
  # is the reopening, and its cost is the vendor row, not the code.
  #
  # 🔑 **`CSP_ENFORCE` is now DELIVERED, explicitly `"false"`, in BOTH manifests'
  # `env.clear` — and that is the WHOLE chain, not part of it.** Before 2026-09-07
  # it was wired nowhere, so Фаза 5 would have been «wire the chain PLUS flip»:
  # two things under time pressure instead of one.
  # ⚠️ **The «five delivery surfaces» figure belongs to a SECRET and does not apply
  # here — measured, not assumed:** `POSTGRES_HOST` and `APP_HOST`, both `env.clear`,
  # have ZERO hits in `.kamal/secrets-common` and in either deploy workflow, because
  # Kamal emits a clear value from the manifest literally. Counting five for a
  # non-secret overstates the remaining work and invites someone to «finish» the
  # chain by putting a non-secret into the secrets path, which `deploy_secret_scan`
  # exists to prevent. Flipping is a one-token manifest edit plus a deploy — and it
  # is reviewable in git precisely BECAUSE the value is clear rather than secret.
  config.content_security_policy_report_only = ENV["CSP_ENFORCE"] != "true"
end
