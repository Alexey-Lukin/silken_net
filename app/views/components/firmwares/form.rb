# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Firmwares
  class Form < ApplicationComponent
    def initialize(firmware:)
      @firmware = firmware
    end

    def view_template
      # 🔴 [SEC.25] `url:` і `scope:` тут ОБИДВА несучі, і без них сторінка віддавала
      # 500. `form_with(model:)` виводить і маршрут, і префікс параметрів із КЛАСУ
      # моделі, а `BioContractFirmware` розходиться з нашими іменами двічі:
      #   route_key  = `bio_contract_firmwares` → хелпера з такою назвою не існує
      #                (маршрут зареєстровано як `firmwares`) → NoMethodError → 500
      #   param_key  = `bio_contract_firmware`  → а контролер читає
      #                `params.require(:firmware)`, тобто форма слала б не в те гніздо
      # Сусідній `TreeFamilies::Form` живий саме тому, що там обидва імені збігаються
      # природно — тобто працездатність була збігом імен, а не властивістю патерну.
      form_with(model: @firmware, url: firmwares_path, scope: :firmware, multipart: true, class: "space-y-8 p-10 border border-gaia-border bg-gaia-surface shadow-sm dark:shadow-none") do |f|
        # Без `&.`: `firmware:` — обовʼязковий kwarg, а `errors` на AR-моделі не буває
        # nil, тож захисні гілки були б МЕРТВІ, не «нетестовані». (Сусідній
        # `Provisioning::New` тримає `&.` законно — там `device:` дефолтить у nil.)
        render Views::Shared::UI::ErrorSummary.new(messages: @firmware.errors.full_messages)

        div(class: "space-y-6") do
          field_container(t(".version_label")) do
            f.text_field :version, class: input_classes, placeholder: t(".version_placeholder"), required: true
          end

          field_container(t(".target_label")) do
            f.select :target_hardware, [ [ t(".target_soldier"), "stm32_l0" ], [ t(".target_queen"), "esp32_s3" ] ], {}, class: input_classes
          end

          field_container(t(".binary_label")) do
            f.file_field :binary_file, class: "w-full text-gaia-text-muted text-tiny font-mono file:mr-4 file:py-2 file:px-4 file:border-0 file:bg-gaia-surface-sunken file:text-gaia-primary hover:file:bg-gaia-primary/20 cursor-pointer", required: true
          end

          field_container(t(".notes_label")) do
            f.text_area :notes, rows: 4, class: input_classes, placeholder: t(".notes_placeholder")
          end
        end

        div(class: "pt-10 border-t border-gaia-border") do
          f.submit t(".submit"), class: "w-full py-4 bg-gaia-primary/10 border border-gaia-primary text-gaia-primary uppercase text-xs tracking-[0.3em] hover:bg-gaia-primary hover:text-black transition-all cursor-pointer shadow-sm"
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
