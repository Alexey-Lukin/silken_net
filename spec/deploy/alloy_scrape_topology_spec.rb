# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# S2.4 / INF.14 drift guard. ⚠️ [OPS.37] Narrowed 2026-08-29 to what stayed TRUE: the guard now
# pins the three-PROCESS contract (a dropped target / broken process-label still fails), but no
# longer pins the ADDRESSES — Kamal gives no stable sibling address and the mechanism is an open
# leg (see config/deploy.yml `accessories.alloy`). Pinning an address nobody chose would make the
# spec assert a decision that was never taken.
# The Prometheus registry is in-process, so a job/daemon-incremented
# metric (money-path SLO, dead-man switch, QATT-security) is scraped as an eternal ZERO unless
# Alloy scrapes that process's own target. `alloy_config_validate` only checks River SYNTAX
# (`alloy fmt`), NOT topology — so a removed job-target, a port-typo (9394→9395), or a broken
# process-label passes green → deploy → job-metrics silently read zero → P0 alerts physically
# dead behind a green status. Mirror of grafana_alerts_spec (config-typo → silent-dead observability).
RSpec.describe "config.alloy declares the 3-process scrape topology (S2.4)" do # rubocop:disable RSpec/DescribeClass
  # __address__ → process — the load-bearing map (06_03 §2.9): web never sees worker increments.
  let(:targets) do
    text = File.read(REPO_ROOT.join("deploy/alloy/config.alloy"))
    # \s spans newlines, and ,? tolerates the trailing comma `alloy fmt` adds in the multi-line
    # form (`"process" = "web",\n}`) — so a legit reformat can't false-alarm the guard.
    text.scan(/\{\s*"__address__"\s*=\s*"([^"]+)",\s*"process"\s*=\s*"([^"]+)",?\s*\}/).to_h
  end

  it "declares exactly three targets, one per process, with the web/job/coap labels" do
    expect(targets.values.sort).to eq(%w[coap job web]),
                                   "config.alloy drifted from the 3-process contract (06_03 §2.9) — " \
                                   "a missing job/coap target or a broken process-label makes those " \
                                   "metrics scrape as eternal zeros, P0 alerts dead: got #{targets.inspect}"
  end

  it "gives every target a distinct address (a copy-paste dupe scrapes one process twice)" do
    expect(targets.keys.uniq.size).to eq(3), "duplicate __address__ in config.alloy: #{targets.keys.inspect}"
  end
end
