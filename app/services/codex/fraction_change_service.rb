# frozen_string_literal: true

# Codex::FractionChangeService — single point of mutation for a user's
# fraction.
#
# Two outcomes (success):
#   * **Initial pick** — no row exists yet; create one with `chosen_at` =
#     `last_changed_at` = now. No cooldown applies.
#   * **Re-pick** — an existing row, last_changed_at + COOLDOWN <= now.
#     Update node + archetype_key + last_changed_at. `chosen_at` stays
#     immutable (it's the user's "since" date).
#
# One failure (handled, not raised): cooldown still active. Returns a
# `Result` whose `success?` is false and whose `cooldown_until` lets the
# UI show the "next pick at …" message.
#
# Audit trail: enqueued via `Codex::FractionAuditWorker` (queue `default`,
# ADR-CDX-4 — never on hot path). The worker, not this service, writes to
# `audit_logs`, because audit_logs is the chained-hash ledger and the
# service must remain transactionally short.
module Codex
  class FractionChangeService
    Result = Struct.new(
      :success, :fraction, :cooldown_until, :previous_node_id, :errors,
      keyword_init: true
    ) do
      alias_method :success?, :success
    end

    def self.call(...)
      new(...).call
    end

    # @param user [User] caller (must be persisted)
    # @param node [Codex::Node] target node (must be persisted)
    # @param now  [Time] injectable clock for specs
    def initialize(user:, node:, now: Time.current)
      @user = user
      @node = node
      @now  = now
    end

    def call
      return invalid("user is required")  unless @user&.persisted?
      return invalid("node is required")  unless @node&.persisted?
      if %w[destroyed extinct].include?(@node.lifecycle_status)
        return invalid("node is not pickable")
      end

      fraction = ::Codex::Fraction.find_or_initialize_by(user_id: @user.id)
      previous_node_id = fraction.codex_node_id

      if fraction.persisted? && fraction.cooldown_active?(@now)
        return cooldown_blocked(fraction)
      end

      ::Codex::Fraction.transaction do
        fraction.codex_node_id    = @node.id
        fraction.archetype_key    = @node.archetype_key
        fraction.house_color_token = @node.realm.accent_token
        fraction.last_changed_at  = @now
        fraction.chosen_at      ||= @now
        fraction.save!
      end

      enqueue_audit(fraction, previous_node_id: previous_node_id)
      enqueue_discovery_probe(fraction, previous_node_id: previous_node_id)
      Result.new(
        success: true, fraction: fraction, cooldown_until: nil,
        previous_node_id: previous_node_id, errors: []
      )
    rescue ActiveRecord::RecordInvalid => e
      Result.new(
        success: false, fraction: e.record, cooldown_until: nil,
        previous_node_id: previous_node_id, errors: e.record.errors.full_messages
      )
    end

    private

    def invalid(message)
      Result.new(
        success: false, fraction: nil, cooldown_until: nil,
        previous_node_id: nil, errors: [ message ]
      )
    end

    def cooldown_blocked(fraction)
      Result.new(
        success: false, fraction: fraction,
        cooldown_until: fraction.cooldown_until,
        previous_node_id: fraction.codex_node_id,
        errors: [ "cooldown_active" ]
      )
    end

    def enqueue_audit(fraction, previous_node_id:)
      ::Codex::FractionAuditWorker.perform_async(
        fraction.user_id, fraction.id, previous_node_id
      )
    rescue StandardError
      # The audit trail is async by design. A transient enqueue failure
      # must not roll back a legitimate user-facing fraction change.
      nil
    end

    # Phase 6 cross-domain stitch — fraction choice triggers a Discovery
    # probe. Inert until DAO ships a `condition_type: fraction_choice`
    # adapter (none yet — Phase 6+), but enqueueing now means the wire-up
    # is in place and rule activation is a one-line DAO config change.
    # Fail-open like the audit enqueue: never rolls back the user-facing
    # fraction change.
    def enqueue_discovery_probe(fraction, previous_node_id:)
      return unless defined?(::Codex::DiscoveryProbeWorker)

      ::Codex::DiscoveryProbeWorker.perform_async(
        fraction.user_id,
        "fraction_choice",
        {
          "fraction_id"      => fraction.id,
          "codex_node_id"    => fraction.codex_node_id,
          "previous_node_id" => previous_node_id,
          "trigger_ref_type" => "Codex::Fraction",
          "trigger_ref_id"   => fraction.id
        }
      )
    rescue StandardError
      nil
    end
  end
end
