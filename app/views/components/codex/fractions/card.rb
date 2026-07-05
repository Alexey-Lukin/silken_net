# frozen_string_literal: true

# Codex::Fractions::Card — read-only summary of the caller's current
# fraction. Shown in `GET /codex/fractions/me` (HTML) and embedded as a
# Turbo Frame on the user profile.
module Codex
  module Fractions
    class Card < ApplicationComponent
      def initialize(fraction:, current_user: nil)
        @fraction     = fraction
        @current_user = current_user
      end

      def view_template
        div(
          id: "codex_fraction_card",
          class: tokens(
            "border border-gaia-border bg-gaia-surface p-5 space-y-4",
            "text-gaia-text"
          )
        ) do
          if @fraction
            render_filled
          else
            render_empty
          end
        end
      end

      private

      def render_filled
        node = @fraction.node
        h3(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-muted") { t("codex.fractions.my_heading") }
        div(class: "flex items-start justify-between gap-4") do
          div(class: "space-y-1") do
            # `node&.` is model-validation-dead, not real: `Fraction#node` is
            # a required belongs_to and `codex_node_id` carries an
            # `ON DELETE RESTRICT` FK — a Node can never be deleted while a
            # Fraction points at it, so `.node` is always present here.
            p(class: "text-tiny text-gaia-text") { node&.title_en || @fraction.archetype_key }
            p(class: "text-mini text-gaia-text-muted font-mono uppercase tracking-widest") do
              @fraction.archetype_key
            end
          end
          render Codex::Fractions::Cooldown.new(fraction: @fraction)
        end
        div(class: "flex items-center gap-3 text-mini text-gaia-text-muted") do
          span { t("codex.fractions.since", date: @fraction.chosen_at.to_date.iso8601) }
          span { "·" }
          span { t("codex.fractions.updated", date: @fraction.last_changed_at.to_date.iso8601) }
        end
        a(
          href: api_v1_codex_fraction_picker_path,
          class: tokens(
            "inline-flex items-center gap-2 px-3 py-1 border border-gaia-border",
            "text-tiny uppercase tracking-[0.3em] text-gaia-text",
            "hover:bg-gaia-primary hover:text-gaia-primary-text",
            "focus-visible:ring-2 focus-visible:ring-gaia-primary"
          )
        ) { t("codex.fractions.change") }
      end

      def render_empty
        h3(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-muted") { t("codex.fractions.my_heading") }
        p(class: "text-tiny text-gaia-text") { t("codex.fractions.empty") }
        a(
          href: api_v1_codex_fraction_picker_path,
          class: tokens(
            "inline-flex items-center gap-2 px-3 py-1 border border-gaia-border bg-gaia-surface-sunken",
            "text-tiny uppercase tracking-[0.3em] text-gaia-text",
            "hover:bg-gaia-primary hover:text-gaia-primary-text",
            "focus-visible:ring-2 focus-visible:ring-gaia-primary"
          )
        ) { t("codex.fractions.choose") }
      end
    end
  end
end
