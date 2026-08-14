# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# INF.4 flash-asymmetry guard. firmware/queen/main.c HARDCODES COAP_SERVER_HOST and it is
# FROZEN at flash time — if the deploy ever points DNS at a different host, the whole fleet
# silently loses the backend and the only fix is re-flashing every Queen. The runtime
# deploy-side host (DNS A-record, RAILS_ALLOWED_HOSTS) is operator-set and NOT committed, so
# it can't be checked here; what we CAN guard is that every committed surface the operator
# reads to configure it echoes the SAME host as the frozen #define. Anchored on the firmware
# value (no hard-coded expected), so a drift in EITHER direction — someone edits the #define,
# or edits the runbook/tooling — fails in CI, surfacing the re-flash coupling.
RSpec.describe "CoAP host consistency (firmware #define ↔ deploy tooling)" do # rubocop:disable RSpec/DescribeClass
  # Committed surfaces that name the CoAP host the operator points DNS at.
  let(:echo_surfaces) do
    %w[
      bin/coap_smoke
      .github/workflows/coap_smoke.yml
      terraform/compute.tf
      docs/06_01_Deployment_Kamal_Terraform.md
    ]
  end

  let(:firmware_host) do
    src = File.read(REPO_ROOT.join("firmware/queen/main.c"))
    src[/#define\s+COAP_SERVER_HOST\s+"([^"]+)"/, 1] or raise "COAP_SERVER_HOST #define not found in firmware/queen/main.c"
  end

  it "the firmware #define is a well-formed hostname" do
    expect(firmware_host).to match(/\A(?:[a-z0-9-]+\.)+[a-z]{2,}\z/)
  end

  it "every committed deploy surface echoes the frozen firmware host (re-flash coupling)" do
    stale = echo_surfaces.reject { |p| File.read(REPO_ROOT.join(p)).include?(firmware_host) }
    expect(stale).to be_empty,
                     "these committed surfaces don't name the firmware COAP host #{firmware_host.inspect} — " \
                     "either the #define drifted or they did (the fleet is flashed with #{firmware_host.inspect}): " \
                     "#{stale.join(', ')}"
  end
end
