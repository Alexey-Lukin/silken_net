# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Show — single node deep-dive.
module Codex
  class Show < ApplicationComponent
    def initialize(node:, current_user: nil, comments: [], current_user_attuned: false)
      @node = node
      @current_user = current_user
      @comments = comments
      @current_user_attuned = current_user_attuned
    end

    def view_template
      div(class: "space-y-8") do
        render_hero
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-6") do
            render_lore_columns
            render Codex::Comments::Thread.new(
              node: @node, comments: @comments, current_user: @current_user
            )
          end
          aside(class: "space-y-4") do
            render Codex::Attunements::Toggle.new(
              node: @node,
              current_user_attuned: @current_user_attuned,
              count: @node.attunement_count
            )
            render_meta_panel
          end
        end
      end
    end

    private

    # NB: both `@node.realm&.name_en` guards below (hero watermark, meta
    # panel) are model-validation-dead, not real: `Node#realm` is a required
    # belongs_to and `codex_realm_id` has no cascade/nullify path (plain FK,
    # no `ON DELETE`; Realm also uses `dependent: :restrict_with_error` on
    # its `has_many :nodes`) — a Realm can never be removed out from under a
    # Node, so `.realm` is always present here. Left as `&.` for defensive
    # style, not tested.
    def render_hero
      div(class: "relative p-8 border border-gaia-border bg-gaia-surface overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[80px] font-bold text-gaia-primary opacity-5 select-none uppercase", aria_hidden: "true") do
          plain @node.realm&.name_en || "Codex"
        end
        div(class: "relative") do
          p(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-2") { @node.codex_uid }
          h1(class: "text-3xl font-extralight tracking-tight text-gaia-text") { @node.title_uk }
          p(class: "text-base font-mono text-gaia-text-muted mt-1") { @node.title_en }
          if @node.subtitle_en.present?
            p(class: "text-tiny uppercase tracking-widest text-gaia-primary mt-3") { @node.subtitle_en }
          end
        end
      end
    end

    def render_lore_columns
      if @node.context_md.present?
        section(class: "space-y-2") do
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted") { t(".sections.context") }
          div(class: "prose prose-sm dark:prose-invert max-w-none text-gaia-text") do
            raw safe(Codex::MarkdownRenderer.render(@node.context_md))
          end
        end
      end

      if @node.cyber_meaning_md.present?
        section(class: "space-y-2") do
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-primary") { t(".sections.cyber_meaning") }
          div(class: "bg-gaia-surface-sunken p-4 border-l-2 border-gaia-primary") do
            div(class: "prose prose-sm dark:prose-invert max-w-none text-gaia-text") do
              raw safe(Codex::MarkdownRenderer.render(@node.cyber_meaning_md))
            end
          end
        end
      end

      if @node.lore_md.present?
        section(class: "space-y-2") do
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted") { t(".sections.lore") }
          div(class: "prose prose-sm dark:prose-invert max-w-none text-gaia-text") do
            raw safe(Codex::MarkdownRenderer.render(@node.lore_md))
          end
        end
      end
    end

    def render_meta_panel
      div(class: "border border-gaia-border bg-gaia-surface p-4 space-y-2 text-tiny font-mono") do
        h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted mb-2") { t(".sections.metadata") }
        render Views::Shared::UI::MetaRow.new(label: t(".meta.realm"), value: (@node.realm&.name_en || "—"))
        render Views::Shared::UI::MetaRow.new(label: t(".meta.archetype"), value: @node.archetype_key)
        div(class: "flex justify-between gap-2") do
          span(class: "text-gaia-text-muted") { t(".meta.lifecycle") }
          render Views::Shared::UI::StatusBadge.new(status: @node.lifecycle_status)
        end
        render Views::Shared::UI::MetaRow.new(label: t(".meta.geo_region"), value: (@node.geo_region.presence || "—"))
        render Views::Shared::UI::MetaRow.new(label: t(".meta.discovered"), value: @node.discovery_count.to_s)
        render Views::Shared::UI::MetaRow.new(label: t(".meta.cited_by"), value: @node.citation_count.to_s)
        render Views::Shared::UI::MetaRow.new(label: t(".meta.attunement"), value: @node.attunement_count.to_s)
        render Views::Shared::UI::MetaRow.new(label: t(".meta.elo"), value: @node.attunement_elo.to_s)
      end

      if @node.external_refs.present?
        div(class: "border border-gaia-border bg-gaia-surface p-4 space-y-2") do
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted mb-1") { t(".sections.external_references") }
          ul(class: "space-y-1 text-tiny") do
            @node.external_refs.each do |ref|
              li do
                a(
                  href: ref["url"],
                  target: "_blank",
                  rel: "noopener noreferrer",
                  class: "text-gaia-primary hover:underline"
                ) { ref["label"].presence || ref["url"] }
              end
            end
          end
        end
      end
    end
  end
end
