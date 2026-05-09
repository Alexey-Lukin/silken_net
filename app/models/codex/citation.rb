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

    # Polymorphic class-name resolver. Works equally well for:
    #   * ActiveRecord models (uses `base_class` so STI subclasses fold)
    #   * Plain Ruby objects / OpenStruct test doubles (falls back to `class.name`)
    #   * Anonymous classes from `Class.new` (skips them — `nil` returned so
    #     callers short-circuit to "no citations").
    # Returning `nil` instead of raising lets callers like `render_codex_citations`
    # gracefully no-op when the target is a non-AR mock.
    def self.polymorphic_type_for(target)
      klass = target.class
      if klass.respond_to?(:base_class) && klass.base_class.name.present?
        return klass.base_class.name
      end
      # Explicit nil contract — anonymous classes (`Class.new { ... }.new`)
      # have `klass.name == nil`. Returning `nil` lets `for_target` and
      # `bulk_for` short-circuit to `none` / `{}` instead of building a
      # `WHERE citable_type = NULL` query.
      klass.name.presence
    end

    # `for_target(target)` — all citations on a single Tree / Cluster / etc.
    # See `polymorphic_type_for` for STI / mock semantics.
    scope :for_target, ->(target) {
      type = polymorphic_type_for(target)
      type ? where(citable_type: type, citable_id: target.id) : none
    }

    # `for_targets(scope)` — bulk lookup for collection views (e.g. an
    # alerts table rendering N rows). Avoids N+1 by fetching all citations
    # for the given target collection in one query, returning a Hash keyed
    # by `[citable_type, citable_id]` so callers can index in O(1).
    #
    # Eager-loads `node: :realm` because `Codex::Citations::Pill` derives
    # the realm-tinted accent border from `node.realm.accent_token` — fetching
    # citations alone would re-introduce a per-pill query for each pill rendered.
    def self.bulk_for(targets)
      return {} if targets.blank?

      grouped = Hash.new { |h, k| h[k] = [] }
      targets_by_type = targets.group_by { |t| polymorphic_type_for(t) }
      targets_by_type.each do |type, list|
        next if type.nil?
        ids = list.map(&:id)
        where(citable_type: type, citable_id: ids)
          .includes(node: :realm)
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
