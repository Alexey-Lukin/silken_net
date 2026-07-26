# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Citations::Strip — wrap-flex container of citation pills attached
# to a single operational target (Tree / Cluster / EwsAlert / OracleVision).
#
# Subscribes to the `codex_citations:<Type>:<ID>` ActionCable stream so a
# pill posted by a forester appears live for any open viewer. We mark the
# container `aria-live="polite"` so a screen reader announces a fresh
# citation instead of silently rerendering it.
#
# Render contract:
#   render Codex::Citations::Strip.new(target: @tree, citations: citations)
#
# `citations` is the eager-loaded slice — pass `Codex::Citation.for_target(target).includes(:node)`
# or, for tables, use `Codex::Citation.bulk_for(targets)[[type, id]]` to avoid N+1.
#
# Visual design (Phase 7 polish):
#   * Lore-grade empty state — instead of "No lore citations yet." (which
#     reads as a missing feature), the strip shows a faint dotted glyph row
#     with the in-voice prompt "Untold." This matches the rest of the Codex
#     palette (kiberпанк-зелений, низькоконтрастний) and signals "available
#     surface" rather than "broken state".
#   * Stable DOM id resolution via `Codex::Citation.polymorphic_type_for` so
#     the strip never crashes on POROs / OpenStruct test doubles (matches
#     the same fallback used by `Citation.for_target`).
module Codex
  module Citations
    class Strip < ApplicationComponent
      def initialize(target:, citations:, current_user: nil)
        @target       = target
        @citations    = Array(citations)
        @current_user = current_user
      end

      def view_template
        div(
          id:           dom_id,
          class:        "flex flex-wrap items-center gap-1.5",
          aria_live:    "polite",
          aria_relevant: "additions"
        ) do
          if @citations.empty?
            empty_state
          else
            @citations.each do |citation|
              render Pill.new(citation: citation)
            end
          end
        end
      end

      private

      # Pure form. Three faint dots + a single low-contrast word. Reads as
      # "this surface is available for lore, none has been written yet"
      # rather than "we failed to load citations".
      def empty_state
        span(
          class: "inline-flex items-center gap-1.5 text-micro text-gaia-text-muted/60 italic select-none",
          role:  "note"
        ) do
          span(aria_hidden: "true", class: "tracking-widest") { "· · ·" }
          span { t(".untold") }
        end
      end

      def dom_id
        type = if defined?(::Codex::Citation)
          ::Codex::Citation.polymorphic_type_for(@target) || @target.class.name
        else
          @target.class.name
        end
        "codex_citations_#{type.underscore}_#{@target.id}"
      end
    end
  end
end
