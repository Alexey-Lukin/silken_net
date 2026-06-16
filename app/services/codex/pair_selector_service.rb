# frozen_string_literal: true

# Codex::PairSelectorService — produces a vote-pair for the Battle Arena.
#
# Signed seed contract:
#
#   pair_seed = HMAC-SHA256(secret, "#{user_id}|#{realm_id}|#{ts}|#{left_id}|#{right_id}")
#
# Stored in Redis under `codex:pair_seed:<seed>` with a TTL of 5 minutes
# and the value `"#{user_id}|#{realm_id}|#{left_id}|#{right_id}|#{ts}"`.
# `VoteRecorderService` later DELs the key on first use → replay-proof,
# even within the TTL window.
#
# Selection heuristic (per docs/04_02 §10b — Codex::PairSelectorService):
#   1. Pull pickable nodes in the requested realm (lifecycle ∉ destroyed/extinct).
#   2. Anchor: random node weighted toward fewer matches (`1 / (match_count+1)`).
#   3. Opponent: random pick within ±200 Elo of the anchor — falls back
#      to "any other in realm" when the bucket has < 2 nodes.
#
# Returns `Result(success?, left:, right:, pair_seed:, realm:, error:)`.
module Codex
  class PairSelectorService
    Result = Struct.new(:success, :left, :right, :pair_seed, :realm, :error,
                        keyword_init: true) do
      alias_method :success?, :success
    end

    SEED_TTL = 5.minutes
    ELO_BUCKET = 200
    REDIS_PREFIX = "codex:pair_seed:"

    def self.call(...)
      new(...).call
    end

    # @param user [User]
    # @param realm [Codex::Realm, nil] when nil → first ordered realm
    # @param now [Time] injectable clock for specs
    def initialize(user:, realm: nil, now: Time.current)
      @user  = user
      @realm = realm
      @now   = now
    end

    def call
      return invalid("user is required") unless @user&.persisted?

      realm = @realm || ::Codex::Realm.ordered.first
      return invalid("no realm available") unless realm

      pickable = ::Codex::Node
                   .where(codex_realm_id: realm.id)
                   .where.not(lifecycle_status: %w[destroyed extinct])
      return invalid("not enough nodes in realm") if pickable.count < 2

      left  = pick_anchor(pickable)
      right = pick_opponent(pickable, left)
      return invalid("could not find opponent") unless right

      seed = sign_pair(realm.id, left.id, right.id)
      store_seed(seed, realm.id, left.id, right.id)

      Result.new(success: true, left: left, right: right,
                 pair_seed: seed, realm: realm, error: nil)
    end

    private

    def pick_anchor(scope)
      # Weighted random: nodes with fewer matches are more likely to be
      # picked, so the leaderboard converges over time even with sparse
      # voters. Implementation: sample a few candidates, pick the one
      # with the lowest match_count.
      candidates = scope.order("RANDOM()").limit(8).to_a
      candidates.min_by(&:match_count) || candidates.first
    end

    def pick_opponent(scope, anchor)
      bucket_low  = anchor.attunement_elo - ELO_BUCKET
      bucket_high = anchor.attunement_elo + ELO_BUCKET

      bucket = scope
                 .where.not(id: anchor.id)
                 .where(attunement_elo: bucket_low..bucket_high)
                 .order("RANDOM()")
                 .limit(1)
                 .first
      bucket || scope.where.not(id: anchor.id).order("RANDOM()").first
    end

    def sign_pair(realm_id, left_id, right_id)
      payload = "#{@user.id}|#{realm_id}|#{@now.to_i}|#{left_id}|#{right_id}"
      digest  = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      digest[0, 64]
    end

    def store_seed(seed, realm_id, left_id, right_id)
      value = "#{@user.id}|#{realm_id}|#{left_id}|#{right_id}|#{@now.to_i}"
      with_redis do |r|
        r.setex("#{REDIS_PREFIX}#{seed}", SEED_TTL.to_i, value)
      end
    end

    def with_redis(&block)
      block.call(Kredis.redis(config: :shared))
    rescue StandardError => e
      Rails.logger.warn "[Codex::PairSelectorService] redis unavailable: #{e.class}"
      nil
    end

    def secret
      ::Rails.application.secret_key_base.to_s
    end

    def invalid(message)
      Result.new(success: false, left: nil, right: nil, pair_seed: nil,
                 realm: nil, error: message)
    end
  end
end
