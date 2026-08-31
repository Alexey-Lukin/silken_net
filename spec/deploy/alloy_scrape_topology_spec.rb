# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "yaml"
require_relative "../support/repo_root"

# S2.4 / INF.14 drift guard. The Prometheus registry is in-process, so a job/daemon-incremented
# metric (money-path SLO, dead-man switch, QATT-security) is scraped as an eternal ZERO unless
# Alloy scrapes that process's own target. `alloy_config_validate` only checks River SYNTAX
# (`alloy fmt`), NOT topology — so a removed job-target, a port-typo (9394→9395), or a broken
# process-label passes green → deploy → job-metrics silently read zero → P0 alerts physically
# dead behind a green status. Mirror of grafana_alerts_spec (config-typo → silent-dead observability).
#
# ⚖️ [OPS.37 2026-08-30] Addresses are PINNED again: the scrape mechanism was ratified as
# per-role `network-alias` on the shared `kamal` docker network (rationale + measured
# rolling-window behaviour — config/deploy.yml web role note). That mechanism has TWO halves
# in TWO files: config.alloy targets an alias, config/deploy.yml declares it on the role.
# They drift apart silently (a renamed alias keeps both files individually valid), so the
# cross-file example below is load-bearing, not decoration.
# Declared ceiling: this spec judges the DECLARATION pair, never live DNS — whether Docker
# actually serves the alias was measured once (2026-08-30, two containers sharing an alias
# through a rolling window) and is re-proven by `up` / sn-alert-scrape-target-down at runtime.
RSpec.describe "config.alloy declares the 3-process scrape topology (S2.4)" do # rubocop:disable RSpec/DescribeClass
  # __address__ → process — the load-bearing map (06_03 §2.9): web never sees worker increments.
  let(:targets) do
    text = File.read(REPO_ROOT.join("deploy/alloy/config.alloy"))
    # \s spans newlines, and ,? tolerates the trailing comma `alloy fmt` adds in the multi-line
    # form (`"process" = "web",\n}`) — so a legit reformat can't false-alarm the guard.
    text.scan(/\{\s*"__address__"\s*=\s*"([^"]+)",\s*"process"\s*=\s*"([^"]+)",?\s*\}/).to_h
  end

  let(:deploy_config) { YAML.load_file(REPO_ROOT.join("config/deploy.yml")) }

  it "pins the ratified alias:port per process (web:80 middleware, job/coap embedded exporters)" do
    expect(targets).to eq(
      "silken-web:80"   => "web",
      "silken-job:9394" => "job",
      "silken-coap:9395" => "coap"
    ), "config.alloy drifted from the ratified scrape topology (⚖️ OPS.37 2026-08-30, 06_03 §2.9) — " \
       "a missing job/coap target, a port-typo or a broken process-label makes those metrics " \
       "scrape as eternal zeros, P0 alerts dead: got #{targets.inspect}"
  end

  it "finds every scraped alias declared as network-alias on a deploy.yml role (the other half)" do
    declared = deploy_config.fetch("servers").values.filter_map { |role| role["options"]&.[]("network-alias") }
    scraped  = targets.keys.map { |address| address.split(":").first }
    expect(scraped - declared).to be_empty,
                                  "config.alloy scrapes aliases no deploy.yml role declares — Docker DNS " \
                                  "returns NXDOMAIN and the process scrapes as a dead target: " \
                                  "missing #{(scraped - declared).inspect} (declared: #{declared.inspect})"
  end

  # 🔴 THIRD half, and it is a different AXIS from the two above: they pin WHAT is scraped,
  # this pins WHO is labelled. There is exactly ONE Alloy container for both slots —
  # `Kamal::Configuration::Accessory#service_name` is `"#{config.service}-#{name}"` and
  # `config.service` carries no destination — so a canopy-destination `accessory boot` does
  # not create a second agent, it renames the label of the ONLY one. `accessory boot` skips
  # when the container exists (yellow, exit 0), so the winner was whichever slot booted
  # first: canopy on every main push, production only on a Release ⇒ production series would
  # have carried `slot="canopy"`. Pure loss, because canopy is alias-less by construction
  # (array-form `servers:` replaces the base hash — invariant B3), so it has nothing to scrape.
  # ⚖️ founder 2026-08-31: drop the destination, not the agent.
  describe "the ONE-Alloy invariant [⚖️ 2026-08-31]" do
    let(:canopy_config) { YAML.load_file(REPO_ROOT.join("config/deploy.canopy.yml")) }

    let(:deploy_workflows) do
      %w[.github/workflows/deploy.yml .github/workflows/deploy-production.yml]
        .to_h { |path| [ path, File.read(REPO_ROOT.join(path)) ] }
    end

    it "boots the accessory with NO destination flag, so its label matches what it scrapes" do
      offenders = deploy_workflows.filter_map do |path, text|
        path if text.match?(/kamal\s+accessory\s+boot\s+\S+\s+-d\s/)
      end
      expect(offenders).to be_empty,
                           "a deploy workflow boots an accessory with `-d <destination>`: #{offenders.inspect}. " \
                           "Both destinations resolve to the SAME container `silken_net-alloy` on the SAME host, " \
                           "so this does not create a per-slot agent — it stamps that destination's " \
                           "DEPLOYMENT_SLOT onto the production targets config.alloy actually scrapes."
    end

    it "keeps canopy free of an accessory override, so no slot label can diverge from the scrape" do
      expect(canopy_config).not_to have_key("accessories"),
                                   "config/deploy.canopy.yml declares an `accessories:` override. Canopy has no " \
                                   "scrape targets (alias-less by construction — invariant B3), so any accessory " \
                                   "value it sets can only relabel the single shared agent."
    end

    # Size pin: both examples above go green loudest on an empty set — a renamed workflow or a
    # canopy manifest that stopped parsing would look like compliance.
    it "judges a non-empty set of real workflows and a canopy manifest that parses" do
      expect(deploy_workflows.size).to eq(2)
      expect(deploy_workflows.values).to all(include("kamal"))
      expect(canopy_config).to include("servers")
    end
  end
end
