# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Node — central lore entity. Hosts all 79 seed records (ecosystems,
# unique trees, protocols, mythos) as well as DAO/community submissions.
#
# Identity:
#   * `slug`       — URL-safe, used in routes (Show pages, citations)
#   * `codex_uid`  — human-quotable id (CDX-ECO-0001, CDX-TRE-0007, ...) used
#                    in audit logs, blockchain anchors and PR descriptions
#
# Geo: lat/lng from concern GeoLocatable; `geo_point` is the PostGIS
# GEOGRAPHY(POINT, 4326) projection kept in sync via callbacks. Mythos /
# protocol nodes leave both NULL — geo is optional.
#
# Lore (`*_md`): markdown rendered through Codex::MarkdownRenderer with a
# tight safelist of tags. Length capped server-side to bound payload size.
#
# Lifecycle: integer-backed enum (matches existing pattern e.g. Tree#status).
# Maps to Views::Shared::UI::StatusBadge styles via the lifecycle keys.
#
# See docs/04_05_Codex_Lore_Module.md §2.2.
module Codex
  class Node < ApplicationRecord
    include GeoLocatable

    self.table_name = "codex_nodes"

    # ----- Length / format limits ---------------------------------------
    SLUG_FORMAT      = /\A[a-z0-9][a-z0-9-]*\z/
    CODEX_UID_FORMAT = /\A(CDX-(?:ECO|TRE|PRT|MYT)-\d{4,6})\z/
    CONTEXT_MAX      = 8 * 1024
    CYBER_MAX        = 8 * 1024
    LORE_MAX         = 16 * 1024

    # ----- Enums ---------------------------------------------------------
    # Integer-backed (matches existing models). prefix avoids collisions
    # with other enums on adjacent models.
    enum :lifecycle_status,
         { mythical: 0, extinct: 1, endangered: 2, thriving: 3,
           destroyed: 4, unknown: 5 },
         prefix: :lifecycle_status, default: :unknown

    enum :seed_origin,
         { seed: 0, dao_proposal: 1, community_submission: 2 },
         prefix: :seed_origin, default: :seed

    # ----- Associations --------------------------------------------------
    belongs_to :realm,
               class_name: "Codex::Realm",
               foreign_key: :codex_realm_id,
               inverse_of: :nodes,
               counter_cache: false

    has_many :citations,
             class_name: "Codex::Citation",
             foreign_key: :codex_node_id,
             inverse_of: :node,
             dependent: :destroy

    has_many :attunements,
             class_name: "Codex::Attunement",
             foreign_key: :codex_node_id,
             inverse_of: :node,
             dependent: :destroy

    # Polymorphic comments: filter by commentable_type so a stray Comment
    # written against a different Codex resource never leaks into a
    # Node's thread.
    has_many :comments,
             -> { where(commentable_type: "Codex::Node") },
             class_name: "Codex::Comment",
             foreign_key: :commentable_id,
             inverse_of: :commentable,
             dependent: :destroy

    has_one_attached  :cover_image
    has_many_attached :gallery

    # ----- Validations ---------------------------------------------------
    validates :slug, presence: true, uniqueness: true,
                     format: { with: SLUG_FORMAT },
                     length: { maximum: 80 }
    validates :codex_uid, presence: true, uniqueness: true,
                          format: { with: CODEX_UID_FORMAT }
    validates :title_uk, :title_en, presence: true, length: { maximum: 200 }
    validates :subtitle_uk, :subtitle_en, length: { maximum: 200 }, allow_nil: true
    validates :archetype_key, presence: true,
                              inclusion: { in: ->(_n) { Codex::ARCHETYPES } }
    validates :context_md,       length: { maximum: CONTEXT_MAX }, allow_nil: true
    validates :cyber_meaning_md, length: { maximum: CYBER_MAX }, allow_nil: true
    validates :lore_md,          length: { maximum: LORE_MAX }, allow_nil: true
    validates :attunement_count, :comments_count, :view_count,
              :discovery_count, :citation_count, :match_count,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :attunement_elo,
              numericality: { only_integer: true, in: 0..4000 }
    validate  :external_refs_must_be_array_of_links

    # ----- Callbacks -----------------------------------------------------
    before_validation :normalize_slug
    before_save       :sync_geo_point

    # ----- Scopes --------------------------------------------------------
    scope :published, -> { where.not(published_at: nil) }
    scope :for_realm, ->(realm_or_slug) {
      case realm_or_slug
      when nil          then all
      when Codex::Realm then where(codex_realm_id: realm_or_slug.id)
      when String, Symbol
        slug = realm_or_slug.to_s
        slug.blank? ? all : joins(:realm).where(codex_realms: { slug: slug })
      else
        none
      end
    }
    # Trigram-fuzzy search across both bilingual title columns. GIN-pg_trgm
    # indexes accelerate the LIKE. lower(col COLLATE "und-x-icu") normalises
    # non-ASCII casing (Cyrillic, etc.) — necessary because the DB cluster was
    # initialised with the C locale, which skips Unicode case folding.
    scope :search_title, ->(query) {
      next all if query.blank?

      pattern = "%#{sanitize_sql_like(query.to_s.strip.downcase)}%"
      where(
        'lower(title_uk COLLATE "und-x-icu") LIKE ? OR lower(title_en COLLATE "und-x-icu") LIKE ?',
        pattern, pattern
      )
    }
    scope :by_archetype, ->(key) { where(archetype_key: key) if key.present? }
    scope :by_lifecycle, ->(status) {
      where(lifecycle_status: lifecycle_statuses[status]) if status.present? && lifecycle_statuses.key?(status.to_s)
    }
    scope :ordered_by_elo, -> { order(attunement_elo: :desc, id: :asc) }

    # ----- Helpers -------------------------------------------------------
    def title(locale = I18n.locale)
      locale.to_s.start_with?("uk") ? title_uk : title_en
    end

    def subtitle(locale = I18n.locale)
      locale.to_s.start_with?("uk") ? subtitle_uk : subtitle_en
    end

    # Used by url helpers. Slug is unique, so route by slug (per plan §6).
    def to_param
      slug
    end

    private

    def normalize_slug
      self.slug = slug.to_s.strip.downcase.tr("_", "-") if slug.present?
    end

    # Keep PostGIS geo_point in sync with concern's lat/lng. Skipped if
    # both unset — `mythos`/`protocol` rows legitimately have no geometry.
    def sync_geo_point
      return unless will_save_change_to_latitude? || will_save_change_to_longitude?

      if latitude.present? && longitude.present?
        self.geo_point = "SRID=4326;POINT(#{longitude.to_f} #{latitude.to_f})"
      else
        self.geo_point = nil
      end
    end

    def external_refs_must_be_array_of_links
      return if external_refs.blank?

      unless external_refs.is_a?(Array) &&
             external_refs.all? { |r| r.is_a?(Hash) && r["url"].is_a?(String) }
        errors.add(:external_refs, "must be an array of {label, url} objects")
      end
    end
  end
end
