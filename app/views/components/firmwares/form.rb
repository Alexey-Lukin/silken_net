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
          field_container(t("firmwares.form.version_label")) do
            f.text_field :version, class: input_classes, placeholder: t("firmwares.form.version_placeholder"), required: true
          end

          field_container(t("firmwares.form.target_label")) do
            f.select :target_hardware, [ [ t("firmwares.form.target_soldier"), "stm32_l0" ], [ t("firmwares.form.target_queen"), "esp32_s3" ] ], {}, class: input_classes
          end

          field_container(t("firmwares.form.binary_label")) do
            f.file_field :binary_file, class: "w-full text-gaia-text-muted text-tiny font-mono file:mr-4 file:py-2 file:px-4 file:border-0 file:bg-gaia-surface-sunken file:text-gaia-primary hover:file:bg-gaia-primary/20 cursor-pointer", required: true
          end

          field_container(t("firmwares.form.notes_label")) do
            f.text_area :notes, rows: 4, class: input_classes, placeholder: t("firmwares.form.notes_placeholder")
          end
        end

        div(class: "pt-10 border-t border-gaia-border") do
          f.submit t("firmwares.form.submit"), class: "w-full py-4 bg-gaia-primary/10 border border-gaia-primary text-gaia-primary uppercase text-xs tracking-[0.3em] hover:bg-gaia-primary hover:text-black transition-all cursor-pointer shadow-sm"
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
