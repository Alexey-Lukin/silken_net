# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Trees
  # = ===================================================================
  # 📜 CHRONICLE (Digital Life Story — Turbo Frame Container)
  # = ===================================================================
  # Рендерить хронологічну історію дерева як lazy-loaded Turbo Frame.
  # Відображає AiInsight, EwsAlert, MaintenanceRecord та BlockchainTransaction
  # події у єдиній стрічці з пагінацією та skeleton-завантаженням.
  #
  # [i18n-READY]: Тексти формуються через TreeChronicle::TextFormatter.
  # [МАСШТАБ]: Паgінація через Pagy, lazy-load через Turbo Frame.
  class Chronicle < ApplicationComponent
    # [i18n-READY]: Date format constants — replace with I18n.l() when localizing
    DATE_FORMAT_SHORT = "%d.%m"
    DATE_FORMAT_YEAR = "%Y"

    # @param tree [Tree] дерево для відображення хроніки
    # @param entries [Array<TreeChronicleService::Entry>] записи хроніки (pre-loaded)
    # @param pagy [Pagy] пагінація
    def initialize(tree:, entries:, pagy:)
      @tree = tree
      @entries = entries
      @pagy = pagy
    end

    def view_template
      turbo_frame_tag("tree_chronicle") do
        div(class: "space-y-6") do
          render_header
          render_entries
          render_pagination
        end
      end
    end

    private

    def render_header
      div(class: "flex items-center justify-between") do
        h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-subtle") { t(".heading") }
        span(class: "text-micro text-gaia-text-subtle font-mono") { t(".events", count: @pagy.count) }
      end
    end

    def render_entries
      if @entries.empty?
        render Views::Shared::UI::EmptyState.new(
          title: t(".empty_title"),
          description: t(".empty_description"),
          icon: "📜"
        )
      else
        div(class: "space-y-1") do
          @entries.each { |entry| render_entry(entry) }
        end
      end
    end

    def render_entry(entry)
      div(class: tokens("flex gap-4 p-4 border-l-2 transition-colors hover:bg-emerald-950/5", severity_border_class(entry.severity))) do
        # Іконка та дата (ліва частина)
        div(class: "flex-shrink-0 w-16 text-center") do
          div(class: "text-lg") { entry.icon }
          div(class: "text-micro font-mono text-gaia-text-muted mt-1") do
            plain(entry.date&.strftime(DATE_FORMAT_SHORT) || "—")
          end
          div(class: "text-micro font-mono text-gaia-text-subtle") do
            plain(entry.date&.strftime(DATE_FORMAT_YEAR) || "")
          end
        end

        # Контент (права частина)
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2 mb-1") do
            span(class: tokens("text-tiny font-bold uppercase tracking-wider", severity_text_class(entry.severity))) do
              entry.title
            end
            span(class: tokens("px-1.5 py-0.5 text-micro font-mono uppercase rounded",
                               event_type_badge_class(entry.event_type))) do
              TreeChronicle::TextFormatter.event_type_label(entry.event_type)
            end
          end

          p(class: "text-tiny text-gaia-text-muted font-mono leading-relaxed") { entry.description }
        end
      end
    end

    def render_pagination
      render Views::Shared::UI::Pagination.new(
        pagy: @pagy,
        url_helper: ->(page:) { chronicle_tree_path(@tree, page: page) }
      )
    end

    # --- Style helpers ---

    # [UI.1 сигнальна хвиля] Рамка тяжкості — СИГНАЛ (1.4.11): пастельні фони бейджів
    # тут давали 1.08:1 у світлій. Кожен штатний рівень іде `-accent`-двійником;
    # `else` (:stable) лишається тихим свідомо — його доля під відкритим ⚖️
    # (фолбек ⊥ живий :stable нерозрізненні, TEST.12/chronicle).
    def severity_border_class(severity)
      case severity
      when :critical then "border-status-danger-accent"
      when :warning  then "border-status-warning-accent"
      when :info     then "border-status-info-accent"
      else "border-emerald-800"
      end
    end

    def severity_text_class(severity)
      case severity
      when :critical then "text-status-danger-text"
      when :warning  then "text-status-warning-text"
      when :info     then "text-status-info-text"
      else "text-gaia-text"
      end
    end

    def event_type_badge_class(event_type)
      case event_type
      when :alert, :fraud          then "bg-status-danger text-status-danger-text"
      when :stress                 then "bg-status-warning text-status-warning-text"
      when :maintenance            then "bg-status-info text-status-info-text"
      when :minting                then "bg-status-success text-status-success-text"
      # [ARCH.101] Спалення — НЕ успіх: вилучення коштів мусить читатись тоном, а не
      # лише підписом. Без цієї гілки воно тихо падало б у нейтральний `else`.
      when :burning                then "bg-status-danger text-status-danger-text"
      when :recovery, :homeostasis then "bg-status-active text-status-active-text"
      else "bg-status-neutral text-status-neutral-text"
      end
    end
  end
end
