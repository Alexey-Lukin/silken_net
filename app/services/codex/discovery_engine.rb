# frozen_string_literal: true

# Codex::DiscoveryEngine — pure rule evaluator.
#
# Input contract:
#   `evaluate(user:, trigger_type:, payload:)` → `Array<Codex::Node>`
#     trigger_type: one of `Codex::Discovery::TRIGGER_TYPES.keys` (Symbol/String)
#     payload:      Hash specific to the trigger (see ADAPTERS below)
#
# Output: array of Nodes the user just unlocked. Caller (DiscoveryProbeWorker)
# is responsible for the actual `Codex::Discovery.create!` and broadcast.
#
# Engine reads `DiscoveryRule.cached_active_by_condition` once, dispatches
# to a per-condition adapter, and skips any rule whose Node the user has
# already unlocked.
#
# Adapters intentionally accept the same `(user, rule, payload)` signature
# so adding a new condition is a one-file diff. Returning `true` means
# "the rule fires for this user now"; `false` means "not yet".
#
# Implemented in Phase 5 (4 of 7 condition_types — 80 % of seed-rule
# coverage). **Phase 6 expansion adds the remaining 3 adapters:**
#   - tree_observation_minutes  → Σ minutes of telemetry from any tree
#                                  the user has observed (presence-touched)
#   - match_count               → user's `Codex::Match` count
#   - attunement_streak_days    → consecutive-days streak of attunements
#   - oracle_dispatched         → user has any `oracle_status_dispatched`
#                                  TelemetryLog (attempts gated by `present?`)
#   - acoustic_class_count      → count of TelemetryLog rows whose
#                                  `acoustic_events` count crosses the
#                                  `min_events` threshold (proxy for
#                                  high-class acoustic activity)
#   - cluster_visited           → count of TelemetryLog rows from the
#                                  user's trees inside cluster matching
#                                  `params["cluster_name"]`
#   - firmware_version_seen     → count of TelemetryLog rows whose
#                                  attached BioContractFirmware version
#                                  matches `params["version"]`
#
# An unknown condition_type is logged & skipped (never raises).
module Codex
  class DiscoveryEngine
    def self.evaluate(...)
      new(...).evaluate
    end

    def initialize(user:, trigger_type:, payload: {})
      @user         = user
      @trigger_type = trigger_type.to_sym
      @payload      = (payload || {}).symbolize_keys
    end

    def evaluate
      return [] unless @user&.persisted?

      already = ::Codex::Discovery.where(user_id: @user.id).pluck(:codex_node_id).to_set
      unlocked = []

      rules_by_condition.each do |condition_type, rules|
        adapter = ADAPTERS[condition_type.to_sym]
        unless adapter
          Rails.logger.debug "[Codex::DiscoveryEngine] no adapter for #{condition_type}"
          next
        end

        rules.each do |rule|
          next if already.include?(rule.codex_node_id)
          unlocked << rule.node if adapter.call(@user, rule, @payload)
        end
      end

      unlocked.uniq(&:id)
    end

    private

    def rules_by_condition
      ::Codex::DiscoveryRule.cached_active_by_condition
    end

    # ------------------------------------------------------------------
    # Adapters
    # ------------------------------------------------------------------

    ADAPTERS = {
      tree_observation_minutes: ->(user, rule, _payload) {
        # Approximation: count distinct minutes in the last 30 d in
        # which any tree owned by the user's org emitted telemetry
        # (Wallet is org-scoped, not user-scoped — see Wallet model).
        # We don't track per-user observation time precisely (would
        # require a side log); the proxy is `count(rows) × effective_period_minutes`.
        return false if user.organization_id.blank?
        window  = (rule.params["window_days"] || 30).to_i.days.ago
        per_log = (rule.params["effective_period_minutes"] || 5).to_i
        observed_logs = TelemetryLog
                          .where("telemetry_logs.created_at >= ?", window)
                          .joins(tree: :wallet)
                          .where(wallets: { organization_id: user.organization_id })
                          .count
        observed_logs * per_log >= rule.threshold_value
      },

      match_count: ->(user, rule, _payload) {
        scope = ::Codex::Match.where(user_id: user.id)
        if (realm_slug = rule.params["realm_slug"])
          realm = ::Codex::Realm.find_by(slug: realm_slug)
          scope = scope.where(codex_realm_id: realm.id) if realm
        end
        scope.count >= rule.threshold_value
      },

      attunement_streak_days: ->(user, rule, _payload) {
        days_back = rule.threshold_value.to_i
        # `< 1`-then dead: threshold_value validates numericality greater_than_or_equal_to: 1
        # (model) → days_back ≥ 1 завжди; guard захищає від невалідного rule (§B.4 leave).
        return false if days_back < 1

        # Distinct days in the last N days on which the user attuned
        # at least once. Streak = consecutive trailing days from today.
        attunement_days = ::Codex::Attunement
                            .where(user_id: user.id)
                            .where("created_at >= ?", (days_back + 1).days.ago)
                            .pluck(Arel.sql("DATE(created_at)"))
                            .to_set
        streak = 0
        days_back.times do |i|
          break unless attunement_days.include?((Time.current.utc.to_date - i))
          streak += 1
        end
        streak >= days_back
      },

      oracle_dispatched: ->(user, rule, _payload) {
        # Oracle-related milestone: unlock when a TelemetryLog tied to
        # any tree owned by the user's org has reached `oracle_status`
        # = dispatched/fulfilled at least `threshold_value` times.
        # Cheap aggregate query.
        return false if user.organization_id.blank?
        TelemetryLog
          .joins(tree: :wallet)
          .where(wallets: { organization_id: user.organization_id })
          .where(oracle_status: %w[dispatched fulfilled])
          .count >= rule.threshold_value
      },

      acoustic_class_count: ->(user, rule, _payload) {
        # `acoustic_events` is the per-packet event count produced by
        # the on-device TinyML INT8 classifier (firmware/soldier/main.c).
        # We treat *high-acoustic* packets (>= `min_events`) as a proxy
        # for "the user's org's trees recorded a noteworthy acoustic class
        # ≥ threshold_value times." `params["min_events"]` defaults to
        # 20 (the well-known cavitation/chainsaw threshold from the
        # `:high_acoustic_activity` scope on `TelemetryLog`).
        return false if user.organization_id.blank?
        min_events = (rule.params["min_events"] || 20).to_i
        TelemetryLog
          .joins(tree: :wallet)
          .where(wallets: { organization_id: user.organization_id })
          .where("acoustic_events >= ?", min_events)
          .count >= rule.threshold_value
      },

      cluster_visited: ->(user, rule, _payload) {
        # Unlock when ≥ threshold_value telemetry packets from the user's
        # org's trees have been recorded inside a target cluster. `Cluster`
        # has no `slug` column at the moment, so the rule is keyed by the
        # human-readable `name` (case-sensitive). Returning false on a
        # missing/blank `cluster_name` keeps the rule inert — DAO must
        # supply the param explicitly.
        cluster_name = rule.params["cluster_name"].to_s
        return false if cluster_name.blank?
        return false if user.organization_id.blank?

        cluster = ::Cluster.find_by(name: cluster_name)
        return false if cluster.nil?

        TelemetryLog
          .joins(tree: :wallet)
          .where(wallets: { organization_id: user.organization_id })
          .where(trees: { cluster_id: cluster.id })
          .count >= rule.threshold_value
      },

      firmware_version_seen: ->(user, rule, _payload) {
        # Unlock when ≥ threshold_value packets emitted by the user's
        # org's trees were running firmware of `params["version"]`.
        # Useful as a "you upgraded" badge after an OTA wave. Inert when
        # no `version` is supplied or no firmware row matches that version.
        version = rule.params["version"].to_s
        return false if version.blank?
        return false if user.organization_id.blank?

        firmware_ids = ::BioContractFirmware.where(version: version).pluck(:id)
        return false if firmware_ids.empty?

        TelemetryLog
          .joins(tree: :wallet)
          .where(wallets: { organization_id: user.organization_id })
          .where(firmware_version_id: firmware_ids)
          .count >= rule.threshold_value
      }
    }.freeze
  end
end
