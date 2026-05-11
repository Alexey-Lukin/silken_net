# frozen_string_literal: true

# Codex::RealmTabs — horizontal filter strip on top of the Atlas Index.
#
# Highlights the currently active realm (slug); clicking a tab navigates
# to the index filtered by that realm. "All" tab clears the filter.
module Codex
  class RealmTabs < ApplicationComponent
    def initialize(realms:, nodes_counts: {}, active_realm_slug: nil)
      @realms = realms
      @nodes_counts = nodes_counts
      @active_realm_slug = active_realm_slug
    end

    def view_template
      nav(
        aria_label: I18n.t("codex.realm_tabs.aria_label"),
        class: "flex flex-wrap gap-2 border-b border-gaia-border pb-3"
      ) do
        render_tab(label: I18n.t("codex.realm_tabs.all"), slug: nil, count: @nodes_counts.values.sum)
        @realms.each do |realm|
          render_tab(
            label: realm.name_en,
            slug: realm.slug,
            count: @nodes_counts[realm.id] || 0
          )
        end
      end
    end

    private

    def render_tab(label:, slug:, count:)
      active = (@active_realm_slug == slug)
      href   = slug.nil? ? api_v1_codex_nodes_path : api_v1_codex_nodes_path(realm: slug)

      a(
        href: href,
        aria_current: (active ? "page" : nil),
        class: tokens(tab_classes, active ? active_classes : inactive_classes)
      ) do
        span(class: "uppercase tracking-widest text-tiny") { label }
        span(class: "text-micro opacity-70") { "(#{count})" }
      end
    end

    def tab_classes
      "inline-flex items-center gap-2 px-3 py-1.5 border " \
        "transition-colors duration-200 ease-in-out " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
    end

    def active_classes
      "border-gaia-primary text-gaia-primary bg-gaia-surface-sunken"
    end

    def inactive_classes
      "border-gaia-border text-gaia-text-muted hover:border-gaia-primary hover:text-gaia-primary"
    end
  end
end
