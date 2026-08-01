# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Discoveries::Toast — Turbo Stream payload for a freshly-unlocked
# Codex card.
#
# Render contract: this component renders a single `<div>` that the
# Stimulus `codex--reveal` controller will pop in with the matrix-rain
# animation. The dashboard layout is expected to expose a Turbo Stream
# target `codex_discovery_feed` (a sticky region in the bottom-right).
#
# Animation policy: keep the markup self-sufficient — text, archetype
# pill, "Visit" link. The reveal controller handles fade-in; absent JS,
# the toast still appears (just without animation).
#
# Namespacing: lives under `Codex::Discoveries::*` (plural) to avoid a
# Zeitwerk const-clash with the `Codex::Discovery` AR model class.
module Codex
  module Discoveries
    class Toast < ApplicationComponent
      def initialize(node:, trigger_type:, unlocked_at:)
        @node         = node
        @trigger_type = trigger_type.to_s
        @unlocked_at  = unlocked_at
      end

      def view_template
        div(
          class: tokens(
            "border border-gaia-border bg-gaia-surface text-gaia-text",
            "p-3 space-y-1 max-w-sm shadow"
          ),
          data: { controller: "codex--reveal", "codex--reveal-trigger-value": @trigger_type }
        ) do
          render_header
          render_title
          render_meta
          render_cta
        end
      end

      private

      def render_header
        div(class: "flex items-center justify-between") do
          span(class: "text-mini uppercase tracking-[0.3em] font-mono text-gaia-text-muted") do
            t(".kicker")
          end
          span(class: tokens(
            "text-mini font-mono uppercase tracking-widest",
            "text-status-success-text bg-status-success px-2"
          )) { trigger_label }
        end
      end

      def render_title
        h4(class: "text-tiny text-gaia-text") { @node.title_en }
      end

      def render_meta
        p(class: "text-mini text-gaia-text-muted font-mono") do
          [ @node.archetype_key, @unlocked_at&.strftime("%H:%M UTC") ].compact.join(" · ")
        end
      end

      def render_cta
        a(
          # Хелпер, не літерал [ARCH.77]: рукописний шлях не переїде разом із
          # роутером і не почервоніє — а парний пін у спеці цементував би саме
          # його, тобто пара «літерал у коді + літерал у спеці» лишалась би
          # самосинхронно зеленою на мертвій адресі.
          href: codex_node_path(@node.slug),
          class: tokens(
            "inline-block text-mini uppercase tracking-[0.3em]",
            "text-gaia-primary hover:underline focus-visible:ring-2 focus-visible:ring-gaia-primary"
          )
        ) { t(".visit") }
      end

      def trigger_label
        key = case @trigger_type
        when "telemetry_observation", "match_milestone", "fraction_choice",
             "attunement_streak", "oracle_seasonal", "manual_unlock"
          @trigger_type
        else
          "default"
        end
        t(".triggers.#{key}")
      end
    end
  end
end
