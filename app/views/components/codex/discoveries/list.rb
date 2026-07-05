# frozen_string_literal: true

# Codex::Discoveries::List — paginated grid of own unlocks.
#
# Used by `Api::V1::Codex::DiscoveriesController#me` (HTML format).
# Empty-state copy when the user hasn't unlocked anything yet.
module Codex
  module Discoveries
    class List < ApplicationComponent
      def initialize(discoveries:, pagy: nil)
        @discoveries = discoveries.to_a
        @pagy        = pagy
      end

      def view_template
        div(
          id: "codex_discoveries_collection",
          class: "border border-gaia-border bg-gaia-surface text-gaia-text p-5 space-y-4"
        ) do
          render_header
          @discoveries.empty? ? render_empty : render_grid
        end
      end

      private

      def render_header
        div(class: "space-y-1") do
          h3(class: "text-tiny uppercase tracking-[0.3em] text-gaia-text-muted") { t("codex.discoveries.heading") }
          p(class: "text-mini text-gaia-text-muted font-mono") do
            count = @pagy ? @pagy.count : @discoveries.size
            t("codex.discoveries.counter", count: count)
          end
        end
      end

      def render_empty
        p(class: "text-mini text-gaia-text-muted italic") do
          t("codex.discoveries.empty")
        end
      end

      def render_grid
        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3") do
          @discoveries.each { |d| render_card(d) }
        end
      end

      # `node&.` / `unlocked_at&.` below are model-validation-dead, not real:
      # `Discovery#node` is a required belongs_to and `codex_node_id` carries
      # an `ON DELETE RESTRICT` FK (a Node can never be deleted while a
      # Discovery cites it), and `unlocked_at` is `validates presence: true`
      # with a `before_validation` default — both are always present for a
      # persisted, valid Discovery.
      def render_card(discovery)
        node = discovery.node
        div(class: "border border-gaia-border bg-gaia-surface-sunken p-3 space-y-1") do
          p(class: "text-tiny text-gaia-text") { node&.title_en.to_s }
          p(class: "text-mini text-gaia-text-muted font-mono uppercase tracking-widest") do
            node&.archetype_key.to_s
          end
          p(class: "text-mini text-gaia-text-muted") do
            t(
              "codex.discoveries.meta",
              trigger: discovery.trigger_type,
              timestamp: discovery.unlocked_at&.strftime("%Y-%m-%d %H:%M UTC")
            )
          end
        end
      end
    end
  end
end
