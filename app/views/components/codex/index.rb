# frozen_string_literal: true

# Codex::Index — Atlas grid of lore cards.
module Codex
  class Index < ApplicationComponent
    def initialize(nodes:, pagy:, realms:, active_realm_slug: nil)
      @nodes = nodes
      @pagy = pagy
      @realms = realms
      @active_realm_slug = active_realm_slug
    end

    def view_template
      div(class: "space-y-6") do
        render_header
        render Codex::RealmTabs.new(
          realms: @realms,
          nodes_counts: realm_counts,
          active_realm_slug: @active_realm_slug
        )

        if @nodes.any?
          div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4") do
            @nodes.each { |node| render Codex::NodeCard.new(node: node) }
          end

          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { api_v1_codex_nodes_path(page: page, realm: @active_realm_slug) }
          )
        else
          render Views::Shared::UI::EmptyState.new(
            title: "Codex is silent. No archetypes match this filter.",
            icon: "📖",
            description: "Try a broader realm or clear the search."
          )
        end
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-end gap-4 border-b border-gaia-border pb-3") do
        div do
          p(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted") { "Lore Layer" }
          h2(class: "text-2xl font-extralight tracking-tight text-gaia-text") { "Codex of Archetypes" }
        end
        p(class: "text-tiny font-mono text-gaia-text-muted") { "#{@pagy.count} archetypes catalogued" }
      end
    end

    # Cheap per-render aggregation; counts are tiny (~4 realms).
    def realm_counts
      @realm_counts ||= ::Codex::Node.group(:codex_realm_id).count
    end
  end
end
