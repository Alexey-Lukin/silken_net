module Views
  module Components
    module OracleVisions
      class SimulationPanel < ApplicationComponent
        def view_template
          div(class: "p-6 border border-emerald-900 bg-black") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Simulation Engine // What-If?" }
            
            form(action: helpers.simulate_api_v1_oracle_visions_path, method: "post", data: { turbo_frame: "simulation_results" }) do
              authenticity_token_input
              
              render_slider("Temp Offset", "variables[temp_offset]", "-10", "10", "0")
              render_slider("Humidity Drop", "variables[humidity_drop]", "-50", "0", "-5")

              button(type: "submit", class: "w-full mt-6 py-2 bg-emerald-900/20 border border-emerald-500 text-emerald-500 uppercase text-[10px] tracking-widest hover:bg-emerald-500 hover:text-black transition-all") do
                "Invoke Oracle Simulation"
              end
            end
          end
        end

        private

        def render_slider(label, name, min, max, value)
          div(class: "mb-4 space-y-2") do
            label(class: "text-[10px] text-gray-600 uppercase") { label }
            input(type: "range", name: name, min: min, max: max, value: value, class: "w-full accent-emerald-500 bg-emerald-950 h-1 rounded-full appearance-none")
          end
        end

        def authenticity_token_input
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        end
      end
    end
  end
end
