# frozen_string_literal: true

# Codex::Match — a single Battle Arena duel.
#
# Storage: RANGE-partitioned by `created_at`. Composite PK `(id, created_at)`
# matches the project standard (`BlockchainTransaction.find_with_partition_pruning`).
#
# Lifecycle:
#   1. `Api::V1::Codex::BattleController#pair` issues a pair via
#      `Codex::PairSelectorService` — returns two pickable nodes plus a
#      HMAC-signed `pair_seed` and a Redis nonce.
#   2. User submits the vote: `Codex::VoteRecorderService` validates the
#      seed, consumes the nonce (replay protection), creates this Match,
#      and enqueues `Codex::EloRecomputeWorker`.
#   3. `winner_node_id` is one of `left_node_id` / `right_node_id` for a
#      "vote", or NULL for a "skip". Skips are still rows — they fuel
#      the PairSelector's avoidance heuristics.
#
# `realm_id` is denormalised: a duel happens *only* between two nodes of
# the same realm (Pundit / VoteRecorder enforce this). Storing the realm
# avoids a join when scoping leaderboards.
module Codex
  class Match < ApplicationRecord
    self.table_name = "codex_matches"
    # Composite PK — Rails 7+ supports it natively for partitioned tables.
    self.primary_key = [ :id, :created_at ]

    belongs_to :user
    belongs_to :realm,
               class_name: "Codex::Realm",
               foreign_key: :codex_realm_id
    belongs_to :left_node,
               class_name: "Codex::Node",
               foreign_key: :left_node_id
    belongs_to :right_node,
               class_name: "Codex::Node",
               foreign_key: :right_node_id
    belongs_to :winner_node,
               class_name: "Codex::Node",
               foreign_key: :winner_node_id,
               optional: true

    validates :pair_seed, presence: true, length: { maximum: 64 }
    validates :elo_delta_left,  presence: true, numericality: { only_integer: true }
    validates :elo_delta_right, presence: true, numericality: { only_integer: true }
    validate  :winner_must_be_one_of_the_pair
    validate  :left_and_right_differ
    validate  :pair_belongs_to_same_realm

    scope :for_user, ->(user) { where(user_id: user.id) }
    scope :for_realm, ->(realm_id) { where(codex_realm_id: realm_id) if realm_id.present? }
    scope :recent, -> { order(created_at: :desc) }

    # @return [Boolean] true when the user explicitly skipped (no winner)
    def skip?
      winner_node_id.nil?
    end

    private

    def winner_must_be_one_of_the_pair
      return if winner_node_id.nil?
      return if [ left_node_id, right_node_id ].include?(winner_node_id)

      errors.add(:winner_node_id, "must equal left_node_id or right_node_id")
    end

    def left_and_right_differ
      return if left_node_id.nil? || right_node_id.nil?
      return if left_node_id != right_node_id

      errors.add(:right_node_id, "must differ from left_node_id")
    end

    def pair_belongs_to_same_realm
      return unless left_node && right_node

      if left_node.codex_realm_id != right_node.codex_realm_id
        errors.add(:right_node_id, "must share the same realm as left_node")
      end
      if codex_realm_id.present? && codex_realm_id != left_node.codex_realm_id
        errors.add(:codex_realm_id, "must match the pair realm")
      end
    end
  end
end
