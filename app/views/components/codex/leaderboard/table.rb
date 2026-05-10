# frozen_string_literal: true

# Codex::Leaderboard::Table — top-N Elo for a single realm.
#
# Lightweight Phlex component (not the heavy DataTable from §7) — keeps
# the markup terse so the public read endpoint is fast. Rank is computed
# in Ruby (no `ROW_NUMBER()` SQL) since `nodes` is already capped at the
# controller's `limit`.
module Codex
  module Leaderboard
    class Table < ApplicationComponent
      def initialize(realm:, nodes:, limit:)
        @realm = realm
        @nodes = nodes.to_a
        @limit = limit
      end

      def view_template
        div(
          id: "codex_leaderboard",
          class: tokens(
            "border border-gaia-border bg-gaia-surface p-5 space-y-4",
            "text-gaia-text"
          )
        ) do
          render_header
          @nodes.empty? ? render_empty : render_table
        end
      end

      private

      def render_header
        div(class: "space-y-1") do
          h3(class: "text-tiny uppercase tracking-[0.3em] text-gaia-text-muted") { "Codex Leaderboard" }
          p(class: "text-mini text-gaia-text-muted") do
            (@realm ? "Realm: #{@realm.name_en} · " : "") + "Top #{@limit}"
          end
        end
      end

      def render_empty
        p(class: "text-mini text-gaia-text-muted italic") { "No ranked nodes yet." }
      end

      def render_table
        table(class: "w-full text-tiny font-mono") do
          thead(class: "text-mini uppercase tracking-[0.2em] text-gaia-text-muted") do
            tr do
              th(class: "py-1 pr-2 text-left") { "#" }
              th(class: "py-1 pr-2 text-left") { "Title" }
              th(class: "py-1 pr-2 text-right") { "Elo" }
              th(class: "py-1 pr-2 text-right") { "Matches" }
              th(class: "py-1 text-right") { "Lifecycle" }
            end
          end
          tbody do
            @nodes.each_with_index do |node, idx|
              render_row(node, idx + 1)
            end
          end
        end
      end

      def render_row(node, rank)
        tr(class: "border-t border-gaia-border") do
          td(class: "py-1 pr-2") { rank.to_s }
          td(class: "py-1 pr-2 text-gaia-text") { node.title_en }
          td(class: "py-1 pr-2 text-right") { node.attunement_elo.to_s }
          td(class: "py-1 pr-2 text-right text-gaia-text-muted") { node.match_count.to_s }
          td(class: "py-1 text-right text-gaia-text-muted") { node.lifecycle_status.to_s }
        end
      end
    end
  end
end
