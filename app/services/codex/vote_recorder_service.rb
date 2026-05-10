# frozen_string_literal: true

# Codex::VoteRecorderService — converts a Battle Arena vote into a
# `Codex::Match` row plus an Elo-update job.
#
# Replay protection: the `pair_seed` Redis key (set by `PairSelectorService`)
# is consumed (DEL) on first use. A second submission with the same seed
# fails with `seed_invalid_or_consumed`.
#
# Elo math: standard formula with K = 32 (`Codex::EloMath.compute_delta`).
# Skips (no winner) record `0/0` deltas — the Match row exists for
# selection-heuristic purposes (avoid showing the same pair).
#
# The Match insert and the Elo-recompute enqueue are decoupled: we write
# the Match synchronously (so the Turbo Stream response can echo the
# fresh state), and update Node Elo asynchronously on the `low` queue
# (ADR-CDX-4 — Battle never blocks Proof-of-Growth hot-path).
module Codex
  class VoteRecorderService
    Result = Struct.new(:success, :match, :error, keyword_init: true) do
      alias_method :success?, :success
    end

    REDIS_PREFIX = ::Codex::PairSelectorService::REDIS_PREFIX

    def self.call(...)
      new(...).call
    end

    # @param user [User]
    # @param pair_seed [String] HMAC from PairSelectorService
    # @param winner_slug [String, nil] slug of the chosen Node — nil for skip
    # @param skip [Boolean] explicit skip flag (alternative to winner_slug=nil)
    def initialize(user:, pair_seed:, winner_slug: nil, skip: false)
      @user        = user
      @pair_seed   = pair_seed
      @winner_slug = winner_slug
      @skip        = skip
    end

    def call
      return failure("user is required")      unless @user&.persisted?
      return failure("pair_seed is required") if    @pair_seed.blank?

      payload = consume_seed
      return failure("seed_invalid_or_consumed") unless payload

      realm_id, left_id, right_id = payload[:realm_id], payload[:left_id], payload[:right_id]
      return failure("seed_user_mismatch") if payload[:user_id] != @user.id

      left  = ::Codex::Node.find_by(id: left_id)
      right = ::Codex::Node.find_by(id: right_id)
      return failure("nodes_missing") unless left && right

      winner = resolve_winner(left, right)
      return failure("winner_not_in_pair") if winner == :invalid

      delta_left, delta_right = compute_deltas(left, right, winner)

      match = ::Codex::Match.create!(
        user_id:         @user.id,
        codex_realm_id:  realm_id,
        left_node_id:    left.id,
        right_node_id:   right.id,
        winner_node_id:  winner&.id,
        pair_seed:       @pair_seed,
        elo_delta_left:  delta_left,
        elo_delta_right: delta_right
      )

      ::Codex::EloRecomputeWorker.perform_async(
        left.id, right.id, delta_left, delta_right
      )

      Result.new(success: true, match: match, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.join("; "))
    end

    private

    def consume_seed
      r = Kredis.redis(config: :shared)
      key = "#{REDIS_PREFIX}#{@pair_seed}"
      # Atomic get-and-delete: avoids TOCTOU race between get and del.
      raw = r.call("GETDEL", key)
      return nil unless raw

      user_id, realm_id, left_id, right_id, _ts = raw.to_s.split("|").map(&:to_i)
      { user_id: user_id, realm_id: realm_id, left_id: left_id, right_id: right_id }
    rescue StandardError => e
      Rails.logger.warn "[Codex::VoteRecorderService] redis unavailable: #{e.class}"
      nil
    end

    def resolve_winner(left, right)
      return nil if @skip
      return nil if @winner_slug.blank?
      return left  if @winner_slug == left.slug
      return right if @winner_slug == right.slug

      :invalid
    end

    # Standard Elo with K=32. Skips → 0/0.
    def compute_deltas(left, right, winner)
      return [ 0, 0 ] if winner.nil?

      ::Codex::EloMath.deltas(
        left_elo:  left.attunement_elo,
        right_elo: right.attunement_elo,
        winner:    winner.id == left.id ? :left : :right
      )
    end

    def failure(reason)
      Result.new(success: false, match: nil, error: reason)
    end
  end
end
