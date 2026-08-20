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
          field_container(f, :version, t(".version_label")) do |aria|
            f.text_field :version, class: input_classes, placeholder: t(".version_placeholder"), required: true, **aria
          end

          # Колонка `target_hardware` не існує — форма роками слала ключ, якого модель
          # не має, тож кожен сабміт помирав на `ActiveModel::UnknownAttributeError`.
          # Значення беруться з allow-list моделі: рукописний перелік розійшовся б із
          # нею мовчки, як розійшлися MCU-мітки. Без `include_blank` свідомо — прошивка
          # без типу не гаситься релізом свого класу (`deploy_globally!` фільтрує по
          # ньому, а SQL NULL не дорівнює жодному значенню).
          field_container(f, :target_hardware_type, t(".target_label")) do |aria|
            f.select :target_hardware_type,
                     BioContractFirmware::HARDWARE_TYPES.map { |type| [ t(".target_#{type.downcase}"), type ] },
                     {}, class: input_classes, **aria
          end

          field_container(f, :binary_file, t(".binary_label")) do |aria|
            f.file_field :binary_file, class: "w-full text-gaia-text-muted text-tiny font-mono file:mr-4 file:py-2 file:px-4 file:border-0 file:bg-gaia-surface-sunken file:text-gaia-primary-strong hover:file:bg-gaia-primary/20 cursor-pointer", required: true, **aria
          end
        end

        div(class: "pt-10 border-t border-gaia-border") do
          f.submit t(".submit"), class: "w-full py-4 bg-gaia-primary/10 border border-gaia-primary-strong text-gaia-primary-strong uppercase text-xs tracking-[0.3em] hover:bg-gaia-primary hover:text-black transition-all cursor-pointer shadow-sm"
        end
      end
    end

    private

    # [UI.3] `form.label`, не голий `label`: той не має `for=`, тож підпис і поле
    # не звʼязані для AT, а клік по підпису не фокусує ввід. `id` дає білдер
    # (`scope: :firmware` → `firmware_version`). Класи ті самі — сусідній пін
    # звіряє саме їх.
    # [UI.3] Блок дістає ARIA-атрибути ПОЛЯ — інакше `aria-invalid` нікуди
    # поставити: контрол рендерить викликач, а не цей хелпер. Порожній хеш на
    # валідному полі, тож `**aria` у викликача безпечний завжди.
    def field_container(form, attribute, label_text, &block)
      div(class: "space-y-2") do
        form.label attribute, label_text, class: "text-mini uppercase tracking-widest text-gaia-label"
        yield(field_error_attrs(form, attribute))
        render_field_error(form, attribute)
      end
    end

    def input_classes
      "w-full bg-gaia-input-bg border border-gaia-input-border text-gaia-input-text p-3 font-mono text-xs focus-visible:border-gaia-primary-strong outline-none transition-all"
    end
  end
end
