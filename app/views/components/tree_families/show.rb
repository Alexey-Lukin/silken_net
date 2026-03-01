# app/views/components/tree_families/show.rb
module Views
  module Components
    module TreeFamilies
      class Show < ApplicationComponent
        def initialize(family:)
          @family = family
        end

        def view_template
          div(class: "space-y-10 animate-in slide-in-from-right duration-700") do
            render_hero
            
            div(class: "grid grid-cols-1 lg:grid-cols-2 gap-8") do
              render_threshold_viz
              render_biological_props
            end
          end
        end

        private

        def render_hero
          div(class: "p-10 border border-emerald-900 bg-zinc-950 relative overflow-hidden") do
            div(class: "absolute top-0 right-0 p-4 text-[120px] font-bold text-emerald-900/5 select-none uppercase") { @family.name.first(3) }
            
            h2(class: "text-5xl font-extralight tracking-tighter text-white") { @family.name }
            p(class: "text-[10px] font-mono text-emerald-700 uppercase tracking-[0.4em] mt-4") { "Baseline Impedance: #{@family.baseline_impedance} kOhm" }
          end
        end

        def render_threshold_viz
          div(class: "p-8 border border-emerald-900 bg-black space-y-8") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "The Homeostasis Scale" }
            
            # Візуальна шкала
            div(class: "relative pt-10 pb-4") do
              # Лінія шкали
              div(class: "h-px w-full bg-emerald-900/50")
              
              # Маркери
              marker(@family.death_threshold_impedance, "DEATH", "bg-red-900")
              marker(@family.critical_z_min, "SAFE_MIN", "bg-emerald-500")
              marker(@family.baseline_impedance, "BASELINE", "bg-white", active: true)
              marker(@family.critical_z_max, "SAFE_MAX", "bg-emerald-500")
            end
          end
        end

        def marker(value, label, color, active: false)
          # Дуже спрощена логіка позиціонування для прикладу
          left = [(value.to_f / (@family.critical_z_max * 1.2) * 100), 100].min
          div(class: "absolute top-0 flex flex-col items-center", style: "left: #{left}%") do
             span(class: "text-[8px] text-gray-600 mb-2 font-mono") { "#{value}kΩ" }
             div(class: tokens("h-3 w-px", active ? "bg-white" : "bg-emerald-900"))
             span(class: tokens("mt-4 text-[7px] uppercase tracking-tighter", active ? "text-white" : "text-gray-700")) { label }
          end
        end

        def render_biological_props
          div(class: "p-8 border border-emerald-900 bg-emerald-950/5") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "TinyML Biological Features" }
            div(class: "space-y-4 font-mono text-[11px]") do
              prop_row("Sap Flow Index", @family.sap_flow_index || "0.0")
              prop_row("Bark Thickness", "#{@family.bark_thickness || 0} mm")
              prop_row("Foliage Density", "#{@family.foliage_density || 0} %")
              prop_row("Fire Rating", @family.fire_resistance_rating || "N/A")
            end
          end
        end

        def prop_row(label, value)
          div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
            span(class: "text-gray-600") { label }
            span(class: "text-emerald-100") { value }
          end
        end
      end
    end
  end
end
