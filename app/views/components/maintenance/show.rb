# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Maintenance
  class Show < ApplicationComponent
    # [UI.6] `current_user` — лише для видимості МУТАЦІЙНИХ дій. Сторінку запису бачить
    # будь-який форестер організації (`show` не гейтований), а `verify`/`edit` стоять за
    # `authorize_record_mutation!` — тобто гард ГЛИБШЕ за дію, якою сторінка відкривається.
    # Доти всі чотири кнопки рендерились кожному глядачеві.
    #
    # Дефолт `nil` fail-CLOSED, як у `Navigation::Sidebar` (`04_04 §6.4`). Наслідок для
    # тестів: негативний приклад тут СЛІПИЙ до забутої проводки (без актора кнопки
    # сховані від усіх), тож проводку стереже позитивний request-пін, не компонентний.
    def initialize(record:, photos:, pagy_photos:, current_user: nil)
      @record       = record
      @user         = record.user
      @photos       = photos
      @pagy_photos  = pagy_photos
      @current_user = current_user
    end

    def view_template
      div(class: "space-y-8") do
        render_header
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-8") do
            render_evidence_gallery
            render_notes_panel
            render_cost_breakdown
          end
          div(class: "space-y-8") do
            render_metadata_panel
            render_gps_panel
            render_hardware_panel
          end
        end
      end
    end

    private

    # [UI.6] Диспетчер видимості, а не друге місце, де живе правило: єдине джерело —
    # `MaintenanceRecord#mutable_by?`, той самий предикат, що читає гард контролера.
    # Інакше UI став би другим домом формули «автор-або-admin» і розійшовся б із гардом
    # тихо (кнопка є → 403, або кнопки нема → людина не може зробити те, на що має право).
    def mutable?
      @record.mutable_by?(@current_user)
    end

    # =========================================================================
    # HEADER
    # =========================================================================
    def render_header
      div(class: "flex flex-col md:flex-row justify-between items-start md:items-center " \
                 "p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[80px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") do
          @record.action_type_label.upcase
        end

        div do
          h2(class: "text-3xl font-extralight tracking-tighter text-emerald-400") do
            "Record // ##{@record.id}"
          end
          div(class: "flex flex-wrap items-center gap-3 mt-2") do
            action_badge(@record.action_type)
            hardware_badge(@record.hardware_verified)
            span(class: "text-mini text-gaia-text-muted font-mono") do
              @record.performed_at&.strftime("%d.%m.%Y // %H:%M UTC")
            end
          end
        end

        div(class: "mt-6 md:mt-0 flex items-center gap-4") do
          a(
            href: new_maintenance_record_path(
              maintainable_type: @record.maintainable_type,
              maintainable_id: @record.maintainable_id
            ),
            class: "px-4 py-2 border border-emerald-800 text-gaia-primary-strong hover:border-emerald-500 " \
                   "hover:text-emerald-500 transition-all uppercase text-mini tracking-widest " \
                   "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
          ) { t(".header.new_record") }

          if !@record.hardware_verified && mutable?
            button_to(
              t(".header.verify_hardware"),
              verify_maintenance_record_path(@record),
              method: :patch,
              class: "px-4 py-2 border border-status-warning text-status-warning-text hover:bg-status-warning " \
                     "hover:text-black transition-all uppercase text-mini tracking-widest " \
                     "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
              data: { turbo_confirm: t(".header.verify_confirm", id: @record.id) }
            )
          end
        end
      end
    end

    # =========================================================================
    # EVIDENCE GALLERY
    # =========================================================================
    def render_evidence_gallery
      div(class: "p-8 border border-emerald-900 bg-zinc-950") do
        h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-6") { t(".evidence.heading") }

        if @pagy_photos.count > 0
          # `editable:` — не оформлення: воно вмикає кнопку видалення фотодоказу, дію
          # за тим самим гардом «автор-або-admin». Доти стояло літеральне `true`, тож
          # «×» бачив і МІГ натиснути кожен форестер організації.
          render Maintenance::PhotoGallery.new(
            record: @record, photos: @photos, pagy: @pagy_photos, editable: mutable?
          )
        else
          render_no_photos_placeholder
        end
      end
    end

    def render_no_photos_placeholder
      div(class: "border border-dashed border-emerald-900/40 p-10 text-center") do
        p(class: "text-gaia-text-muted uppercase tracking-widest text-tiny") { t(".evidence.no_photos") }
        if %w[repair installation].include?(@record.action_type)
          p(class: "text-red-800 text-mini mt-2 font-mono") do
            t(".evidence.trust_protocol", action_type: @record.action_type_label)
          end
        end
        if mutable?
          a(
            href: edit_maintenance_record_path(@record),
            class: "inline-block mt-4 px-4 py-2 border border-emerald-900 text-gaia-primary-strong " \
                   "hover:border-emerald-500 hover:text-emerald-500 uppercase text-mini tracking-widest transition-all " \
                   "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
          ) { t(".evidence.attach") }
        end
      end
    end

    # =========================================================================
    # NOTES
    # =========================================================================
    def render_notes_panel
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".notes.heading") }
        p(class: "text-sm text-gaia-text font-mono leading-relaxed whitespace-pre-wrap") { @record.notes }
      end
    end

    # =========================================================================
    # COST BREAKDOWN (OpEx Series C)
    # =========================================================================
    def render_cost_breakdown
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-6") { t(".cost.heading") }

        # 🔴 [ARCH.103] Асиметрія стояла в ОДНОМУ РЯДКУ, і саме тому пережила всі
        # проходи класу: той самий тернар `@record.labor_hours ?` друкував чесне
        # «—» у ПІДПИСІ й вигаданий `$0.00` у сусідній комірці. Тобто картка сама
        # зізнавалась, що виміру немає, і поруч називала його число.
        # ⚠️ Нуль тут не нейтральний у ЖОДЕН бік: явно введений `0` — законний
        # вимір «безкоштовний візит», тож глушити його не можна; підставлений `0`
        # на порожньому полі — фабрикація. Розрізняє їх лише `nil`, тому всі три
        # картки читають саме його, а не «чи значення додатне».
        div(class: "grid grid-cols-3 gap-6") do
          cost_card(
            t(".cost.labor_label"),
            @record.labor_hours ? "#{@record.labor_hours}h × $#{MaintenanceRecord::LABOR_RATE_PER_HOUR}" : t("ui.measurement.not_measured"),
            money_or_unmeasured(@record.labor_hours && @record.labor_hours.to_f * MaintenanceRecord::LABOR_RATE_PER_HOUR)
          )
          cost_card(
            t(".cost.parts_label"),
            t(".cost.parts_sub"),
            money_or_unmeasured(@record.parts_cost)
          )
          cost_card(t(".cost.total_label"), t(".cost.total_sub"), money_or_unmeasured(@record.total_cost), highlight: true)
        end
      end
    end

    # [ARCH.103] Дім рішення про порожнечу для грошових комірок цієї сторінки.
    # Власний хелпер потрібен лише тому, що одиниця тут ПРЕФІКСНА (`$` перед
    # числом), тож `measured_value` з його постфіксною формою не підходить;
    # спільним лишається саме рішення — `nil` друкує `ui.measurement.not_measured`,
    # той самий ключ, що й на сенсорних величинах.
    def money_or_unmeasured(value)
      return t("ui.measurement.not_measured") if value.nil?

      "$#{formatted_amount(value)}"
    end

    def cost_card(label, sub, value, highlight: false)
      div(class: "p-4 border border-emerald-900/40 bg-zinc-950") do
        p(class: "text-mini uppercase tracking-widest text-gaia-text-muted") { label }
        p(class: "text-micro text-gaia-text-subtle mt-1 mb-3") { sub }
        span(class: tokens("text-2xl font-light", "text-gaia-primary-strong": highlight, "text-gaia-text-strong": !highlight)) { value }
      end
    end

    # =========================================================================
    # METADATA
    # =========================================================================
    def render_metadata_panel
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".metadata.heading") }

        div(class: "space-y-3 text-tiny font-mono") do
          meta_row(t(".metadata.technician"), "#{@user&.first_name} #{@user&.last_name}")
          # [I18N.1] `role_label`, не сирий enum: мітка поруч ПЕРЕКЛАДЕНА, тож
          # сире значення давало локалізований підпис із англійським токеном
          # у кожній із чотирьох мов. Дім деривації — `User::ROLE_LABEL_SCOPE`.
          meta_row(t(".metadata.role"), @user&.role_label&.upcase)
          meta_row(t(".metadata.target"), "#{@record.maintainable_type} // #{@record.maintainable&.display_identifier || '—'}")
          meta_row(t(".metadata.action"), @record.action_type_label.upcase)
          meta_row(t(".metadata.photos"), @pagy_photos.count.to_s)
          if @record.ews_alert_id
            meta_row(t(".metadata.ews_alert"), "##{@record.ews_alert_id}")
          end
          meta_row(t(".metadata.created"), @record.created_at&.strftime("%d.%m.%Y %H:%M"))
          meta_row(t(".metadata.updated"), @record.updated_at&.strftime("%d.%m.%Y %H:%M"))
        end

        if mutable?
          div(class: "pt-4 border-t border-emerald-900/30") do
            a(
              href: edit_maintenance_record_path(@record),
              class: "block w-full text-center py-2 border border-emerald-900 text-mini uppercase " \
                     "text-gaia-primary-strong hover:border-emerald-500 hover:text-emerald-500 transition-all " \
                     "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
            ) { t(".edit") }
          end
        end
      end
    end

    # =========================================================================
    # GPS PANEL (Anti-Sofa-Repair)
    # =========================================================================
    def render_gps_panel
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".gps.heading") }

        if @record.latitude.present? && @record.longitude.present?
          div(class: "space-y-3 text-tiny font-mono") do
            meta_row(t(".gps.lat"), @record.latitude.to_s)
            meta_row(t(".gps.lng"), @record.longitude.to_s)
            render_gps_drift_check
          end

          a(
            href: "https://www.google.com/maps?q=#{@record.latitude},#{@record.longitude}",
            target: "_blank",
            class: "block mt-4 text-center p-2 border border-emerald-800 text-emerald-600 " \
                   "hover:bg-emerald-900 hover:text-white transition-all uppercase text-mini " \
                   "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
          ) { t(".gps.locate") }
        else
          p(class: "text-gaia-text-muted text-mini uppercase tracking-widest") { t(".gps.no_gps") }
          p(class: "text-gaia-text-subtle text-micro mt-1") { t(".gps.no_gps_sub") }
        end
      end
    end

    def render_gps_drift_check
      # Порівнюємо координати патрульного з координатами Tree
      return unless @record.maintainable_type == "Tree"

      tree = @record.maintainable
      # `tree.longitude` (no `&.`, unlike the first clause): dead-`&.` cleanup
      # — reaching this clause already requires `tree&.latitude` to be
      # truthy, which is only possible when `tree` is non-nil, so `tree` is
      # provably present here too. The first clause keeps its `&.` — `tree`
      # itself (a nullified FK on a deleted maintainable) can be nil.
      return unless tree&.latitude.present? && tree.longitude.present?

      drift_m = SilkenNet::GeoUtils.haversine_distance_m(
        @record.latitude.to_f, @record.longitude.to_f,
        tree.latitude.to_f, tree.longitude.to_f
      )

      color = if drift_m < 50 then "text-emerald-400"
      elsif drift_m < 500 then "text-status-warning-text"
      else "text-red-400"
      end

      div(class: "flex justify-between border-t border-emerald-900/30 pt-2 mt-2") do
        span(class: "text-gaia-text-muted") { t(".gps.drift") }
        span(class: color) { "#{drift_m.round} m" }
      end
    end

    # =========================================================================
    # HARDWARE
    # =========================================================================
    def render_hardware_panel
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        div(class: "flex justify-between items-center") do
          h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".hardware.heading") }
          if @record.hardware_verified
            span(class: "h-2 w-2 rounded-full bg-emerald-500 shadow-[0_0_8px_#10b981]")
          else
            span(class: "h-2 w-2 rounded-full bg-status-warning")
          end
        end

        div(class: "text-tiny font-mono space-y-3") do
          meta_row(t(".hardware.stm_verified"), @record.hardware_verified ? t(".hardware.verified") : t(".hardware.pending"))
          meta_row(t(".hardware.record_type"), @record.action_type_label.upcase)
        end

        if !@record.hardware_verified && mutable?
          div(class: "pt-4 border-t border-emerald-900/30") do
            button_to(
              t(".hardware.verify_now"),
              verify_maintenance_record_path(@record),
              method: :patch,
              class: "w-full py-2 border border-status-warning text-mini uppercase text-status-warning-text " \
                     "hover:bg-status-warning hover:text-white transition-all",
              data: { turbo_confirm: t(".hardware.verify_confirm", id: @record.id) }
            )
          end
        end
      end
    end

    # =========================================================================
    # HELPERS
    # =========================================================================
    # [I18N.1] Приймає СИРИЙ токен: мапа ключується ним, тож подана сюди локалізована
    # мітка не влучала НІКОЛИ — бейдж мовчки сірів на кожному записі, і фолбек-пін
    # цього не бачив, бо він однаково зелений, коли сіріє лише невідомий тип і коли
    # сіріє кожен. Мітку деривує сам хелпер, дім — `MaintenanceRecord.action_type_label`.
    def action_badge(type)
      colors = {
        "repair" => "border-status-warning text-status-warning-text",
        "installation" => "border-blue-600 text-blue-600",
        "inspection" => "border-emerald-600 text-emerald-600",
        "cleaning" => "border-cyan-700 text-cyan-700",
        "decommissioning" => "border-red-800 text-red-800",
        "biomass_extraction" => "border-status-danger text-status-danger-accent"
      }
      cls = colors[type.to_s] || "border-gaia-border text-gaia-text-muted"
      span(class: tokens("text-mini px-2 py-0.5 border font-mono uppercase tracking-widest", cls)) do
        MaintenanceRecord.action_type_label(type)
      end
    end

    def hardware_badge(verified)
      if verified
        span(class: "text-mini px-2 py-0.5 border border-emerald-600 text-emerald-600 font-mono uppercase") do
          t(".hardware_badge.verified")
        end
      else
        span(class: "text-mini px-2 py-0.5 border border-status-warning-accent text-status-warning-accent font-mono uppercase") do
          t(".hardware_badge.pending")
        end
      end
    end

    def meta_row(label, value)
      div(class: "flex justify-between") do
        span(class: "text-gaia-text-muted") { "#{label}:" }
        span(class: "text-emerald-400 truncate ml-2") { value }
      end
    end

    # Haversine distance delegated to shared utility (SilkenNet::GeoUtils)
  end
end
