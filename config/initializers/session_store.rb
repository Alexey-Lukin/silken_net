# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🍪 SESSION COOKIE CONFIGURATION (SESS audit category)
# = ===================================================================
# The dashboard uses cookie-based sessions for the browser flow (see
# Api::V1::BaseController#authenticate_user! → session[:user_id]). API
# clients (mobile / Gateway) use Bearer tokens and are unaffected.
#
# Hardening:
#   • httponly:    true      — block JavaScript access (XSS theft).
#   • secure:      true (prod)— never sent over plain HTTP.
#   • same_site:   :lax      — block cross-site POST CSRF while still
#                              allowing top-level navigation from an emailed
#                              link (password-reset lands mid-session).
#   • expire_after: 14.days  — bound the lifetime of a stolen cookie.
#                              Active users get touched on every request
#                              via touch_visit!.
#   • key:         prefixed  — namespaced so multiple tenants on one host
#                              cannot collide.

Rails.application.config.session_store :cookie_store,
  key:          "_silken_net_session",
  httponly:     true,
  secure:       Rails.env.production?,
  same_site:    :lax,
  expire_after: 14.days
