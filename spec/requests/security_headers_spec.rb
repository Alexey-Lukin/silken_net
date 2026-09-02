# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.35] The security headers are pinned on a LIVE response, not on the config hash.
# Until 2026-09-02 they were assigned in config/initializers/security_headers.rb — after
# ActionDispatch had already copied the defaults into `ActionDispatch::Response` inside
# `on_load(:action_dispatch_response)` — so every response carried Rails' defaults
# (`X-Frame-Options: SAMEORIGIN`, no `Permissions-Policy`) while the config, the assurance
# case (§A05) and the initializer all said DENY. Nothing in spec/ touched a header, so the
# gap had no colour. The config now lives in config/application.rb (read before that hook);
# this spec is the carrier, and it must stay a REQUEST spec: a unit assertion on the config
# hash would have been green through the whole defect.
RSpec.describe "security headers on a live response [SEC.35]", type: :request do
  before { get "/up" }

  it "hardens beyond the Rails defaults on every response" do
    aggregate_failures do
      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Frame-Options"]).to eq("DENY")
      expect(response.headers["Permissions-Policy"]).to include("camera=()", "microphone=()", "interest-cohort=()")
      expect(response.headers["Cross-Origin-Opener-Policy"]).to eq("same-origin")
      expect(response.headers["Cross-Origin-Resource-Policy"]).to eq("same-origin")
      expect(response.headers["X-XSS-Protection"]).to eq("0")
    end
  end

  it "keeps the Rails defaults the replacement hash could silently drop" do
    aggregate_failures do
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
      expect(response.headers["X-Permitted-Cross-Domain-Policies"]).to eq("none")
      expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
    end
  end

  # The discriminating pin: the object ActionDispatch actually reads IS the configured one.
  it "wires the configured hash into ActionDispatch::Response itself" do
    expect(ActionDispatch::Response.default_headers["X-Frame-Options"]).to eq("DENY")
  end
end
