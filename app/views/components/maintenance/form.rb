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
        form_with(
          model: [ :api, :v1, @record ],
          multipart: true,
          class: "space-y-8 p-8 border border-gaia-border bg-gaia-surface shadow-sm dark:shadow-none"
        ) do |f|
          render_form_header(f)

          # --- РЯДОК 1: Target + EWS ---
          div(class: "grid grid-cols-2 gap-6") do
            field_container(t(".target_type")) do
              f.select :maintainable_type, [ "Tree", "Gateway" ], {}, class: input_classes
            end
            field_container(t(".target_id")) do
              f.number_field :maintainable_id, class: input_classes, placeholder: "e.g. 42"
            end
          end

          field_container(t(".ews_association")) do
            f.number_field :ews_alert_id, class: input_classes,
                           placeholder: t(".ews_placeholder")
          end

          # --- РЯДОК 2: Action + Timestamp ---
          div(class: "grid grid-cols-2 gap-6") do
            field_container(t(".action_type")) do
              f.select :action_type,
                MaintenanceRecord.action_types.keys.map { |k| [ k.humanize, k ] },
                { prompt: t(".action_prompt") },
                class: input_classes,
                data: { action: "change->maintenance-form#togglePhotoRequired" }
            end
            field_container(t(".performed_at")) do
              f.datetime_local_field :performed_at,
                value: (@record.performed_at || Time.current).strftime("%Y-%m-%dT%H:%M"),
                class: input_classes
            end
          end

          # --- НОТАТКИ ---
          field_container(t(".notes")) do
            f.text_area :notes, rows: 4, class: input_classes,
                        placeholder: t(".notes_placeholder")
          end

          # -----------------------------------------------------------------------
          # OpEx ФІНАНСОВИЙ ОБЛІК (Series C)
          # -----------------------------------------------------------------------
          div(class: "border border-gaia-border p-4 space-y-4") do
            p(class: "text-mini uppercase tracking-widest text-gaia-text-muted mb-2") { t(".opex.heading") }
            div(class: "grid grid-cols-2 gap-6") do
              field_container(t(".opex.labor_hours")) do
                f.number_field :labor_hours, step: 0.5, min: 0, class: input_classes,
                               placeholder: "e.g. 2.5"
              end
              field_container(t(".opex.parts_cost")) do
                f.number_field :parts_cost, step: 0.01, min: 0, class: input_classes,
                               placeholder: "e.g. 150.00"
              end
            end
          end

          # -----------------------------------------------------------------------
          # GPS КООРДИНАТИ (Anti-Sofa-Repair Protocol)
          # -----------------------------------------------------------------------
          div(class: "border border-gaia-border p-4 space-y-4") do
            div(class: "flex justify-between items-center mb-2") do
              p(class: "text-mini uppercase tracking-widest text-gaia-text-muted") { t(".gps.heading") }
              button(
                type: "button",
                class: "text-micro border border-gaia-border text-gaia-text-muted px-2 py-1 hover:border-gaia-primary hover:text-gaia-primary transition-all uppercase",
                data: { action: "click->maintenance-form#captureGPS" }
              ) { t(".gps.capture") }
            end
            div(class: "grid grid-cols-2 gap-6") do
              field_container(t(".gps.latitude")) do
                f.number_field :latitude, step: 0.000001, class: input_classes,
                               placeholder: "49.428500", id: "record_latitude"
              end
              field_container(t(".gps.longitude")) do
                f.number_field :longitude, step: 0.000001, class: input_classes,
                               placeholder: "32.062000", id: "record_longitude"
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

            # Існуючі фото при редагуванні (перша сторінка, без load more в формі)
            if @editing && @existing_photos.any?
              pagy   = Pagy.new(count: @existing_photos.size, items: 6, page: 1)
              render Maintenance::PhotoGallery.new(
                record: @record, photos: @existing_photos, pagy: pagy, editable: true
              )
              div(class: "mt-3")
            end

            # Direct upload — файли йдуть напряму на S3, не через Rails
            field_container(t(".evidence.attach_photos")) do
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
                href: api_v1_maintenance_record_path(@record),
                class: "px-4 py-4 border border-gaia-border text-gaia-text-muted hover:text-gaia-primary " \
                       "uppercase text-mini tracking-widest transition-all"
              ) { t(".cancel") }
            end
          end

          render_errors if @record.errors.any?
        end
      end
    end

    private

    def render_form_header(f)
      div(class: "flex justify-between items-center mb-2") do
        h3(class: "text-tiny uppercase tracking-[0.5em] text-gaia-text-muted") do
          @editing ? t(".header.edit", id: @record.id) : t(".header.new")
        end
        span(class: "text-micro text-gaia-text-muted font-mono") { @record.maintainable_type&.upcase || "PENDING" }
      end
      hr(class: "border-gaia-border mb-6")
    end

    def render_errors
      div(class: "mt-6 p-4 border border-status-danger-accent bg-status-danger") do
        p(class: "text-mini uppercase tracking-widest text-status-danger-text mb-2") { t(".errors.heading") }
        ul(class: "space-y-1") do
          @record.errors.full_messages.each do |msg|
            li(class: "text-tiny text-status-danger-accent font-mono") { "× #{msg}" }
          end
        end
      end
    end

    def field_container(label, &)
      div(class: "space-y-2") do
        label(class: "text-mini uppercase tracking-widest text-gaia-label") { label }
        yield
      end
    end

    def input_classes
      "w-full bg-gaia-input-bg border border-gaia-input-border text-gaia-input-text p-3 font-mono text-xs " \
      "focus-visible:border-gaia-primary focus-visible:ring-0 outline-none transition-all"
    end
  end
end
