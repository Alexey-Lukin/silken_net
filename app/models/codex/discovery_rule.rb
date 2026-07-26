# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::DiscoveryRule — DAO-editable unlock condition.
#
# Hard-coding "10 hours of observation → unlock roots-darwin-brain" inside
# Ruby would mean every new lore card requires a deploy. Instead we keep
# the condition as a row: `condition_type` (enum, dispatch key) +
# `threshold_value` (integer) + `params` (JSONB for region regex,
# archetype filter, etc.).
#
# Caching: `Codex::DiscoveryEngine` reads via
# `Rails.cache.fetch("codex.discovery_rules.v1", expires_in: 1.hour)`.
# We bust the cache on `after_commit` (create / update / destroy) so a
# DAO admin's change is visible within ~1 sec across all Sidekiq workers.
#
# Validations enforce sanity: threshold ≥ 1, params must be a Hash.
module Codex
  class DiscoveryRule < ApplicationRecord
    self.table_name = "codex_discovery_rules"

    CACHE_KEY = "codex.discovery_rules.v1"

    CONDITION_TYPES = {
      tree_observation_minutes: 0,
      acoustic_class_count:     1,
      cluster_visited:          2,
      match_count:              3,
      attunement_streak_days:   4,
      firmware_version_seen:    5,
      oracle_dispatched:        6
    }.freeze

    enum :condition_type, CONDITION_TYPES, prefix: :condition

    belongs_to :node,
               class_name: "Codex::Node",
               foreign_key: :codex_node_id
    belongs_to :created_by_user, class_name: "User"

    validates :name, presence: true, length: { maximum: 120 }
    validates :threshold_value,
              presence: true,
              numericality: { only_integer: true, greater_than_or_equal_to: 1 }
    validate  :params_must_be_hash

    scope :active_only, -> { where(active: true) }
    scope :for_condition, ->(type) { where(condition_type: type) }

    after_commit :bust_cache

    # Eager-loaded hash of all *active* rules grouped by condition_type.
    # Returned shape: `{ "match_count" => [<Rule>, <Rule>], "..." => [...] }`.
    # Lazily populated; auto-busted on any rule mutation.
    def self.cached_active_by_condition
      Rails.cache.fetch(CACHE_KEY, expires_in: 1.hour) do
        active_only
          .includes(:node)
          .group_by(&:condition_type)
          .freeze
      end
    end

    def self.bust_cache!
      Rails.cache.delete(CACHE_KEY)
    end

    private

    def params_must_be_hash
      return if params.is_a?(Hash)

      errors.add(:params, "must be a JSON object")
    end

    def bust_cache
      self.class.bust_cache!
    end
  end
end
