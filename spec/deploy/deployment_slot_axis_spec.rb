# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "yaml"
require_relative "../support/repo_root"

# [INF.27] BOTH deploy slots run RAILS_ENV=production — canopy deliberately, because it wants
# the hardened runtime. So `Rails.env` cannot discriminate them, and every surface that NAMES,
# NAMESPACES or TAGS a shared external resource with it stamps `production` twice.
#
# 🔴 The class fails SILENTLY and in the expensive direction: a WRONG label, not a missing one.
# An empty field is visible in a dashboard; `environment: production` on a canopy stack trace
# is not. `config/deploy.canopy.yml` already argues exactly this for the Alloy `slot` label —
# this spec is that argument given a carrier for the Rails roles, which it had not reached.
#
# ⚠️ DECLARED CEILING: this judges the surfaces NAMED below, never "every possible slot label".
# A new consumer that stamps `Rails.env` onto a shared resource is invisible here until someone
# adds its row — the list is the specification of what is guarded, exactly like the metric
# registry. What the list DOES buy is that none of the known five silently regresses.
# Each row: the file, a regex anchored on the ASSIGNMENT (not the file), and what it names.
# Anchoring on the assignment is the whole point — a file-wide grep for "DeploymentSlot" would
# pass on a doc comment that mentions it while the live expression still reads Rails.env.
# Declared at file scope (not inside the example group) so the examples can be generated from
# it without tripping RSpec/LeakyConstantDeclaration.
SLOT_LABEL_SURFACES = {
  "config/initializers/sentry.rb" => [ /^\s*config\.environment\s*=\s*(.+)$/, "the Sentry environment facet" ],
  "config/cache.yml" => [ /^\s*namespace:\s*(.+)$/, "the cache key namespace" ],
  "config/environments/production.rb" => [ /^\s*current_slot\s*=\s*(.+)$/, "the JSON log origin field" ]
}.freeze

RSpec.describe "Deployment-slot axis reaches the Rails roles (INF.27)" do # rubocop:disable RSpec/DescribeClass
  def yaml_at(path) = YAML.safe_load(File.read(REPO_ROOT.join(path)), aliases: true)
  def source(path)  = File.read(REPO_ROOT.join(path))

  let(:base)   { yaml_at("config/deploy.yml") }
  let(:canopy) { yaml_at("config/deploy.canopy.yml") }

  # [S2.4] Sibling facet: the release. Kamal injects `KAMAL_VERSION` (git sha) into every
  # container; `RELEASE_VERSION` is an explicit override only. Both go through `.presence`
  # because the present-but-EMPTY form is the one Sentry silently discards (measured 2026-09-02).
  it "reads the Sentry release from Kamal's injected KAMAL_VERSION, RELEASE_VERSION as override, both via presence" do
    line = source("config/initializers/sentry.rb")[/^\s*config\.release\s*=\s*(.+)$/, 1]

    expect(line).to eq('ENV["RELEASE_VERSION"].presence || ENV["KAMAL_VERSION"].presence')
  end

  describe "the declaration itself" do
    it "is set for the Rails roles in the base manifest" do
      expect(base.dig("env", "clear", "DEPLOYMENT_SLOT")).to eq("production")
    end

    it "is overridden by canopy — a shared value would be worse than none" do
      expect(canopy.dig("env", "clear", "DEPLOYMENT_SLOT")).to eq("canopy")
    end

    # The var was BORN on the accessory; extending it to the roles must not displace the
    # observability half, whose `slot` label the Grafana panels and alert rules split on
    # (spec/deploy/grafana_alerts_spec.rb).
    #
    # 🔴 But "two homes, one value, both required" — what this example asserted until
    # 2026-08-31 — was TRUE of the ROLES and FALSE of the ACCESSORY, and the difference is
    # structural, not editorial. There is exactly ONE Alloy container for both slots:
    # `Kamal::Configuration::Accessory#service_name` is `"#{config.service}-#{name}"` and
    # `config.service` carries no destination, so both slots resolve to `silken_net-alloy`,
    # and canopy inherited the base `host` because it overrode only `env.clear`. A canopy
    # value there was therefore not a second home — it RELABELLED the single shared agent,
    # and `accessory boot` skips the loser silently, so the winner was whoever booted first
    # (canopy on every main push, production only on a Release). ⚖️ founder 2026-08-31:
    # the accessory boots with NO destination, and canopy declares no override at all.
    # Full mechanism + the one-Alloy pins: spec/deploy/alloy_scrape_topology_spec.rb.
    it "reaches the Alloy accessory on the base manifest, and ONLY there" do
      expect(base.dig("accessories", "alloy", "env", "clear", "DEPLOYMENT_SLOT")).to eq("production")
      # Scoped to `alloy` since 2026-09-03: canopy legitimately declares its OWN Redis accessory
      # [INF.28], which the base manifest never names — that is a second container, not a relabel.
      expect(canopy.dig("accessories", "alloy")).to be_nil,
                                                   "canopy re-declared the Alloy accessory: with one shared container that " \
                                                   "cannot create a per-slot agent, it can only mislabel production's series"
    end

    # ⚠️ `present` first, THEN `differs`. Written as a bare `not_to eq` this example survived
    # the removal of the canopy override entirely — `nil != "production"` is true, so an ABSENT
    # declaration read as a distinct one. Caught by mutation, not by review.
    it "declares different values per slot — an equal OR ABSENT pair discriminates nothing" do
      # Plain Ruby, not `be_present`: this suite runs on spec_helper (offline, no Rails boot),
      # so ActiveSupport core_ext is NOT loaded here.
      pair = [ base, canopy ].map { |cfg| cfg.dig("env", "clear", "DEPLOYMENT_SLOT") }
      expect(pair.compact.reject(&:empty?).size).to eq(2), "one slot declares nothing: #{pair.inspect}"
      expect(pair.uniq.size).to eq(2)
    end
  end

  SLOT_LABEL_SURFACES.each do |path, (anchor, what)|
    it "reads the slot One-Home for #{what} (#{path})" do
      matches = source(path).scan(anchor).flatten
      expect(matches.size).to eq(1), "expected exactly one assignment in #{path}, found #{matches.size}"
      expect(matches.first).to include("SilkenNet::DeploymentSlot"),
                               "#{path} still labels #{what} with: #{matches.first}"
    end
  end

  # storage.yml carries TWO buckets and they must move together: `production_mirror` writes to
  # both services, so splitting only the primary would still let canopy pollute the DR mirror —
  # the one copy that has to be trustworthy during a restore.
  it "reads the slot One-Home for BOTH Active Storage buckets" do
    buckets = source("config/storage.yml").scan(/^\s*bucket:\s*(.+)$/).flatten
    expect(buckets.size).to eq(2), "expected 2 bucket declarations, found #{buckets.size}"
    expect(buckets).to all(include("SilkenNet::DeploymentSlot"))
  end

  it "leaves no `Rails.env` stamping a guarded surface" do
    offenders = (SLOT_LABEL_SURFACES.keys + [ "config/storage.yml" ]).uniq.select do |path|
      anchors = path == "config/storage.yml" ? [ /^\s*bucket:\s*(.+)$/ ] : [ SLOT_LABEL_SURFACES.fetch(path).first ]
      anchors.any? { |a| source(path).scan(a).flatten.any? { |line| line.include?("Rails.env") } }
    end
    expect(offenders).to be_empty, "slot-label surfaces still on Rails.env: #{offenders.join(', ')}"
  end

  # ⚠️ Size pin. Every "no offenders" example above is green on an empty set, and the set here
  # is a hand-written constant — so an accidental empty/renamed map would read as success.
  it "judges a non-empty surface set" do
    expect(SLOT_LABEL_SURFACES.size).to eq(3)
    SLOT_LABEL_SURFACES.each_key { |path| expect(REPO_ROOT.join(path)).to exist }
  end
end
