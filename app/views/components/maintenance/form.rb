# SPDX-License-Identifier: AGPL-3.0-or-later
module Maintenance
  class Form < ApplicationComponent
    # @param record [MaintenanceRecord] the record to edit/create
    # @param existing_photos [Array<ActiveStorage::Blob>] pre-loaded first page of photos (max 6, eager-load in controller)
    # 🔴 [UI.6] `current_user:` з дефолтом `nil` — fail-CLOSED: компонент рендерить
    # ГЕЙТОВАНУ й НЕЗВОРОТНУ дію (кнопку видалення фотодоказу, `purge_later` у S3 —
    # [SEC.28]), а доти віддавав її літеральним `editable: true`, тобто не знав про
    # актора взагалі й не міг знати. Транзитивно це було безпечно (галерею дістають
    # лише `edit` і невдалий `update`, обидва за `authorize_record_mutation!`), але
    # безпека трималась на маршруті викликача, а не на власному контракті —
    # і саме таку залежність правило UI.5/UI.6 і забороняє.
    def initialize(record:, existing_photos: [], current_user: nil)
      @record = record
      @editing = @record.persisted?
      @existing_photos = existing_photos
      @current_user = current_user
    end

    def view_template
      div(class: "max-w-3xl mx-auto") do
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
            field_container(f, :maintainable_type, t(".target_type")) do |aria|
              f.select :maintainable_type, [ "Tree", "Gateway" ], {}, class: input_classes, **aria
            end
            field_container(f, :maintainable_id, t(".target_id")) do |aria|
              f.number_field :maintainable_id, class: input_classes, placeholder: "e.g. 42", **aria
            end
          end

          field_container(f, :ews_alert_id, t(".ews_association")) do |aria|
            f.number_field :ews_alert_id, class: input_classes,
                           placeholder: t(".ews_placeholder"), **aria
          end

          # --- РЯДОК 2: Action + Timestamp ---
          div(class: "grid grid-cols-2 gap-6") do
            field_container(f, :action_type, t(".action_type")) do |aria|
              # [I18N.1] Мітка — з дому, ЗНАЧЕННЯ лишається сирим токеном: у select'і
              # обидва роди вжитку стоять в одному літералі, і сплутати їх коштує
              # зламаного сабміту, а не англійського слова.
              f.select :action_type,
                MaintenanceRecord.action_types.keys.map { |k| [ MaintenanceRecord.action_type_label(k), k ] },
                { prompt: t(".action_prompt") },
                class: input_classes, **aria
            end
            field_container(f, :performed_at, t(".performed_at")) do |aria|
              f.datetime_local_field :performed_at,
                value: (@record.performed_at || Time.current).strftime("%Y-%m-%dT%H:%M"),
                class: input_classes, **aria
            end
          end

          # --- НОТАТКИ ---
          field_container(f, :notes, t(".notes")) do |aria|
            f.text_area :notes, rows: 4, class: input_classes,
                        placeholder: t(".notes_placeholder"), **aria
          end

          # -----------------------------------------------------------------------
          # OpEx ФІНАНСОВИЙ ОБЛІК (Series C)
          # -----------------------------------------------------------------------
          div(class: "border border-gaia-border p-4 space-y-4") do
            p(class: "text-mini uppercase tracking-widest text-gaia-text-muted mb-2") { t(".opex.heading") }
            div(class: "grid grid-cols-2 gap-6") do
              field_container(f, :labor_hours, t(".opex.labor_hours")) do |aria|
                f.number_field :labor_hours, step: 0.5, min: 0, class: input_classes,
                               placeholder: "e.g. 2.5", **aria
              end
              field_container(f, :parts_cost, t(".opex.parts_cost")) do |aria|
                f.number_field :parts_cost, step: 0.01, min: 0, class: input_classes,
                               placeholder: "e.g. 150.00", **aria
              end
            end
          end

          # -----------------------------------------------------------------------
          # GPS КООРДИНАТИ (Anti-Sofa-Repair Protocol)
          # -----------------------------------------------------------------------
          div(class: "border border-gaia-border p-4 space-y-4") do
            p(class: "text-mini uppercase tracking-widest text-gaia-text-muted mb-2") { t(".gps.heading") }
            div(class: "grid grid-cols-2 gap-6") do
              field_container(f, :latitude, t(".gps.latitude")) do |aria|
                f.number_field :latitude, step: 0.000001, class: input_classes,
                               placeholder: "49.428500", **aria
              end
              field_container(f, :longitude, t(".gps.longitude")) do |aria|
                f.number_field :longitude, step: 0.000001, class: input_classes,
                               placeholder: "32.062000", **aria
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
            field_container(f, :photos, t(".evidence.attach_photos")) do |aria|
              f.file_field :photos,
                multiple: true,
                accept: "image/jpeg,image/png,image/webp,image/heic,image/heif",
                direct_upload: true,
                class: "w-full bg-gaia-input-bg border border-gaia-input-border text-gaia-input-text p-3 font-mono text-xs " \
                       "file:mr-3 file:border file:border-gaia-border file:bg-gaia-surface-sunken " \
                       "file:text-gaia-primary file:text-mini file:uppercase file:px-3 file:py-1 " \
                       "focus-visible:border-gaia-primary outline-none transition-all", **aria
            end
          end

          # -----------------------------------------------------------------------
          # HARDWARE VERIFIED (тільки при редагуванні)
          # -----------------------------------------------------------------------
          if @editing
            div(class: "flex items-center gap-3") do
              f.check_box :hardware_verified,
                class: "h-4 w-4 border border-gaia-border bg-gaia-input-bg text-gaia-primary focus-visible:ring-0"
              # [UI.3] Через білдер, не голий `label(for: …)`: рукописний id тримався
              # на тому, що ім'я моделі не змінюється — а перевіряти це не було чим
              # (мутація «зламати for» лишала сюїту зеленою, бо пін на сироти-мітки
              # цієї спеки не мав узагалі; він приїхав тим самим ходом).
              f.label :hardware_verified,
                class: "text-mini uppercase tracking-widest text-gaia-text-muted cursor-pointer" do
                t(".hardware_verified")
              end
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
    # ✅ [UI.6] Тепер явний предикат замість літерала — форма питає ТУ САМУ модель, що
    # й `authorize_record_mutation!` (`MaintenanceRecord#mutable_by?`), тож право
    # більше не деривується з маршруту. Без актора (`nil`) галерея нередагована —
    # fail-closed, а не «як зазвичай».
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
          editable: @record.mutable_by?(@current_user)
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
    # [UI.3] Блок дістає ARIA-атрибути ПОЛЯ — інакше `aria-invalid` нікуди
    # поставити: контрол рендерить викликач, а не цей хелпер. Порожній хеш на
    # валідному полі, тож `**aria` у викликача безпечний завжди.
    def field_container(form, attribute, label_text, &)
      div(class: "space-y-2") do
        form.label attribute, label_text, class: "text-mini uppercase tracking-widest text-gaia-label"
        yield(field_error_attrs(form, attribute))
        render_field_error(form, attribute)
      end
    end

    def input_classes
      "w-full bg-gaia-input-bg border border-gaia-input-border text-gaia-input-text p-3 font-mono text-xs " \
      "focus-visible:border-gaia-primary focus-visible:ring-0 outline-none transition-all"
    end
  end
end
