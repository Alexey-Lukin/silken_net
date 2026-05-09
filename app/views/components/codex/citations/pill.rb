# frozen_string_literal: true

# Codex::Citations::Pill — single inline citation chip.
#
# Renders a compact pill linking back to the cited Codex Node:
#
#   « Mafusail · relict_oracle »
#
# Used inside `Codex::Citations::Strip` and (for one-off renders) standalone.
# Design tokens only — gaia-* surface, focus-visible ring, mini text scale.
module Codex
  module Citations
    class Pill < ApplicationComponent
      # @param citation [Codex::Citation] eager-loaded with `:node`
      def initialize(citation:)
        @citation = citation
      end

      def view_template
        node = @citation.node
        # Defensive — Node could be in the process of being soft-archived.
        return if node.nil?

        a(
          href:        "/api/v1/codex/nodes/#{node.slug}",
          id:          dom_id,
          class:       pill_classes,
          aria_label:  aria_label(node),
          title:       full_title(node),
          data:        { codex_citation_id: @citation.id }
        ) do
          span(class: "opacity-70") { "« " }
          span(class: "font-medium") { node.title_en.presence || node.slug }
          if node.archetype_key.present?
            span(class: "ml-1 opacity-60 text-micro uppercase tracking-tighter") do
              "· #{node.archetype_key}"
            end
          end
          span(class: "opacity-70") { " »" }
        end
      end

      private

      def dom_id
        "codex_citation_#{@citation.id}"
      end

      def pill_classes
        tokens(
          "inline-flex items-center gap-0.5 px-2 py-0.5",
          "text-mini bg-gaia-surface-alt text-gaia-text",
          "border border-gaia-border rounded",
          "hover:border-gaia-primary",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary",
          "transition-colors"
        )
      end

      def aria_label(node)
        if @citation.note.present?
          "Codex citation: #{node.title_en} — #{@citation.note}"
        else
          "Codex citation: #{node.title_en}"
        end
      end

      # Shown on hover. Note can be up to 140 chars; this surfaces forester
      # context without requiring a click-through.
      def full_title(node)
        base = node.title_en.to_s
        return base if @citation.note.blank?
        "#{base} — #{@citation.note}"
      end
    end
  end
end
