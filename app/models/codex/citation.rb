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
    belongs_to :citable, polymorphic: true
    belongs_to :created_by_user, class_name: "User"

    validates :citable_type, inclusion: { in: ALLOWED_CITABLE_TYPES }
    validates :note, length: { maximum: 140 }, allow_nil: true
    validates :codex_node_id,
              uniqueness: {
                scope: [ :citable_type, :citable_id, :created_by_user_id ],
                message: "already cited on this entity by this user"
              }

    scope :for_target, ->(target) {
      where(citable_type: target.class.base_class.name, citable_id: target.id)
    }
  end
end
