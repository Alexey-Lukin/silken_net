# frozen_string_literal: true

module Firmwares
  class Form < ApplicationComponent
    def initialize(firmware:)
      @firmware = firmware
    end

    def view_template
      # Тільки логіка взаємодії з моделлю
      form_with(model: [ :api, :v1, @firmware ], multipart: true, class: "space-y-8 p-10 border border-gaia-border bg-gaia-surface shadow-sm dark:shadow-none") do |f|
        div(class: "space-y-6") do
          field_container("Evolution Version") do
            f.text_field :version, class: input_classes, placeholder: "e.g. 1.4.2", required: true
          end

          field_container("Target Hardware Architecture") do
            f.select :target_hardware, [ [ "STM32-L0 (Soldier)", "stm32_l0" ], [ "ESP32-S3 (Queen)", "esp32_s3" ] ], {}, class: input_classes
          end

          field_container("Binary Artifact (.bin)") do
            f.file_field :binary_file, class: "w-full text-gaia-text-muted text-tiny font-mono file:mr-4 file:py-2 file:px-4 file:border-0 file:bg-gaia-surface-alt file:text-gaia-primary hover:file:bg-gaia-primary/20 cursor-pointer", required: true
          end

          field_container("Release Notes / Logical Changes") do
            f.text_area :notes, rows: 4, class: input_classes, placeholder: "Describing the changes in the biogenic firmware..."
          end
        end

        div(class: "pt-10 border-t border-gaia-border") do
          f.submit "COMMIT EVOLUTION", class: "w-full py-4 bg-gaia-primary/10 border border-gaia-primary text-gaia-primary uppercase text-xs tracking-[0.3em] hover:bg-gaia-primary hover:text-black transition-all cursor-pointer shadow-sm"
        end
      end
    end

    private

    def field_container(label, &block)
      div(class: "space-y-2") do
        label(class: "text-mini uppercase tracking-widest text-gaia-label") { label }
        yield
      end
    end

    def input_classes
      "w-full bg-gaia-input-bg border border-gaia-input-border text-gaia-input-text p-3 font-mono text-xs focus-visible:border-gaia-primary outline-none transition-all"
    end
  end
end
