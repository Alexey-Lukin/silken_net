# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# S2.4 / INF.14 drift guard. The Prometheus registry is in-process, so a job/daemon-incremented
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

  it "scrapes exactly 9393/9394/9395 on host loopback with matching process labels" do
    expect(targets).to eq({ "127.0.0.1:9393" => "web", "127.0.0.1:9394" => "job", "127.0.0.1:9395" => "coap" }),
                       "config.alloy scrape topology drifted from the 3-process contract (06_03 §2.9) — " \
                       "a missing job/coap target or port-typo makes those metrics scrape as eternal " \
                       "zeros, P0 alerts dead: got #{targets.inspect}"
  end
end
