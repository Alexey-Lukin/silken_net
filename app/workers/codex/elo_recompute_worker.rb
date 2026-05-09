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
    end

    private

    def bump(node_id, delta)
      ::Codex::Node
        .where(id: node_id)
        .update_all([ "attunement_elo = attunement_elo + ?, match_count = match_count + 1, updated_at = ?",
                      delta.to_i, Time.current ])
    end
  end
end
