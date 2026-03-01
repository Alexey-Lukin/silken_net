# frozen_string_literal: true

module Views
  module Components
    module OracleVisions
      class SimulationPanel < ApplicationComponent
        def view_template
          div(class: "p-6 border border-emerald-900 bg-black shadow-[0_0_20px_rgba(6,78,59,0.3)]") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6 flex items-center gap-2") do
              i(class: "ph ph-cpu")
              plain "Simulation Engine // What-If?"
            end
            
            form(action: helpers.simulate_api_v1_oracle_visions_path, method: "post", data: { turbo_frame: "simulation_results" }) do
              authenticity_token_input
              
              # Вибір контексту симуляції (Кластер)
              div(class: "mb-6") do
                label(class: "text-[9px] text-emerald-800 uppercase block mb-2") { "Target Sector" }
                select(name: "cluster_id", class: "w-full bg-zinc-950 border border-emerald-900 text-emerald-400 text-xs p-2 outline-none focus:border-emerald-500") do
                  Cluster.all.each do |cluster|
                    option(value: cluster.id) { "Sector: #{cluster.name}" }
                  end
                end
              end

              render_slider("Temp Offset (Δt)", "variables[temp_offset]", "-10", "10", "0")
              render_slider("Humidity Drop (%)", "variables[humidity_drop]", "-50", "0", "-5")
              render_slider("Sap Flow Bias", "variables[sap_bias]", "-20", "20", "0")

              button(type: "submit", class: "w-full mt-6 py-3 bg-emerald-950/40 border border-emerald-500 text-emerald-500 uppercase text-[10px] tracking-widest hover:bg-emerald-500 hover:text-black transition-all font-bold") do
                "Invoke Neural Simulation"
              end
            end
          end
        end

        private

        def render_slider(label, name, min, max, value)
          div(class: "mb-4 space-y-2") do
            div(class: "flex justify-between") do
              label(class: "text-[10px] text-gray-600 uppercase") { label }
              span(class: "text-[10px] font-mono text-emerald-500", data_simulation_target: "value") { value }
            end
            input(type: "range", name: name, min: min, max: max, value: value, 
                  class: "w-full accent-emerald-500 bg-emerald-950 h-1 rounded-full appearance-none cursor-pointer")
          end
        end

        def authenticity_token_input
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        end
      end
    end
  end
end
