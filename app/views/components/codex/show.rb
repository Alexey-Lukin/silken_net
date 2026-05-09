# frozen_string_literal: true

# Codex::Show — single node deep-dive.
module Codex
  class Show < ApplicationComponent
    def initialize(node:)
      @node = node
    end

    def view_template
      div(class: "space-y-8") do
        render_hero
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-6") { render_lore_columns }
          aside(class: "space-y-4") { render_meta_panel }
        end
      end
    end

    private

    def render_hero
      div(class: "relative p-8 border border-gaia-border bg-gaia-surface overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[80px] font-bold text-gaia-primary opacity-5 select-none uppercase") do
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
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted") { "Context" }
          div(class: "prose prose-sm dark:prose-invert max-w-none text-gaia-text") do
            unsafe_raw Codex::MarkdownRenderer.render(@node.context_md)
          end
        end
      end

      if @node.cyber_meaning_md.present?
        section(class: "space-y-2") do
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-primary") { "Cyber Meaning" }
          div(class: "bg-gaia-surface-alt p-4 border-l-2 border-gaia-primary") do
            div(class: "prose prose-sm dark:prose-invert max-w-none text-gaia-text") do
              unsafe_raw Codex::MarkdownRenderer.render(@node.cyber_meaning_md)
            end
          end
        end
      end

      if @node.lore_md.present?
        section(class: "space-y-2") do
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted") { "Lore" }
          div(class: "prose prose-sm dark:prose-invert max-w-none text-gaia-text") do
            unsafe_raw Codex::MarkdownRenderer.render(@node.lore_md)
          end
        end
      end
    end

    def render_meta_panel
      div(class: "border border-gaia-border bg-gaia-surface p-4 space-y-2 text-tiny font-mono") do
        h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted mb-2") { "Metadata" }
        render Views::Shared::UI::MetaRow.new(label: "Realm", value: (@node.realm&.name_en || "—"))
        render Views::Shared::UI::MetaRow.new(label: "Archetype", value: @node.archetype_key)
        div(class: "flex justify-between gap-2") do
          span(class: "text-gaia-text-muted") { "Lifecycle:" }
          render Views::Shared::UI::StatusBadge.new(status: @node.lifecycle_status)
        end
        render Views::Shared::UI::MetaRow.new(label: "Geo Region", value: (@node.geo_region.presence || "—"))
        render Views::Shared::UI::MetaRow.new(label: "Discovered", value: @node.discovery_count.to_s)
        render Views::Shared::UI::MetaRow.new(label: "Cited By", value: @node.citation_count.to_s)
        render Views::Shared::UI::MetaRow.new(label: "Attunement", value: @node.attunement_count.to_s)
        render Views::Shared::UI::MetaRow.new(label: "Elo", value: @node.attunement_elo.to_s)
      end

      if @node.external_refs.present?
        div(class: "border border-gaia-border bg-gaia-surface p-4 space-y-2") do
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted mb-1") { "External References" }
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
