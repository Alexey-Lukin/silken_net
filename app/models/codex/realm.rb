# SPDX-License-Identifier: AGPL-3.0-or-later
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

    # [UI.10] Дім реалм-акценту — тут, поряд із `DISPLAY_GLYPHS` і з того самого
    # обґрунтування: пʼятий реалм від DAO має додаватись ОДНИМ записом, а не
    # полюванням по вʼю. Доти мапи жили приватно в `Codex::Citations::Pill`, а
    # `Codex::NodeCard` акцент лише ОБІЦЯВ докстрінгом — тож Atlas-грід, єдина
    # поверхня, де всі чотири реалми видно одночасно, не розрізняв їх ніяк.
    #
    # Класи статичні навмисно: Tailwind JIT бачить лише те, що стоїть у джерелі
    # текстом, тож `border-l-#{token}` не скомпілювався б узагалі.
    ACCENT_BORDER_CLASSES = {
      "status-success" => "border-l-status-success",
      "gaia-primary"   => "border-l-status-active",
      "status-info"    => "border-l-status-info",
      "status-warning" => "border-l-status-warning"
    }.freeze
    DEFAULT_ACCENT_BORDER_CLASS = "border-l-gaia-border"

    # 🔴 Тут `-text`-варіант, а не базовий токен, і це ВИМІРЯНО, не стильово:
    # `status-*` без суфікса — це ФОН бейджа (`#d1fae5`, `#fef3c7`), і попередня
    # мапа клала ці значення на ТЕКСТ. Вимір (`lib/silken_net/contrast.rb`) на
    # реальній поверхні пігулки: 1.01–1.11:1 у світлій темі та 1.73–2.59:1 у
    # темній — тобто гліф був практично невидимий в ОБОХ. Парні `-text`-токени
    # дають 6.4–17.5:1. Третій екземпляр класу «токен існує ≠ токен придатний
    # для РОЛІ» (перші два — `--status-danger` на крапці severity й фантомний
    # `--gaia-primary-text`).
    #
    # ⚠️ `gaia-primary` мапиться на бірюзову родину СВІДОМО: у брендового
    # смарагда AA-безпечної текстової пари не існує — його `-text` партнер
    # (`#0f172a`) призначений стояти НА смарагдовій кнопці, а не поруч із нею.
    # Реалми лишаються чотирма розрізнюваними відтінками, і колір тут не єдиний
    # носій різниці (пігулка друкує ще й назву реалму та гліф — WCAG 1.4.1).
    ACCENT_TEXT_CLASSES = {
      "status-success" => "text-status-success-text",
      "gaia-primary"   => "text-status-active-text",
      "status-info"    => "text-status-info-text",
      "status-warning" => "text-status-warning-text"
    }.freeze
    DEFAULT_ACCENT_TEXT_CLASS = "text-gaia-text-muted"

    def accent_border_class
      ACCENT_BORDER_CLASSES.fetch(accent_token.to_s, DEFAULT_ACCENT_BORDER_CLASS)
    end

    def accent_text_class
      ACCENT_TEXT_CLASSES.fetch(accent_token.to_s, DEFAULT_ACCENT_TEXT_CLASS)
    end
  end
end
