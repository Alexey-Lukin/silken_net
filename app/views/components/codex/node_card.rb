# frozen_string_literal: true

# Codex::NodeCard — Phlex card adapter around lore Codex::Node entries.
#
# Reuses dashboard tokens (gaia-* / status-*) only. The realm accent is
# pulled from `node.realm.accent_token` and applied to the corner badge.
#
# Used inside `Codex::Index` grid and (Phase 4) the Battle Arena.
module Codex
  class NodeCard < ApplicationComponent
    def initialize(node:)
      @node = node
    end

    def view_template
      a(
        href: api_v1_codex_node_path(@node),
        aria_label: "Open Codex card: #{@node.title_en}",
        class: tokens(card_classes)
      ) do
        div(class: "relative") do
          render_cover
          render_realm_pill
          render_lifecycle_badge
        end
        div(class: "p-4 space-y-1") do
          p(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-muted") { @node.codex_uid }
          h3(class: "text-base text-gaia-text font-light") { @node.title_uk }
          p(class: "text-tiny text-gaia-text-muted") { @node.title_en }
          if @node.subtitle_en.present?
            p(class: "text-mini text-gaia-primary uppercase tracking-widest") { @node.subtitle_en }
          end
        end
        render_footer
      end
    end

    private

    def card_classes
      "block group border border-gaia-border bg-gaia-surface " \
        "shadow-sm dark:shadow-none overflow-hidden " \
        "hover:border-gaia-primary transition-all duration-200 ease-in-out " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
    end

    def render_cover
      div(class: "relative aspect-[4/3] bg-gaia-surface-alt overflow-hidden") do
        if @node.cover_image.attached? && @node.cover_image.representable?
          img(
            src: rails_representation_path(@node.cover_image.variant(resize_to_fill: [ 480, 360 ])),
            alt: @node.title_en,
            loading: "lazy",
            class: "w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
          )
        else
          div(class: "w-full h-full flex items-center justify-center text-4xl text-gaia-primary opacity-30") do
            plain glyph_for_realm(@node.realm&.glyph)
          end
        end
      end
    end

    def render_realm_pill
      return unless @node.realm

      span(class: tokens(
        "absolute top-2 left-2 px-2 py-0.5 text-micro uppercase tracking-widest font-bold",
        "bg-black/70 text-gaia-primary"
      )) { @node.realm.name_en }
    end

    def render_lifecycle_badge
      div(class: "absolute top-2 right-2") do
        render Views::Shared::UI::StatusBadge.new(status: @node.lifecycle_status)
      end
    end

    def render_footer
      div(class: "px-4 py-2 border-t border-gaia-border flex justify-between text-mini text-gaia-text-muted font-mono") do
        span { "Elo #{@node.attunement_elo}" }
        if @node.geo_region.present?
          span(class: "truncate") { @node.geo_region }
        else
          span { "—" }
        end
      end
    end

    def glyph_for_realm(key)
      case key
      when "forest"   then "🌲"
      when "tree"     then "🌳"
      when "protocol" then "⚛"
      when "mythos"   then "✶"
      else "○"
      end
    end
  end
end
