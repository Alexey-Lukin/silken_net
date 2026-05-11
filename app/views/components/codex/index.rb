# frozen_string_literal: true

# Codex::Index — Atlas grid of lore cards.
module Codex
  class Index < ApplicationComponent
    # @param nodes_counts [Hash<Integer,Integer>] realm_id → node count, pre-computed
    #   by the controller to avoid a second GROUP BY query here.
    def initialize(nodes:, pagy:, realms:, active_realm_slug: nil, nodes_counts: nil)
      @nodes = nodes
      @pagy = pagy
      @realms = realms
      @active_realm_slug = active_realm_slug
      @nodes_counts = nodes_counts
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
            title: I18n.t("codex.atlas.empty.title"),
            icon: "📖",
            description: I18n.t("codex.atlas.empty.description")
          )
        end
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-end gap-4 border-b border-gaia-border pb-3") do
        div do
          p(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted") { I18n.t("codex.atlas.kicker") }
          h2(class: "text-2xl font-extralight tracking-tight text-gaia-text") { I18n.t("codex.atlas.title") }
        end
        p(class: "text-tiny font-mono text-gaia-text-muted") do
          I18n.t("codex.atlas.count", count: @pagy.count)
        end
      end
    end

    # Use controller-supplied counts when available; fall back to a local
    # GROUP BY only when rendering in isolation (e.g. ViewComponent previews).
    def realm_counts
      @nodes_counts || ::Codex::Node.group(:codex_realm_id).count
    end
  end
end
