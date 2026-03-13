module Trees
  class Index < ApplicationComponent
    def initialize(cluster:, trees:, pagy: nil)
      @cluster = cluster
      @trees = trees
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        render_header

        # Масова сітка солдатів
        div(class: "grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8 gap-4") do
          @trees.each do |tree|
            render_soldier_node(tree)
          end
        end

        if @pagy
          render Shared::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { helpers.api_v1_cluster_trees_path(@cluster, page: page) }
          )
        end
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-end mb-6 border-b border-emerald-900/30 pb-6") do
        div do
          h3(class: "text-[10px] uppercase tracking-[0.5em] text-emerald-700") { "Sector Matrix Deployment" }
          h2(class: "text-3xl font-extralight text-emerald-400 mt-1") { @cluster.name }
        end

        div(class: "flex space-x-8 text-right font-mono text-[10px]") do
          header_stat("Population", @pagy&.count || @trees.size, "Soldiers")
          header_stat("Operational", @cluster.active_trees_count, "Nodes")
        end
      end
    end

    def header_stat(label, value, unit, danger: false)
      div do
        p(class: "text-gray-600 uppercase mb-1") { label }
        span(class: tokens("text-lg", danger ? "text-red-500" : "text-emerald-100")) { value.to_s }
        span(class: "ml-1 text-emerald-900") { unit }
      end
    end

    def render_soldier_node(tree)
      voltage = tree.ionic_voltage
      charge_percent = tree.charge_percentage

      a(
        href: helpers.api_v1_tree_path(tree),
        class: "group relative p-3 border border-emerald-900/50 bg-black hover:border-emerald-500 transition-all duration-300"
      ) do
        # DID та Статус
        div(class: "flex justify-between items-start mb-3") do
          span(class: "text-[9px] font-mono text-emerald-800 group-hover:text-emerald-400") { tree.did.last(6) }
          div(class: tokens("h-1.5 w-1.5 rounded-full", tree_status_led(tree)))
        end

        # Індикатор заряду іоністора (Streaming Potential Reserve)
        div(class: "space-y-1") do
          div(class: "flex justify-between text-[7px] uppercase text-gray-700 font-mono") do
            span { "Ionic Pulse" }
            span { "#{voltage}mV" }
          end
          div(class: "w-full h-0.5 bg-emerald-950 overflow-hidden") do
            div(
              class: tokens("h-full transition-all duration-1000", charge_color(charge_percent)),
              style: "width: #{charge_percent}%"
            )
          end
        end

        # Hover overlay зі стресом
        div(class: "absolute inset-0 bg-emerald-500/10 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none")
      end
    end

    def tree_status_led(tree)
      return "bg-red-600 animate-pulse shadow-[0_0_8px_red]" if tree.under_threat?
      return "bg-gray-800" if tree.last_seen_at.nil? || tree.last_seen_at < 24.hours.ago
      "bg-emerald-500 shadow-[0_0_5px_#10b981]"
    end

    def charge_color(percent)
      if percent > 70 then "bg-emerald-500 shadow-[0_0_5px_#10b981]"
      elsif percent > 30 then "bg-amber-500"
      else "bg-red-600 animate-pulse"
      end
    end
  end
end
