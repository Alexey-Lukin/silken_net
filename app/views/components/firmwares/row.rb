# app/views/components/firmwares/row.rb
module Views
  module Components
    module Firmwares
      class Row < ApplicationComponent
        def initialize(firmware:)
          @firmware = firmware
        end

        def view_template
          tr(class: "hover:bg-emerald-950/10 transition-colors") do
            td(class: "p-4 text-emerald-100 font-bold") { "v#{@firmware.version}" }
            td(class: "p-4 text-emerald-600") { @firmware.target_hardware.upcase }
            td(class: "p-4 text-gray-600") { @firmware.checksum&.first(12) || "N/A" }
            td(class: "p-4 text-gray-500") { @firmware.created_at.strftime("%d.%m.%y") }
            td(class: "p-4 text-right") do
              # Форма для наказу оновлення через Turbo
              form(action: helpers.deploy_api_v1_firmware_path(@firmware), method: "post") do
                authenticity_token_input
                button(
                  type: "submit",
                  class: "text-emerald-500 hover:text-white border border-emerald-900 hover:border-emerald-500 px-4 py-1 uppercase text-[9px] tracking-tighter transition-all"
                ) { "Order Evolution" }
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
