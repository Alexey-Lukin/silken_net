# frozen_string_literal: true

# Codex::Fraction — the user's chosen archetype identity.
#
# Conceptually: every authenticated SilkenNet citizen aligns with **one**
# Codex node (their "house" / "fraction"). UNIQUE (user_id) on the DB
# enforces the singleton; mutations go through `Codex::FractionChangeService`
# which holds the 7-day cooldown gate and the audit-trail enqueue.
#
# Denormalisation: `archetype_key` is copied from the chosen Node so that
# "fraction-by-archetype" filters (e.g. "show all `cold_wallet` users") are
# index-only without a join. The service keeps it in sync on every change.
module Codex
  class Fraction < ApplicationRecord
    self.table_name = "codex_fractions"

    # 7 calendar days. Used by `FractionChangeService` and `Cooldown` view
    # component. Public so specs and policies can reference the same value.
    COOLDOWN = 7.days

    belongs_to :user
    belongs_to :node,
               class_name: "Codex::Node",
               foreign_key: :codex_node_id,
               counter_cache: false

    validates :archetype_key, presence: true, length: { maximum: 64 }
    validates :house_color_token, length: { maximum: 64 }, allow_nil: true
    validates :user_id, uniqueness: true
    validates :chosen_at, :last_changed_at, presence: true

    # Reject lifecycle states that aren't pickable. `mythical` is allowed
    # (myth is a valid identity); `destroyed` / `extinct` are not — picking
    # them would imply tribute to lore that is gone.
    validate :node_lifecycle_pickable

    scope :ordered, -> { order(last_changed_at: :desc) }
    scope :by_archetype, ->(key) { where(archetype_key: key) if key.present? }

    # @return [Boolean] true while the cooldown window is still open
    def cooldown_active?(reference_time = Time.current)
      reference_time < cooldown_until
    end

    # @return [Time] earliest moment another change is permitted
    def cooldown_until
      last_changed_at + COOLDOWN
    end

    # @return [Integer] whole seconds until cooldown elapses (0 when open)
    def seconds_until_unlocked(reference_time = Time.current)
      diff = cooldown_until - reference_time
      diff.positive? ? diff.to_i : 0
    end

    private

    def node_lifecycle_pickable
      return unless node

      blocked = %w[destroyed extinct]
      return unless blocked.include?(node.lifecycle_status)

      errors.add(:codex_node_id, "cannot pick a #{node.lifecycle_status} node")
    end
  end
end
