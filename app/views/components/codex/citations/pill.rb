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
      # Static class table — Tailwind v4 JIT only picks up classes it sees as
      # static text in source files. Dynamic interpolation `border-l-#{token}`
      # would NOT be compiled, leaving the pill border colour-less in prod.
      # We map the 4 seeded `Realm.accent_token` values explicitly; new realms
      # added by DAO proposal must extend this hash AND add their classes to
      # `@source inline()` in `app/assets/tailwind/application.css` (or be
      # whitelisted by being mentioned anywhere else in the source tree).
      ACCENT_BORDER_CLASSES = {
        "status-success" => "border-l-status-success",
        "gaia-primary"   => "border-l-gaia-primary",
        "status-info"    => "border-l-status-info",
        "status-warning" => "border-l-status-warning"
      }.freeze
      DEFAULT_ACCENT_BORDER_CLASS = "border-l-gaia-border"

      ACCENT_TEXT_CLASSES = {
        "status-success" => "text-status-success",
        "gaia-primary"   => "text-gaia-primary",
        "status-info"    => "text-status-info",
        "status-warning" => "text-status-warning"
      }.freeze
      DEFAULT_ACCENT_TEXT_CLASS = "text-gaia-text-muted"

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
          href:       "/api/v1/codex/nodes/#{node.slug}",
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

      # `Realm#accent_token` is a Tailwind class fragment seeded per realm
      # (e.g. `"gaia-primary"`, `"status-success"`). We map it through the
      # static ACCENT_*_CLASSES hashes because Tailwind JIT can't see
      # dynamic interpolation.
      def accent_token(node)
        node.realm&.accent_token.to_s
      end

      def accent_border_class(node)
        ACCENT_BORDER_CLASSES.fetch(accent_token(node), DEFAULT_ACCENT_BORDER_CLASS)
      end

      def accent_text_class(node)
        ACCENT_TEXT_CLASSES.fetch(accent_token(node), DEFAULT_ACCENT_TEXT_CLASS)
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
