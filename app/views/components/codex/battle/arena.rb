# frozen_string_literal: true

# Codex::Battle::Arena — Turbo Frame `id="codex_battle_arena"` containing
# two pickable cards + VS divider.
#
# No Stimulus controller — both cards are real `<form method="post">`
# submissions, and Turbo handles the frame replacement on response.
# Keyboard shortcuts (←/→/space) deferred until a visible affordance
# (tooltip/legend) ships so users actually discover them.
#
# Error mode: when `PairSelectorService` cannot produce a pair (no realm,
# < 2 nodes, etc.), the component renders a friendly empty-state instead.
module Codex
  module Battle
    class Arena < ApplicationComponent
      def initialize(left:, right:, pair_seed:, realm:, error: nil)
        @left      = left
        @right     = right
        @pair_seed = pair_seed
        @realm     = realm
        @error     = error
      end

      def view_template
        div(
          id: "codex_battle_arena",
          class: tokens(
            "border border-gaia-border bg-gaia-surface p-5 space-y-5",
            "text-gaia-text"
          ),

        ) do
          render_header
          @error ? render_error : render_arena
        end
      end

      private

      def render_header
        div(class: "space-y-1") do
          h3(class: "text-tiny uppercase tracking-[0.3em] text-gaia-text-muted") { "Battle of the Nodes" }
          p(class: "text-mini text-gaia-text-muted") do
            @realm ? "Realm: #{@realm.name_en}" : "Realm: —"
          end
        end
      end

      def render_error
        div(class: tokens(
          "border border-status-warning bg-status-warning text-status-warning-text",
          "p-3 text-mini"
        )) do
          p(class: "uppercase tracking-[0.2em] font-mono") { @error.to_s }
        end
      end

      def render_arena
        div(class: "grid grid-cols-1 md:grid-cols-[1fr_auto_1fr] gap-3 items-stretch") do
          render_card(@left, side: :left)
          div(class: "flex items-center justify-center") do
            span(class: "text-tiny uppercase tracking-[0.3em] font-mono text-gaia-text-muted") { "VS" }
          end
          render_card(@right, side: :right)
        end
        render_skip
      end

      def render_card(node, side:)
        div(
          class: tokens(
            "border border-gaia-border bg-gaia-surface-alt p-3 space-y-2",
            "flex flex-col justify-between"
          ),

        ) do
          div(class: "space-y-1") do
            p(class: "text-tiny text-gaia-text") { node.title_en }
            p(class: "text-mini text-gaia-text-muted font-mono uppercase tracking-widest") do
              node.archetype_key
            end
            p(class: "text-mini text-gaia-text-muted font-mono") do
              "Elo: #{node.attunement_elo} · #{node.match_count}m"
            end
          end
          render_pick_form(node)
        end
      end

      def render_pick_form(node)
        form(
          action: api_v1_codex_votes_battle_path,
          method: "post",

        ) do
          input(type: "hidden", name: "pair_seed", value: @pair_seed)
          input(type: "hidden", name: "winner_slug", value: node.slug)
          button(
            type: "submit",
            class: tokens(
              "inline-flex items-center gap-2 px-3 py-1 border",
              "bg-gaia-surface text-gaia-text border-gaia-border",
              "hover:bg-gaia-primary hover:text-gaia-primary-text",
              "text-tiny uppercase tracking-[0.3em]",
              "focus-visible:ring-2 focus-visible:ring-gaia-primary"
            )
          ) { "Pick" }
        end
      end

      def render_skip
        form(
          action: api_v1_codex_votes_battle_path,
          method: "post",
          class: "flex justify-end",

        ) do
          input(type: "hidden", name: "pair_seed", value: @pair_seed)
          input(type: "hidden", name: "skip", value: "true")
          button(
            type: "submit",
            class: tokens(
              "inline-flex items-center gap-2 px-3 py-1 border border-gaia-border",
              "bg-gaia-surface text-gaia-text-muted",
              "hover:bg-gaia-surface-alt",
              "text-mini uppercase tracking-[0.3em] font-mono",
              "focus-visible:ring-2 focus-visible:ring-gaia-primary"
            )
          ) { "Skip" }
        end
      end
    end
  end
end
