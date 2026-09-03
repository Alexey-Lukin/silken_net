# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "kamal"
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
#
# ⚖️ [OPS.37 founder 2026-09-03] Canopy is SCRAPED too — under its own `canopy-*` aliases, with
# `slot = "canopy"` carried ON THE TARGET (a target label wins over the accessory's
# `external_labels`, so every `silken-*` series keeps the production label the ONE agent stamps).
# Until then canopy was deliberately unscraped and its dashboard read «No data» everywhere. The
# invariant that used to be "canopy aliases are disjoint from the scraped set" is now two
# halves: a canopy role never answers to a production alias, and a canopy alias is scraped ONLY
# with an explicit slot label — a canopy target without one would land as production.
# Declared ceiling: this spec judges the DECLARATION pair, never live DNS — whether Docker
# actually serves the alias was measured once (2026-08-30, two containers sharing an alias
# through a rolling window) and is re-proven by `up` / sn-alert-scrape-target-down at runtime;
# whether the target label really outranks `external_labels` is proven by the first canopy
# series in Grafana Cloud (measured 2026-09-03: up{instance="canopy-web:80",slot="canopy"} = 1 — 00_07 OPS.37), not here.
RSpec.describe "config.alloy declares the scrape topology (S2.4: 3 production + 2 canopy targets)" do # rubocop:disable RSpec/DescribeClass
  # __address__ → [process, slot] — the load-bearing map (06_03 §2.9): web never sees worker
  # increments; the slot label is the third field, present only on canopy targets.
  let(:targets) do
    text = File.read(REPO_ROOT.join("deploy/alloy/config.alloy"))
    # \s spans newlines, and ,? tolerates the trailing comma `alloy fmt` adds in the multi-line
    # form (`"process" = "web",\n}`) — so a legit reformat can't false-alarm the guard.
    text.scan(/\{\s*"__address__"\s*=\s*"([^"]+)",\s*"process"\s*=\s*"([^"]+)"(?:,\s*"slot"\s*=\s*"([^"]+)")?,?\s*\}/)
        .to_h { |address, process, slot| [ address, [ process, slot ] ] }
  end

  let(:deploy_config) { YAML.load_file(REPO_ROOT.join("config/deploy.yml")) }

  let(:canopy_servers) do
    Kamal::Configuration.create_from(config_file: REPO_ROOT.join("config/deploy.yml"),
                                     destination: "canopy").raw_config["servers"]
  ensure
    ENV.delete("KAMAL_DESTINATION") # `create_from` sets it as a side effect
  end

  let(:canopy_aliases) do
    hosted = canopy_servers.select { |_, role| role.is_a?(Hash) && Array(role["hosts"]).any? }
    hosted.transform_values { |role| role.dig("options", "network-alias") }
  end

  it "pins the ratified alias:port per process — production unlabelled, canopy labelled slot=canopy" do
    expect(targets).to eq(
      "silken-web:80"    => [ "web", nil ],
      "silken-job:9394"  => [ "job", nil ],
      "silken-coap:9395" => [ "coap", nil ],
      "canopy-web:80"    => [ "web", "canopy" ],
      "canopy-job:9394"  => [ "job", "canopy" ]
    ), "config.alloy drifted from the ratified scrape topology (⚖️ OPS.37 2026-08-30 + 2026-09-03, 06_03 §2.9) — " \
       "a missing job/coap target, a port-typo, a broken process-label or a canopy target without " \
       "its slot label makes those metrics scrape as eternal zeros or as PRODUCTION: got #{targets.inspect}"
  end

  it "finds every scraped alias declared as network-alias on a role (production in deploy.yml, canopy in the merged manifest)" do
    declared = deploy_config.fetch("servers").values.filter_map { |role| role["options"]&.[]("network-alias") } +
               canopy_aliases.values.compact
    scraped  = targets.keys.map { |address| address.split(":").first }
    expect(scraped - declared).to be_empty,
                                  "config.alloy scrapes aliases no role declares — Docker DNS " \
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
  # have carried `slot="canopy"`. ⚖️ founder 2026-08-31: drop the destination, not the agent.
  # Since 2026-09-03 the slot of a canopy series comes from its TARGET, so the agent's own
  # label must stay production for the `silken-*` targets it also scrapes.
  describe "the ONE-Alloy invariant [⚖️ 2026-08-31]" do
    let(:canopy_config) { YAML.load_file(REPO_ROOT.join("config/deploy.canopy.yml")) }

    let(:deploy_workflows) do
      %w[.github/workflows/deploy.yml .github/workflows/deploy-production.yml]
        .to_h { |path| [ path, File.read(REPO_ROOT.join(path)) ] }
    end

    it "boots the accessory with NO destination flag, so its label matches the production targets" do
      offenders = deploy_workflows.filter_map do |path, text|
        path if text.match?(/kamal\s+accessory\s+boot\s+\S+\s+-d\s/)
      end
      expect(offenders).to be_empty,
                           "a deploy workflow boots an accessory with `-d <destination>`: #{offenders.inspect}. " \
                           "Both destinations resolve to the SAME container `silken_net-alloy` on the SAME host, " \
                           "so this does not create a per-slot agent — it stamps that destination's " \
                           "DEPLOYMENT_SLOT onto the production targets config.alloy scrapes unlabelled."
    end

    it "keeps canopy free of an accessory override, so the agent's label cannot diverge from its production targets" do
      expect(canopy_config).not_to have_key("accessories"),
                                   "config/deploy.canopy.yml declares an `accessories:` override. Canopy's slot " \
                                   "rides on its TARGETS (config.alloy), so any accessory value it sets can only " \
                                   "relabel the single shared agent — and with it every production series."
    end

    # [OPS.37 ⚖️ founder 2026-09-02 → 2026-09-03] Canopy is no longer alias-less: its `servers:` is
    # the HASH form (own job role), and a hash role INHERITS the base `options.network-alias`
    # unless it overrides it — so a canopy web container answering to `silken-web` on the shared
    # `kamal` network would be scraped as PRODUCTION. Every hosted canopy role must therefore
    # declare its own alias (an omitted alias is the inherited one, not no alias), that alias
    # must not collide with a production one, and — since canopy IS scraped — every scraped
    # canopy alias must carry the slot label on its target while no production alias carries one.
    # ⚠️ Review 2026-09-02: judged on the MERGED config, not the raw canopy YAML — a canopy role
    # that omits `hosts:` inherits the base hosts AND the base alias, and the raw file shows
    # neither; the raw filter `Array(role["hosts"]).any?` skipped exactly that case.
    it "gives every hosted canopy role its own alias, scraped ONLY with slot=canopy (production targets unlabelled)" do
      expect(canopy_servers).to be_a(Hash), "canopy fell back to the alias-less array form — the scrape targets now expect canopy-* aliases"
      expect(canopy_aliases.size).to be >= 2, "canopy resolves #{canopy_aliases.size} hosted roles — parser drift?"
      missing = canopy_aliases.select { |_, a| a.nil? }.keys
      expect(missing).to be_empty,
                         "canopy roles #{missing.inspect} declare no network-alias — they INHERIT the base " \
                         "alias via deep_merge and get scraped as production"
      production_aliases = deploy_config.fetch("servers").values.filter_map { |role| role["options"]&.[]("network-alias") }
      expect(canopy_aliases.values & production_aliases).to be_empty,
                                                            "canopy aliases collide with production aliases: " \
                                                            "#{(canopy_aliases.values & production_aliases).inspect}"
      targets.each do |address, (_process, slot)|
        host = address.split(":").first
        if canopy_aliases.value?(host)
          expect(slot).to eq("canopy"), "#{address} is a canopy alias scraped WITHOUT slot=\"canopy\" — its series would land as production"
        else
          expect(slot).to be_nil, "#{address} is a production alias carrying a slot label — the accessory's external label is the one home for production"
        end
      end
    end

    # Size pin: the examples above go green loudest on an empty set — a renamed workflow or a
    # canopy manifest that stopped parsing would look like compliance.
    it "judges a non-empty set of real workflows and a canopy manifest that parses" do
      expect(deploy_workflows.size).to eq(2)
      expect(deploy_workflows.values).to all(include("kamal"))
      expect(canopy_config).to include("servers")
    end
  end
end
