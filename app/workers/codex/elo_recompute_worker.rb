# frozen_string_literal: true

# Codex::EloRecomputeWorker — applies pre-computed Elo deltas to the two
# nodes of a Match.
#
# Why pre-computed (delta passed as an arg, not recomputed inside the
# worker): keeps the math deterministic from the user's POV — what the
# Arena UI showed at the moment of voting is what gets persisted, even
# if another vote racing through the same node would have shifted Elo
# in the meantime.
#
# Concurrency safety: uses `UPDATE ... SET col = col + ?` — atomic at
# the DB level. No SELECT-then-UPDATE race; no need for an advisory lock.
# Both nodes update inside a single transaction (ROLLBACK keeps state
# consistent if the second update fails).
module Codex
  class EloRecomputeWorker
    include Sidekiq::Worker

    sidekiq_options queue: :low, retry: 3

    def perform(left_node_id, right_node_id, delta_left, delta_right)
      ::Codex::Node.transaction do
        bump(left_node_id, delta_left)
        bump(right_node_id, delta_right)
      end

      probe_for_match_milestone(left_node_id, right_node_id)
    end

    private

    def bump(node_id, delta)
      ::Codex::Node
        .where(id: node_id)
        .update_all([ "attunement_elo = attunement_elo + ?, match_count = match_count + 1, updated_at = ?",
                      delta.to_i, Time.current ])
    end

    # Phase 6 cross-domain stitch — every Elo-applied match probes the
    # voting user's Discovery rules (`condition_type: match_count`).
    # We resolve the user via the most recent Match referencing either
    # node — pre-computed deltas don't carry the user_id, but the row
    # was already written by `VoteRecorderService` moments before this
    # worker runs. Fail open: any error path here must NOT roll back
    # the Elo update (cosmetic).
    #
    # Partition pruning: `codex_matches` is RANGE-partitioned by
    # `created_at`. We bound the lookup to the last hour so PG only
    # scans the live partition (Sidekiq picks up jobs within seconds;
    # an hour window is forgiving even under retry backoff).
    def probe_for_match_milestone(left_id, right_id)
      return unless defined?(::Codex::DiscoveryProbeWorker)

      ids = [ left_id, right_id ]
      match = ::Codex::Match
                .where("created_at >= ?", 1.hour.ago)
                .where("left_node_id IN (?) OR right_node_id IN (?)", ids, ids)
                .order(created_at: :desc)
                .limit(1)
                .first
      return if match.nil?

      ::Codex::DiscoveryProbeWorker.perform_async(
        match.user_id,
        "match_milestone",
        {
          "match_id"         => match.id,
          "trigger_ref_type" => "Codex::Match",
          "trigger_ref_id"   => match.id
        }
      )
    rescue StandardError => e
      Rails.logger.warn "[Codex::EloRecomputeWorker] probe enqueue failed: #{e.class}: #{e.message}"
    end
  end
end
