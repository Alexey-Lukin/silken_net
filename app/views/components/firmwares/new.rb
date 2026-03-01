# frozen_string_literal: true

module Views
  module Components
    module Firmwares
      class New < ApplicationComponent
        def initialize(firmware:)
          @firmware = firmware
        end

        def view_template
          div(class: "max-w-2xl mx-auto animate-in zoom-in duration-500") do
            # Заголовок сторінки (Презентаційний шар)
            header_section
            
            # Виклик атомарного компонента форми
            render Views::Components::Firmwares::Form.new(firmware: @firmware)
          end
        end

        private

        def header_section
          div(class: "text-center mb-10") do
            h2(class: "text-2xl font-extralight text-emerald-400 tracking-widest uppercase") { "New Code Injection" }
            p(class: "text-[10px] text-emerald-900 uppercase mt-2 tracking-[0.5em]") { "Prepare the binary artifact for OTA deployment" }
          end
        end
      end
    end
  end
end
