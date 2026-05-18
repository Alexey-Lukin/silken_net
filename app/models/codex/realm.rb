# frozen_string_literal: true

# Codex::Realm — top-level Codex taxonomy.
#
# Modeled as a table (~4 rows) instead of an enum so the DAO can introduce
# a 5th realm (e.g. `space`, `mycorrhiza`) without a migration. Phase 1
# seeds: ecosystem, unique_tree, protocol, mythos.
#
# Bilingual SSOT (UA/EN) — no i18n gem.
#
# See docs/04_05_Codex_Lore_Module.md §2.1.
module Codex
  class Realm < ApplicationRecord
    self.table_name = "codex_realms"

    SLUG_FORMAT = /\A[a-z][a-z0-9_]*\z/

    has_many :nodes,
             class_name: "Codex::Node",
             foreign_key: :codex_realm_id,
             inverse_of: :realm,
             dependent: :restrict_with_error

    validates :slug, presence: true, uniqueness: true,
                     format: { with: SLUG_FORMAT }
    validates :name_uk, :name_en, :glyph, :accent_token, presence: true
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :active,  -> { where(is_active: true) }
    scope :ordered, -> { order(:position, :id) }

    # Bilingual switcher — uniform with `Codex::Node#title(locale)` /
    # `Codex::Node#subtitle(locale)`. SSOT: `docs/04_01` §7b.
    #
    # `codex_realms` має лише `name_uk` / `name_en` стовпці (без plain
    # `name`), тож метод `#name(locale)` тут безпечно перекриває default
    # AR getter — він би все одно повертав nil.
    def name(locale = I18n.locale)
      locale.to_s.start_with?("uk") ? name_uk : name_en
    end

    # Lookup table: `glyph` column stores a stable English keyword
    # (`forest`, `tree`, `protocol`, `mythos`) — `display_glyph` translates
    # it to a unicode character at the rendering boundary. SSOT used by
    # `Codex::NodeCard` and `Codex::Citations::Pill` so adding a 5th realm
    # only needs one new entry here, not a hunt through view code.
    DISPLAY_GLYPHS = {
      "forest"   => "🌲",
      "tree"     => "🌳",
      "protocol" => "⚛",
      "mythos"   => "✶"
    }.freeze
    DEFAULT_DISPLAY_GLYPH = "○"

    def display_glyph
      DISPLAY_GLYPHS.fetch(glyph.to_s, DEFAULT_DISPLAY_GLYPH)
    end
  end
end
