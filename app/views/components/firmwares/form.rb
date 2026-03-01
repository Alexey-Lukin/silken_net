# frozen_string_literal: true

module Views
  module Components
    module Firmwares
      class Form < ApplicationComponent
        def initialize(firmware:)
          @firmware = firmware
        end

        def view_template
          # Тільки логіка взаємодії з моделлю
          form_with(model: [:api, :v1, @firmware], multipart: true, class: "space-y-8 p-10 border border-emerald-900 bg-black/80 shadow-2xl backdrop-blur-md") do |f|
            
            div(class: "space-y-6") do
              field_container("Evolution Version") do
                f.text_field :version, class: input_classes, placeholder: "e.g. 1.4.2", required: true
              end

              field_container("Target Hardware Architecture") do
                f.select :target_hardware, [["STM32-L0 (Soldier)", "stm32_l0"], ["ESP32-S3 (Queen)", "esp32_s3"]], {}, class: input_classes
              end

              field_container("Binary Artifact (.bin)") do
                f.file_field :binary_file, class: "w-full text-emerald-900 text-[10px] font-mono file:mr-4 file:py-2 file:px-4 file:border-0 file:bg-emerald-900/20 file:text-emerald-500 hover:file:bg-emerald-900/40 cursor-pointer", required: true
              end

              field_container("Release Notes / Logical Changes") do
                f.text_area :notes, rows: 4, class: input_classes, placeholder: "Describing the changes in the biogenic firmware..."
              end
            end

            div(class: "pt-10 border-t border-emerald-900/30") do
              f.submit "COMMIT EVOLUTION", class: "w-full py-4 bg-emerald-500/10 border border-emerald-500 text-emerald-500 uppercase text-xs tracking-[0.3em] hover:bg-emerald-500 hover:text-black transition-all cursor-pointer shadow-[0_0_30px_rgba(16,185,129,0.1)]"
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
          "w-full bg-zinc-950 border border-emerald-900/50 text-emerald-100 p-3 font-mono text-xs focus:border-emerald-500 outline-none transition-all"
        end
      end
    end
  end
end
