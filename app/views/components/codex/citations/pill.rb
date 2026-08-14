# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Citations::Pill — single inline citation chip.
#
# Renders a compact pill linking back to the cited Codex Node:
#
#   ◆ Mafusail · relict_oracle
#
# Visual design (Phase 7 polish):
#   * Realm-tinted left edge — a 2px accent border whose colour comes from
#     the Node's realm `accent_token` column (DAO-tunable per ADR-CDX-2).
#     This turns the strip from a flat row of chips into a glanceable
#     Realm distribution — a forester can see "this tree leans Mythos"
#     without reading any names.
#   * Realm glyph prefix from `Realm#display_glyph` (data + lookup table in
#     the model — see `Codex::Realm::DISPLAY_GLYPHS`) so adding a 5th realm
#     needs only an entry in that hash, not a hunt through view code.
#   * Subtle hover lift (translate-y) + border glow — confirms interactivity
#     without resorting to a colour change that would clash with the realm tint.
#
# Used inside `Codex::Citations::Strip` and (for one-off renders) standalone.
# All chrome colours come through Tailwind tokens that already exist in the
# project palette — no new tokens added.
module Codex
  module Citations
    class Pill < ApplicationComponent
      # [UI.10] Мапи акценту переїхали в `Codex::Realm` — до `DISPLAY_GLYPHS`,
      # свого природного сусіда: пʼятий реалм від DAO має додаватись одним
      # записом у моделі. Тут лишається лише споживання; копії немає навмисно —
      # `Codex::NodeCard` читає ТОЙ САМИЙ дім.
      DEFAULT_GLYPH = ::Codex::Realm::DEFAULT_DISPLAY_GLYPH

      # @param citation [Codex::Citation] eager-loaded with `:node` (and
      #   ideally with `node: :realm` to avoid a per-pill realm query).
      def initialize(citation:)
        @citation = citation
      end

      def view_template
        node = @citation.node
        # Defensive — Node could be in the process of being soft-archived.
        return if node.nil?

        a(
          # Хелпер, не літерал [ARCH.77]: рукописний шлях не переїде разом із
          # роутером і не почервоніє — а парний пін у спеці цементував би саме
          # його, тобто пара «літерал у коді + літерал у спеці» лишалась би
          # самосинхронно зеленою на мертвій адресі.
          href:       codex_node_path(node.slug),
          id:         dom_id,
          class:      pill_classes(node),
          aria_label: aria_label(node),
          title:      full_title(node),
          data:       { codex_citation_id: @citation.id, realm: realm_slug(node) }
        ) do
          span(class: "#{accent_text_class(node)} text-mini leading-none") { glyph(node) }
          span(class: "font-medium text-gaia-text") { node.title_en.presence || node.slug }
          if node.archetype_key.present?
            span(class: "ml-0.5 text-gaia-text-muted text-micro uppercase tracking-tighter") do
              "· #{node.archetype_key}"
            end
          end
        end
      end

      private

      def dom_id
        "codex_citation_#{@citation.id}"
      end

      # Pill chrome. The `border-l-2` + realm-tinted accent class gives the
      # left edge a vertical wick of colour; the rest of the border stays
      # neutral so the row reads as a coherent strip, not a rainbow.
      def pill_classes(node)
        tokens(
          "inline-flex items-center gap-1 px-2 py-0.5",
          "text-mini bg-gaia-surface-sunken",
          "border border-gaia-border border-l-2 rounded-sm",
          accent_border_class(node),
          "hover:-translate-y-px hover:border-gaia-primary",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary",
          "transition-all duration-150 ease-out"
        )
      end

      # Резолв акценту живе на моделі (`Codex::Realm#accent_*_class`) — тут лише
      # nil-плече на випадок реалму, знятого з-під вузла.
      def accent_border_class(node)
        node.realm&.accent_border_class || ::Codex::Realm::DEFAULT_ACCENT_BORDER_CLASS
      end

      def accent_text_class(node)
        node.realm&.accent_text_class || ::Codex::Realm::DEFAULT_ACCENT_TEXT_CLASS
      end

      def glyph(node)
        node.realm&.display_glyph || DEFAULT_GLYPH
      end

      def realm_slug(node)
        node.realm&.slug
      end

      def aria_label(node)
        realm_name = node.realm&.name_en.presence || t("codex.citations.unknown_realm")
        base = t("codex.citations.aria_with_realm", title: node.title_en, realm: realm_name)
        return base if @citation.note.blank?

        t("codex.citations.aria_with_note", base: base, note: @citation.note)
      end

      # Shown on hover. Note can be up to 140 chars; this surfaces forester
      # context without requiring a click-through.
      def full_title(node)
        base = node.title_en.to_s
        return base if @citation.note.blank?

        t("codex.citations.title_with_note", base: base, note: @citation.note)
      end
    end
  end
end
