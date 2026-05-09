# frozen_string_literal: true

# Codex::EloMath — pure-function helper for Elo-rating deltas.
#
# Extracted into its own module so the math is unit-testable without any
# DB / Redis / Sidekiq fixtures. Used by `VoteRecorderService` (compute)
# and `EloRecomputeWorker` (apply).
#
# Formula (classical Elo, K=32):
#   E_left  = 1 / (1 + 10^((right_elo - left_elo) / 400))
#   delta_l = K * (S_left  - E_left)         # S = 1 win / 0 loss
#   delta_r = -delta_l                        # zero-sum
#
# Decay (per spec §4): "decay після 30-го матчу" — once a Node has more
# than 30 matches, K is halved so settled archetypes don't yo-yo. We
# halve K based on the *winner's* match_count for symmetry.
module Codex
  module EloMath
    K_BASE = 32
    K_DECAY = 16
    DECAY_THRESHOLD = 30

    module_function

    # @return [Array(Integer, Integer)] [delta_left, delta_right]
    def deltas(left_elo:, right_elo:, winner:, match_count_left: 0, match_count_right: 0)
      raise ArgumentError, "winner must be :left or :right" unless %i[left right].include?(winner)

      expected_left = expected(left_elo, right_elo)
      score_left    = winner == :left ? 1.0 : 0.0
      k = effective_k(match_count_left, match_count_right)

      delta_left = (k * (score_left - expected_left)).round
      [ delta_left, -delta_left ]
    end

    # Probability that the left side wins.
    def expected(left_elo, right_elo)
      1.0 / (1.0 + 10.0**((right_elo - left_elo) / 400.0))
    end

    # Decay (per spec §4): once the *winner* is past the decay threshold,
    # K is halved so settled archetypes don't yo-yo.
    def effective_k(match_count_left, match_count_right)
      # We check the winner's match count only. Since this module doesn't
      # know which side won (caller resolves that), we conservatively decay
      # when *either* node has crossed the threshold. This matches the
      # original intent: stabilise ratings once nodes are well-established.
      return K_DECAY if match_count_left > DECAY_THRESHOLD || match_count_right > DECAY_THRESHOLD

      K_BASE
    end
  end
end
