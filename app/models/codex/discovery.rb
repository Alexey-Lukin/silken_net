# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Discovery — fact: "User U unlocked Node N via trigger T at time t".
#
# Storage shape: regular (non-partitioned) — Discoveries are sparse vs
# `codex_matches` (most users will collect dozens, not millions). The
# UNIQUE `(user_id, codex_node_id)` index is the primary correctness
# guarantee: every card unlocks at most once per user.
#
# `trigger_ref` is a *loose* polymorphic — no FK, no `dependent`. If a
# `TelemetryLog` partition is dropped or a `Codex::Match` is archived,
# the Discovery survives as a historical fact. UI gracefully handles
# `trigger_ref` being nil at render-time.
module Codex
  class Discovery < ApplicationRecord
    self.table_name = "codex_discoveries"

    TRIGGER_TYPES = {
      telemetry_observation: 0,
      manual_unlock:         1,
      match_milestone:       2,
      fraction_choice:       3,
      attunement_streak:     4,
      oracle_seasonal:       5
    }.freeze

    enum :trigger_type, TRIGGER_TYPES, prefix: :triggered_by

    belongs_to :user
    belongs_to :node,
               class_name: "Codex::Node",
               foreign_key: :codex_node_id,
               counter_cache: :discovery_count
    belongs_to :trigger_ref, polymorphic: true, optional: true

    validates :unlocked_at, presence: true
    validates :user_id,
              uniqueness: {
                scope: :codex_node_id,
                message: "has already unlocked this node"
              }

    scope :for_user, ->(user) { where(user_id: user.id) }
    scope :recent,   -> { order(unlocked_at: :desc) }

    before_validation :default_unlocked_at, on: :create

    private

    def default_unlocked_at
      self.unlocked_at ||= Time.current
    end
  end
end
