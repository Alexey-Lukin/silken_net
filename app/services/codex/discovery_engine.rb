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
# coverage):
#   - tree_observation_minutes  → Σ minutes of telemetry from any tree
#                                  the user has observed (presence-touched)
#   - match_count               → user's `Codex::Match` count
#   - attunement_streak_days    → consecutive-days streak of attunements
#   - oracle_dispatched         → user has any `oracle_status_dispatched`
#                                  TelemetryLog (attempts gated by `present?`)
#
# Deferred (no adapter yet — DAO can't create such rules until Phase 6):
#   - acoustic_class_count      → needs join across TelemetryLog acoustic events
#   - cluster_visited           → needs Cluster check-in feature
#   - firmware_version_seen     → trivial, not in seed list
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

      unlocked.uniq
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
        # which the user was the *presence-touched observer* of any
        # tree that emitted telemetry. We don't track per-user observation
        # time precisely (would require a side log) — instead we use the
        # number of TelemetryLog rows recorded during the window times the
        # `effective_period_minutes` (= 5 by default) as a proxy.
        window  = (rule.params["window_days"] || 30).to_i.days.ago
        per_log = (rule.params["effective_period_minutes"] || 5).to_i
        observed_logs = TelemetryLog
                          .where("created_at >= ?", window)
                          .joins(tree: :wallet)
                          .where(wallets: { user_id: user.id })
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
        # a tree owned by the user has reached `oracle_status_dispatched`
        # at least `threshold_value` times. Cheap aggregate query.
        TelemetryLog
          .joins(tree: :wallet)
          .where(wallets: { user_id: user.id })
          .where(oracle_status: %w[dispatched fulfilled])
          .count >= rule.threshold_value
      }
    }.freeze
  end
end
