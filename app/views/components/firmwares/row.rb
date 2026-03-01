# frozen_string_literal: true

module Views
  module Components
    module Firmwares
      class Row < ApplicationComponent
        def initialize(firmware:)
          @firmware = firmware
        end

        def view_template
          tr(class: "hover:bg-emerald-950/10 transition-colors group") do
            td(class: "p-4 text-emerald-100 font-bold font-mono") { "v#{@firmware.version}" }
            td(class: "p-4 text-emerald-600 uppercase font-mono text-[10px]") { @firmware.target_hardware }
            td(class: "p-4 text-gray-600 font-mono text-[10px]") { @firmware.checksum&.first(16) || "N/A" }
            td(class: "p-4 text-gray-500 font-mono text-[10px]") { @firmware.created_at.strftime("%d.%m.%y // %H:%M") }
            
            td(class: "p-4 text-right") do
              # Форма для ініціації OTA оновлення
              form(action: helpers.deploy_api_v1_firmware_path(@firmware), method: "post") do
                authenticity_token_input
                button(
                  type: "submit",
                  class: "text-emerald-500 hover:text-white border border-emerald-900 hover:border-emerald-500 px-4 py-1 uppercase text-[9px] tracking-widest transition-all group-hover:shadow-[0_0_10px_rgba(16,185,129,0.2)]",
                  data: { turbo_confirm: "Initiate evolution to v#{@firmware.version} for the selected hardware?" }
                ) { "Order Evolution →" }
              end
            end
          end
        end

        private

        def authenticity_token_input
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        end
      end
    end
  end
end
