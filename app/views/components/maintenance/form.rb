module Views
  module Components
    module Maintenance
      class Form < ApplicationComponent
        def initialize(record:)
          @record = record
        end

        def view_template
          div(class: "max-w-2xl mx-auto animate-in zoom-in duration-500") do
            form_with(model: [:api, :v1, @record], class: "space-y-8 p-8 border border-emerald-900 bg-zinc-950") do |f|
              h3(class: "text-[10px] uppercase tracking-[0.5em] text-emerald-700 mb-8") { "Register Intervention Ritual" }

              div(class: "grid grid-cols-2 gap-6") do
                field_container("Target Type") do
                  f.select :maintainable_type, ["Tree", "Gateway"], {}, class: input_classes
                end
                field_container("Target ID") do
                  f.number_field :maintainable_id, class: input_classes, placeholder: "e.g. 42"
                end
              end

              field_container("EWS Alert Association (Optional)") do
                f.number_field :ews_alert_id, class: input_classes, placeholder: "ID of the threat being resolved"
              end

              field_container("Action Type") do
                f.select :action_type, ["repair", "inspection", "battery_swap", "firmware_check", "other"], {}, class: input_classes
              end

              field_container("Notes (Observations from the Field)") do
                f.text_area :notes, rows: 4, class: input_classes, placeholder: "Describe the state of the biogenic anchor..."
              end

              div(class: "pt-6") do
                f.submit "Commit to Matrix", class: "w-full py-4 bg-emerald-900/20 border border-emerald-500 text-emerald-500 uppercase text-xs tracking-widest hover:bg-emerald-500 hover:text-black transition-all cursor-pointer shadow-[0_0_20px_rgba(16,185,129,0.2)]"
              end
            end
          end
        end

        private

        def field_container(label, &block)
          div(class: "space-y-2") do
            label(class: "text-[9px] uppercase tracking-widest text-gray-600") { label }
            yield
          end
        end

        def input_classes
          "w-full bg-black border border-emerald-900/50 text-emerald-100 p-3 font-mono text-xs focus:border-emerald-500 focus:ring-0 outline-none transition-all"
        end
      end
    end
  end
end
