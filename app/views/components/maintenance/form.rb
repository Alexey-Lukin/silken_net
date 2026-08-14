# SPDX-License-Identifier: AGPL-3.0-or-later
module Maintenance
  class Form < ApplicationComponent
    # @param record [MaintenanceRecord] the record to edit/create
    # @param existing_photos [Array<ActiveStorage::Blob>] pre-loaded first page of photos (max 6, eager-load in controller)
    def initialize(record:, existing_photos: [])
      @record = record
      @editing = @record.persisted?
      @existing_photos = existing_photos
    end

    def view_template
      div(class: "max-w-3xl mx-auto animate-in zoom-in duration-500") do
        render_existing_photos

        form_with(
          model: @record,
          multipart: true,
          class: "space-y-8 p-8 border border-gaia-border bg-gaia-surface shadow-sm dark:shadow-none"
        ) do |f|
          render_form_header

          # [SEC.25] Зведення стоїть ПЕРЕД полями. Доти воно рендерилось останнім —
          # нижче кнопки «Update», тобто причина відмови лежала за межами екрана
          # рівно тоді, коли людина дивиться на кнопку, яка щойно не спрацювала.
          render Views::Shared::UI::ErrorSummary.new(messages: @record.errors.full_messages)

          # --- РЯДОК 1: Target + EWS ---
          div(class: "grid grid-cols-2 gap-6") do
            field_container(f, :maintainable_type, t(".target_type")) do
              f.select :maintainable_type, [ "Tree", "Gateway" ], {}, class: input_classes
            end
            field_container(f, :maintainable_id, t(".target_id")) do
              f.number_field :maintainable_id, class: input_classes, placeholder: "e.g. 42"
            end
          end

          field_container(f, :ews_alert_id, t(".ews_association")) do
            f.number_field :ews_alert_id, class: input_classes,
                           placeholder: t(".ews_placeholder")
          end

          # --- РЯДОК 2: Action + Timestamp ---
          div(class: "grid grid-cols-2 gap-6") do
            field_container(f, :action_type, t(".action_type")) do
              f.select :action_type,
                MaintenanceRecord.action_types.keys.map { |k| [ k.humanize, k ] },
                { prompt: t(".action_prompt") },
                class: input_classes
            end
            field_container(f, :performed_at, t(".performed_at")) do
              f.datetime_local_field :performed_at,
                value: (@record.performed_at || Time.current).strftime("%Y-%m-%dT%H:%M"),
                class: input_classes
            end
          end

          # --- НОТАТКИ ---
          field_container(f, :notes, t(".notes")) do
            f.text_area :notes, rows: 4, class: input_classes,
                        placeholder: t(".notes_placeholder")
          end

          # -----------------------------------------------------------------------
          # OpEx ФІНАНСОВИЙ ОБЛІК (Series C)
          # -----------------------------------------------------------------------
          div(class: "border border-gaia-border p-4 space-y-4") do
            p(class: "text-mini uppercase tracking-widest text-gaia-text-muted mb-2") { t(".opex.heading") }
            div(class: "grid grid-cols-2 gap-6") do
              field_container(f, :labor_hours, t(".opex.labor_hours")) do
                f.number_field :labor_hours, step: 0.5, min: 0, class: input_classes,
                               placeholder: "e.g. 2.5"
              end
              field_container(f, :parts_cost, t(".opex.parts_cost")) do
                f.number_field :parts_cost, step: 0.01, min: 0, class: input_classes,
                               placeholder: "e.g. 150.00"
              end
            end
          end

          # -----------------------------------------------------------------------
          # GPS КООРДИНАТИ (Anti-Sofa-Repair Protocol)
          # -----------------------------------------------------------------------
          div(class: "border border-gaia-border p-4 space-y-4") do
            p(class: "text-mini uppercase tracking-widest text-gaia-text-muted mb-2") { t(".gps.heading") }
            div(class: "grid grid-cols-2 gap-6") do
              field_container(f, :latitude, t(".gps.latitude")) do
                f.number_field :latitude, step: 0.000001, class: input_classes,
                               placeholder: "49.428500"
              end
              field_container(f, :longitude, t(".gps.longitude")) do
                f.number_field :longitude, step: 0.000001, class: input_classes,
                               placeholder: "32.062000"
              end
            end
          end

          # -----------------------------------------------------------------------
          # ФОТОДОКАЗИ (Evidence Protocol — Trust Protocol)
          # -----------------------------------------------------------------------
          div(
            class: "border border-gaia-border p-4 space-y-4",
            id: "photo_upload_section"
          ) do
            p(class: "text-mini uppercase tracking-widest text-gaia-text-muted") { t(".evidence.heading") }
            p(class: "text-micro text-gaia-text-muted mb-3") do
              t(".evidence.hint")
            end

            # Direct upload — файли йдуть напряму на S3, не через Rails
            field_container(f, :photos, t(".evidence.attach_photos")) do
              f.file_field :photos,
                multiple: true,
                accept: "image/jpeg,image/png,image/webp,image/heic,image/heif",
                direct_upload: true,
                class: "w-full bg-gaia-input-bg border border-gaia-input-border text-gaia-input-text p-3 font-mono text-xs " \
                       "file:mr-3 file:border file:border-gaia-border file:bg-gaia-surface-sunken " \
                       "file:text-gaia-primary file:text-mini file:uppercase file:px-3 file:py-1 " \
                       "focus-visible:border-gaia-primary outline-none transition-all"
            end

            # Direct upload progress bar (активується activestorage JS)
            div(class: "hidden mt-2",
              id: "direct-upload-progress",
              data: { "direct-upload-progress-bar": "" }
            ) do
              div(class: "h-1 bg-gaia-surface-sunken overflow-hidden") do
                div(class: "h-full bg-gaia-primary transition-all", style: "width:0%", id: "direct-upload-bar")
              end
            end
          end

          # -----------------------------------------------------------------------
          # HARDWARE VERIFIED (тільки при редагуванні)
          # -----------------------------------------------------------------------
          if @editing
            div(class: "flex items-center gap-3") do
              f.check_box :hardware_verified,
                class: "h-4 w-4 border border-gaia-border bg-gaia-input-bg text-gaia-primary focus-visible:ring-0"
              label(
                for: "maintenance_record_hardware_verified",
                class: "text-mini uppercase tracking-widest text-gaia-text-muted cursor-pointer"
              ) { t(".hardware_verified") }
            end
          end

          # --- SUBMIT ---
          div(class: "pt-6 flex items-center gap-4") do
            f.submit(
              @editing ? t(".submit.update") : t(".submit.create"),
              class: "flex-1 py-4 bg-gaia-primary/10 border border-gaia-primary text-gaia-primary " \
                     "uppercase text-xs tracking-widest hover:bg-gaia-primary hover:text-black " \
                     "transition-all cursor-pointer shadow-sm"
            )
            if @editing
              a(
                href: maintenance_record_path(@record),
                class: "px-4 py-4 border border-gaia-border text-gaia-text-muted hover:text-gaia-primary " \
                       "uppercase text-mini tracking-widest transition-all"
              ) { t(".cancel") }
            end
          end
        end
      end
    end

    private

    # Галерея стоїть ПОЗА `form_with`, і це несуче, а не компонування.
    #
    # Кожна картка фото рендерить `button_to`, тобто `<form>` усередині `<form>`.
    # HTML такого не допускає: парсер викидає внутрішню форму, а її дітей —
    # `_method=delete` і токен — переносить у ЗОВНІШНЮ. Далі зовнішня форма несе
    # `_method` двічі («patch», «delete»), і при Rack-парсингу виграє останнє.
    # Наслідок був подвійний: кнопка «Update» летіла в `DELETE /maintenance_records/:id`,
    # якого не існує (`only:` без `:destroy`) — тобто форма редагування запису
    # З БУДЬ-ЯКИМ ФОТО не зберігалась узагалі, — а «×» сабмітив зовнішню форму
    # замість власної. Виміряно spec-сумісним HTML5-парсером, не виведено. [UI.7]
    #
    # ⚠️ `editable: true` літералом безпечний ТРАНЗИТИВНО, а не сам собою: галерею
    # дістають лише `edit` і невдалий `update`, обидва за `authorize_record_mutation!`
    # (= `mutable_by?`). Незахищеного шляху рендеру немає; вирівняти форму на явний
    # предикат, як у `Maintenance::Show`, — гігієна [UI.6], не діра.
    def render_existing_photos
      return unless @editing && @existing_photos.any?

      div(class: "mb-8") do
        render Maintenance::PhotoGallery.new(
          record: @record,
          photos: @existing_photos,
          # `Pagy::Offset`, а не `Pagy` — у 43.x базовий клас конструктора не має
          # (`Pagy.new` кидає ArgumentError), тож стара форма валила цю гілку 500-ю
          # на кожному записі з фото. Сусід `TreeChronicleService` уже на новій.
          pagy: Pagy::Offset.new(count: @existing_photos.size, limit: PhotoGallery::PHOTOS_PER_PAGE, page: 1),
          editable: true
        )
      end
    end

    def render_form_header
      div(class: "flex justify-between items-center mb-2") do
        h3(class: "text-tiny uppercase tracking-[0.5em] text-gaia-text-muted") do
          @editing ? t(".header.edit", id: @record.id) : t(".header.new")
        end
        span(class: "text-micro text-gaia-text-muted font-mono") { @record.maintainable_type&.upcase || "PENDING" }
      end
      hr(class: "border-gaia-border mb-6")
    end

    # [UI.3] `form.label`, не голий `label` — той не має `for=`, тож AT не звʼязує
    # підпис із полем, а клік по підпису не фокусує ввід. `id` уже генерує білдер
    # (`form_with model:` → `maintenance_record_*`), тож уся робота — передати
    # атрибут. ⊕ Чекбокс `hardware_verified` нижче свідомо лишається на голому
    # `label(for: …)`: він рахує id РУКАМИ, і саме той рукописний звʼязок ця
    # міграція існує щоб усунути — але він поза `field_container`, тож іде
    # окремим ходом разом із рештою периметра.
    def field_container(form, attribute, label_text, &)
      div(class: "space-y-2") do
        form.label attribute, label_text, class: "text-mini uppercase tracking-widest text-gaia-label"
        yield
      end
    end

    def input_classes
      "w-full bg-gaia-input-bg border border-gaia-input-border text-gaia-input-text p-3 font-mono text-xs " \
      "focus-visible:border-gaia-primary focus-visible:ring-0 outline-none transition-all"
    end
  end
end
