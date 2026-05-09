# frozen_string_literal: true

# Codex::DiscoveryProbeWorker — async fan-out for the Discovery layer.
#
# Trigger sources:
#   * `TelemetryUnpackerService` finalizer (one job per active observer)
#   * `Codex::EloRecomputeWorker` (after a battle vote — match_milestone)
#   * `Codex::FractionChangeService` (fraction_choice)
#   * `Codex::AttunementsController` (attunement_streak)
#
# Why a single worker rather than four: the rule registry is the same
# regardless of trigger; only the engine's payload differs. Keeping one
# entry-point keeps observability uniform (one queue, one alert path).
#
# Queue choice: `default` per ADR-CDX-4 — Discovery is a cosmetic
# unlock, never on the Proof-of-Growth critical path.
#
# Idempotency:
#   * `Discovery` has UNIQUE `(user_id, codex_node_id)` — concurrent
#     workers may both try to insert; one wins, the other gets a
#     RecordNotUnique we silently swallow.
#   * Broadcast is fired only on actual create (after the `find_or_create_by`
#     branch returns a fresh record) — no double-toast on retry.
module Codex
  class DiscoveryProbeWorker
    include Sidekiq::Worker

    sidekiq_options queue: "default", retry: 3

    def perform(user_id, trigger_type, payload = {})
      user = User.find_by(id: user_id)
      return unless user

      unlocked_nodes = ::Codex::DiscoveryEngine.evaluate(
        user: user,
        trigger_type: trigger_type,
        payload: payload || {}
      )
      return if unlocked_nodes.empty?

      unlocked_nodes.each do |node|
        record = create_discovery!(user, node, trigger_type, payload)
        broadcast(user, record) if record
      end
    end

    private

    def create_discovery!(user, node, trigger_type, payload)
      ref_type = payload["trigger_ref_type"] || payload[:trigger_ref_type]
      ref_id   = payload["trigger_ref_id"]   || payload[:trigger_ref_id]

      record = ::Codex::Discovery.create_with(
        trigger_type:     trigger_type.to_s,
        trigger_ref_type: ref_type,
        trigger_ref_id:   ref_id,
        unlocked_at:      Time.current
      ).find_or_create_by(user_id: user.id, codex_node_id: node.id)

      # Only broadcast when *we* are the creator. `previously_new_record?`
      # is true exactly once per row across concurrent workers — it stays
      # false for the loser of the find-or-create race.
      record.previously_new_record? ? record : nil
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      nil
    rescue ArgumentError => e
      Rails.logger.warn "[Codex::DiscoveryProbeWorker] #{e.class}: #{e.message}"
      nil
    end

    def broadcast(user, discovery)
      payload = {
        slug:           discovery.node.slug,
        title_en:       discovery.node.title_en,
        title_uk:       discovery.node.title_uk,
        archetype_key:  discovery.node.archetype_key,
        trigger_type:   discovery.trigger_type,
        unlocked_at:    discovery.unlocked_at.iso8601
      }
      ActionCable.server.broadcast("codex:discoveries:user:#{user.id}", payload)
    rescue StandardError => e
      Rails.logger.warn "[Codex::DiscoveryProbeWorker] broadcast failed: #{e.class}"
    end
  end
end
