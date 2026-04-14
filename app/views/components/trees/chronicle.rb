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
        h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "Digital Chronicle" }
        span(class: "text-micro text-emerald-900 font-mono") { "#{@pagy.count} events" }
      end
    end

    def render_entries
      if @entries.empty?
        render Views::Shared::UI::EmptyState.new(
          title: "No chronicle events recorded",
          description: "Events will appear here as the tree generates telemetry data",
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
          div(class: "text-micro font-mono text-emerald-900 mt-1") do
            plain(entry.date&.strftime("%d.%m") || "—")
          end
          div(class: "text-micro font-mono text-gray-700") do
            plain(entry.date&.strftime("%Y") || "")
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
              entry.event_type.to_s
            end
          end

          p(class: "text-tiny text-gray-400 font-mono leading-relaxed") { entry.description }
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

    def severity_border_class(severity)
      case severity
      when :critical then "border-red-600"
      when :warning  then "border-yellow-600"
      when :info     then "border-blue-600"
      else "border-emerald-800"
      end
    end

    def severity_text_class(severity)
      case severity
      when :critical then "text-red-400"
      when :warning  then "text-yellow-400"
      when :info     then "text-blue-400"
      else "text-emerald-400"
      end
    end

    def event_type_badge_class(event_type)
      case event_type
      when :alert, :fraud          then "bg-red-900/30 text-red-400"
      when :stress                 then "bg-yellow-900/30 text-yellow-400"
      when :maintenance            then "bg-blue-900/30 text-blue-400"
      when :minting                then "bg-emerald-900/30 text-emerald-400"
      when :recovery, :homeostasis then "bg-emerald-900/20 text-emerald-600"
      else "bg-zinc-800 text-zinc-400"
      end
    end
  end
end
