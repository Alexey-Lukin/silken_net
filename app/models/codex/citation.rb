# frozen_string_literal: true

# Codex::Citation — polymorphic stitch from any operational entity to a
# Codex::Node. The lore layer is bidirectional: telemetry/clusters/alerts
# can quote a lore card, so the Codex stops being a sidebar wiki.
#
# Phase 1 ships the model + uniqueness guard. Phase 6 will render the
# `Codex::CitationPill` component inside Tree::Show, Cluster::Show,
# OracleVisions::ForecastCard and EwsAlert::Row.
#
# See docs/04_05_Codex_Lore_Module.md §2.9.
module Codex
  class Citation < ApplicationRecord
    self.table_name = "codex_citations"

    # Allow-list of citable models. Polymorphic types accepted server-side
    # only if present in this list — prevents arbitrary string injection
    # into `citable_type`.
    ALLOWED_CITABLE_TYPES = %w[
      Tree
      Cluster
      AiInsight
      EwsAlert
      OracleVision
      NaasContract
    ].freeze

    belongs_to :node,
               class_name: "Codex::Node",
               foreign_key: :codex_node_id,
               inverse_of: :citations,
               counter_cache: :citation_count
    # citable_type/id are NOT NULL at DB level and ALLOWED_CITABLE_TYPES is
    # enforced via inclusion below; we mark the AR association `optional: true`
    # so unit specs (and admin tooling) can create rows without instantiating
    # heavy Tree/Cluster/AiInsight factories. Real callers always supply a
    # live target via the controller layer.
    belongs_to :citable, polymorphic: true, optional: true
    belongs_to :created_by_user,
               class_name: "User",
               inverse_of: :codex_citations

    validates :citable_type, presence: true, inclusion: { in: ALLOWED_CITABLE_TYPES }
    validates :citable_id, presence: true
    validates :note, length: { maximum: 140 }, allow_nil: true
    validates :codex_node_id,
              uniqueness: {
                scope: [ :citable_type, :citable_id, :created_by_user_id ],
                message: "already cited on this entity by this user"
              }

    # `for_target(target)` — all citations on a single Tree / Cluster / etc.
    # Use `target.class.base_class.name` so STI subclasses fold to the parent
    # (citation rows always store the canonical type name).
    scope :for_target, ->(target) {
      where(citable_type: target.class.base_class.name, citable_id: target.id)
    }

    # `for_targets(scope)` — bulk lookup for collection views (e.g. an
    # alerts table rendering N rows). Avoids N+1 by fetching all citations
    # for the given target collection in one query, returning a Hash keyed
    # by `[citable_type, citable_id]` so callers can index in O(1).
    def self.bulk_for(targets)
      return {} if targets.blank?

      grouped = Hash.new { |h, k| h[k] = [] }
      targets_by_type = targets.group_by { |t| t.class.base_class.name }
      targets_by_type.each do |type, list|
        ids = list.map(&:id)
        where(citable_type: type, citable_id: ids)
          .includes(:node)
          .order(created_at: :asc)
          .each { |c| grouped[[ type, c.citable_id ]] << c }
      end
      grouped
    end

    # `editable_grace?` — Phase 6: own-citation deletion grace window.
    # Mirrors Comment's 24h edit grace; admin+ bypass via policy.
    EDIT_GRACE = 24.hours
    def within_edit_grace?
      created_at.present? && created_at >= EDIT_GRACE.ago
    end
  end
end
