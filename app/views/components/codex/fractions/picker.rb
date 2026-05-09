# frozen_string_literal: true

# Codex::Fractions::Picker — Turbo Frame fragment listing pickable nodes
# for the active realm. The user submits a tiny POST form per node; the
# controller dispatches to `Codex::FractionChangeService` which enforces
# the 7-day cooldown.
module Codex
  module Fractions
    class Picker < ApplicationComponent
      def initialize(realms:, active_realm:, nodes:, current_fraction: nil)
        @realms           = realms
        @active_realm     = active_realm
        @nodes            = nodes
        @current_fraction = current_fraction
      end

      def view_template
        div(
          id: "codex_fraction_picker",
          class: tokens(
            "border border-gaia-border bg-gaia-surface p-5 space-y-5",
            "text-gaia-text"
          ),
          data: { controller: "codex--fraction-picker" }
        ) do
          render_header
          render_realm_tabs
          render_grid
        end
      end

      private

      def render_header
        div(class: "space-y-1") do
          h3(class: "text-tiny uppercase tracking-[0.3em] text-gaia-text-muted") { "Pick a Fraction" }
          p(class: "text-mini text-gaia-text-muted") do
            "One archetype, one identity. Re-pick available every 7 days."
          end
        end
      end

      def render_realm_tabs
        return if @realms.blank?

        nav(class: "flex flex-wrap gap-2") do
          @realms.each do |realm|
            a(
              href: api_v1_codex_fraction_picker_path(realm: realm.slug),
              class: realm_tab_classes(realm)
            ) { realm.name_en }
          end
        end
      end

      def realm_tab_classes(realm)
        if realm.id == @active_realm&.id
          tokens(
            "inline-flex items-center gap-2 px-3 py-1 border",
            "bg-gaia-primary text-gaia-primary-text border-gaia-primary",
            "text-tiny uppercase tracking-[0.3em]"
          )
        else
          tokens(
            "inline-flex items-center gap-2 px-3 py-1 border border-gaia-border",
            "text-tiny uppercase tracking-[0.3em] text-gaia-text",
            "hover:bg-gaia-primary hover:text-gaia-primary-text",
            "focus-visible:ring-2 focus-visible:ring-gaia-primary"
          )
        end
      end

      def render_grid
        if @nodes.blank?
          p(class: "text-mini text-gaia-text-muted italic") { "No pickable nodes in this realm." }
          return
        end

        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3") do
          @nodes.each { |node| render_node_card(node) }
        end
      end

      def render_node_card(node)
        active          = @current_fraction&.codex_node_id == node.id
        cooldown_locked = @current_fraction&.cooldown_active? && !active

        div(
          class: tokens(
            "border p-3 space-y-2 flex flex-col justify-between",
            "bg-gaia-surface-alt",
            active ? "border-gaia-primary" : "border-gaia-border"
          )
        ) do
          div(class: "space-y-1") do
            p(class: "text-tiny text-gaia-text") { node.title_en }
            p(class: "text-mini text-gaia-text-muted font-mono uppercase tracking-widest") do
              node.archetype_key
            end
          end
          render_pick_button(node, active: active, cooldown_locked: cooldown_locked)
        end
      end

      def render_pick_button(node, active:, cooldown_locked:)
        if active
          span(class: "text-mini uppercase tracking-[0.3em] text-status-success-text") { "Current" }
          return
        end

        form(
          action: api_v1_codex_fractions_path,
          method: "post",
          data: { "codex--fraction-picker-target": "form" }
        ) do
          input(type: "hidden", name: "fraction[node_slug]", value: node.slug)
          button(
            type: "submit",
            disabled: cooldown_locked,
            class: tokens(
              "inline-flex items-center gap-2 px-3 py-1 border",
              "text-tiny uppercase tracking-[0.3em]",
              "focus-visible:ring-2 focus-visible:ring-gaia-primary",
              cooldown_locked ? locked_classes : open_classes
            )
          ) { cooldown_locked ? "Locked" : "Pick" }
        end
      end

      def open_classes
        "bg-gaia-surface text-gaia-text border-gaia-border hover:bg-gaia-primary hover:text-gaia-primary-text"
      end

      def locked_classes
        "bg-gaia-surface text-gaia-text-muted border-gaia-border opacity-60 cursor-not-allowed"
      end
    end
  end
end
