# frozen_string_literal: true

# = ===================================================================
# 🛡️ SECURITY HEADERS (HDR audit category)
# = ===================================================================
# Rails 8.1 already emits sensible defaults (X-Frame-Options=SAMEORIGIN,
# X-Content-Type-Options=nosniff, Referrer-Policy=strict-origin-when-cross-origin).
# We tighten them further:
#
#   • X-Frame-Options: DENY  — SilkenNet dashboard is never embedded in an
#                              <iframe>; CSP frame-ancestors 'none' is the
#                              modern equivalent but X-Frame-Options is
#                              still respected by older browsers.
#   • Permissions-Policy:    — disable powerful browser features the
#                              dashboard does not use (camera, mic,
#                              geolocation handled server-side, payment,
#                              USB, FLoC/Topics).
#   • Cross-Origin-Opener-Policy: same-origin
#                              prevents window.opener cross-origin reads,
#                              required for Spectre mitigations.
#   • Cross-Origin-Resource-Policy: same-origin
#                              prevents other origins from embedding our
#                              JSON/HTML responses.
#   • X-XSS-Protection: 0    — disable legacy IE/Edge filter (modern guidance).

Rails.application.config.action_dispatch.default_headers = {
  "X-Frame-Options"               => "DENY",
  "X-Content-Type-Options"        => "nosniff",
  "X-XSS-Protection"              => "0",
  "Referrer-Policy"               => "strict-origin-when-cross-origin",
  "Cross-Origin-Opener-Policy"    => "same-origin",
  "Cross-Origin-Resource-Policy"  => "same-origin",
  "Permissions-Policy"            => [
    "accelerometer=()",
    "ambient-light-sensor=()",
    "autoplay=()",
    "battery=()",
    "camera=()",
    "display-capture=()",
    "document-domain=()",
    "encrypted-media=()",
    "fullscreen=(self)",
    "geolocation=()",
    "gyroscope=()",
    "magnetometer=()",
    "microphone=()",
    "midi=()",
    "payment=()",
    "picture-in-picture=()",
    "publickey-credentials-get=(self)",
    "screen-wake-lock=()",
    "sync-xhr=()",
    "usb=()",
    "xr-spatial-tracking=()",
    "interest-cohort=()",
    "browsing-topics=()"
  ].join(", ")
}
