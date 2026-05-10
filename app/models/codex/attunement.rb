# frozen_string_literal: true

# Codex::Attunement — semantic "I tune to this archetype" relation.
#
# Distinct from a "like" (one user can attune to 1..N nodes simultaneously,
# and the choice is publicly visible on their profile). Distinct from a
# Fraction (Phase 3, exactly one) and from a Match vote (Phase 4, transient).
#
# Counter cache feeds `codex_nodes.attunement_count`; the UNIQUE
# (user_id, codex_node_id) DB constraint guarantees idempotent toggling
# under concurrent requests.
module Codex
  class Attunement < ApplicationRecord
    self.table_name = "codex_attunements"

    INTENSITY_RANGE = (1..5).freeze
    QUOTE_MAX       = 280

    belongs_to :user
    belongs_to :node,
               class_name: "Codex::Node",
               foreign_key: :codex_node_id,
               inverse_of: :attunements,
               counter_cache: :attunement_count

    validates :intensity,
              numericality: { only_integer: true,
                              greater_than_or_equal_to: INTENSITY_RANGE.min,
                              less_than_or_equal_to:    INTENSITY_RANGE.max }
    validates :quote, length: { maximum: QUOTE_MAX }, allow_nil: true
    validates :user_id, uniqueness: { scope: :codex_node_id }

    before_validation :default_started_at, on: :create

    scope :for_node, ->(node) { where(codex_node_id: node.id) }
    scope :for_user, ->(user) { where(user_id: user.id) }
    scope :ordered,  -> { order(created_at: :desc) }

    private

    def default_started_at
      self.started_at ||= Time.current
    end
  end
end
