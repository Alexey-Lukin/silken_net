# frozen_string_literal: true

# Codex::AttunementBroadcastWorker — pushes the freshly-mutated attunement
# counter to anyone watching the Show page.
#
# Lives on the `default` queue (#5) per ADR-CDX-4: never on uplink (#1) or
# any web3_* queue. The hot Proof-of-Growth pipeline must not be slowed by
# UI broadcasts.
#
# Two channels (per docs/04_05 §8):
#   * `codex_node_<id>_attunements` — public counter for the host node;
#   * `codex_node_<id>_attunements_user_<uid>` — private "did I attune?"
#     state for the acting user only.
module Codex
  class AttunementBroadcastWorker
    include Sidekiq::Worker

    sidekiq_options queue: :default, retry: 3

    def perform(node_id, user_id)
      node = ::Codex::Node.find_by(id: node_id)
      return unless node

      # Re-read counter from DB so the broadcast reflects the post-commit
      # state — Rails' counter cache and the toggle row commit in the same
      # transaction, so by the time this enqueued job fires, the cache is
      # authoritative.
      payload = {
        node_id: node.id,
        attunement_count: node.reload.attunement_count,
        actor_user_id: user_id
      }

      ActionCable.server.broadcast("codex_node_#{node.id}_attunements", payload)
      ActionCable.server.broadcast(
        "codex_node_#{node.id}_attunements_user_#{user_id}",
        payload.merge(attuned: ::Codex::Attunement.exists?(user_id: user_id, codex_node_id: node.id))
      )
    rescue StandardError => e
      Rails.logger.error("[Codex::AttunementBroadcastWorker] #{e.class}: #{e.message}")
      raise # let Sidekiq retry per sidekiq_options
    end
  end
end
