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
                 "p-8 border border-gaia-border bg-gaia-surface shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[80px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") do
          @record.action_type_label.upcase
        end

        div do
          h2(class: "text-3xl font-extralight tracking-tighter text-gaia-text") do
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
            class: "px-4 py-2 border border-gaia-border-strong text-gaia-primary-strong hover:border-gaia-primary " \
                   "hover:text-gaia-primary-strong transition-all uppercase text-mini tracking-widest " \
                   "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
          ) { t(".header.new_record") }

          if !@record.hardware_verified && mutable?
            button_to(
              t(".header.verify_hardware"),
              verify_maintenance_record_path(@record),
              method: :patch,
              class: "px-4 py-2 border border-status-warning-accent text-status-warning-accent hover:bg-status-warning " \
                     "hover:text-status-warning-text transition-all uppercase text-mini tracking-widest " \
                     "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
              data: { turbo_confirm: t(".header.verify_confirm", id: @record.id) }
            )
          end

          if attestable?
            button_to(
              t(".header.attest"),
              attest_maintenance_record_path(@record),
              method: :patch,
              aria: { label: t(".header.attest_aria", id: @record.id) },
              class: "px-4 py-2 border border-gaia-border-strong text-gaia-text-strong hover:border-gaia-primary " \
                     "transition-all uppercase text-mini tracking-widest " \
                     "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
              data: { turbo_confirm: t(".header.attest_confirm", id: @record.id) }
            )
          end
        end
      end
    end

    # [E.20] Кнопку бачить лише той, хто МОЖЕ підписати — тобто НЕ автор запису.
    # 🔴 Це дзеркало моделі (`SelfAttestation`), і напрямок тут протилежний до
    # сусіднього `mutable?`: той пускає автора, а тут автор — саме той, кого треба
    # відсікти. Скопіювати сусідній гард означало б легалізувати самозвіт, а
    # розходження в інший бік дало б кнопку-обманку тому, хто найімовірніше її й
    # натисне.
    def attestable?
      @current_user.present? && @current_user.id != @record.user_id && !@record.attested?
    end

    # «Не засвідчено» — це ІМʼЯ стану, не прочерк (ARCH.103: порожнеча мусить мати
    # голос). Відсутність другої пари очей і є тим фактом, який читач мусить
    # побачити, а тире прочиталось би як «поле не заповнили».
    def attestation_label
      return t(".metadata.not_attested") unless @record.attested?

      # Без `&.`-гардів свідомо: пару (атестатор, час) пише ОДНА операція
      # (`attest!`), а FK не дає атестатору зникнути — тож захисна гілка тут
      # була б мертвим кодом із виглядом обачності (її й спіймала гілкова
      # підлога покриття). Якщо інваріант колись зламають, чесніше впасти
      # гучно, ніж намалювати правдоподібний напівряд.
      "#{@record.attestor.full_name} — #{@record.attested_at.strftime('%d.%m.%Y %H:%M')}"
    end

    # =========================================================================
    # EVIDENCE GALLERY
    # =========================================================================
    def render_evidence_gallery
      div(class: "p-8 border border-gaia-border bg-gaia-surface-sunken") do
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
      div(class: "border border-dashed border-gaia-border p-10 text-center") do
        p(class: "text-gaia-text-muted uppercase tracking-widest text-tiny") { t(".evidence.no_photos") }
        if %w[repair installation].include?(@record.action_type)
          p(class: "text-status-danger-accent text-mini mt-2 font-mono") do
            t(".evidence.trust_protocol", action_type: @record.action_type_label)
          end
        end
        if mutable?
          a(
            href: edit_maintenance_record_path(@record),
            class: "inline-block mt-4 px-4 py-2 border border-gaia-border text-gaia-primary-strong " \
                   "hover:border-gaia-primary hover:text-gaia-primary-strong uppercase text-mini tracking-widest transition-all " \
                   "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
          ) { t(".evidence.attach") }
        end
      end
    end

    # =========================================================================
    # NOTES
    # =========================================================================
    def render_notes_panel
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".notes.heading") }
        p(class: "text-sm text-gaia-text font-mono leading-relaxed whitespace-pre-wrap") { @record.notes }
      end
    end

    # =========================================================================
    # COST BREAKDOWN (OpEx Series C)
    # =========================================================================
    def render_cost_breakdown
      div(class: "p-6 border border-gaia-border bg-gaia-surface-sunken") do
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
      div(class: "p-4 border border-gaia-border bg-gaia-surface-sunken") do
        p(class: "text-mini uppercase tracking-widest text-gaia-text-muted") { label }
        p(class: "text-micro text-gaia-text-subtle mt-1 mb-3") { sub }
        span(class: tokens("text-2xl font-light", "text-gaia-primary-strong": highlight, "text-gaia-text-strong": !highlight)) { value }
      end
    end

    # =========================================================================
    # METADATA
    # =========================================================================
    def render_metadata_panel
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-4") do
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
          meta_row(t(".metadata.attested"), attestation_label)
          if @record.ews_alert_id
            meta_row(t(".metadata.ews_alert"), "##{@record.ews_alert_id}")
          end
          meta_row(t(".metadata.created"), @record.created_at&.strftime("%d.%m.%Y %H:%M"))
          meta_row(t(".metadata.updated"), @record.updated_at&.strftime("%d.%m.%Y %H:%M"))
        end

        if mutable?
          div(class: "pt-4 border-t border-gaia-border") do
            a(
              href: edit_maintenance_record_path(@record),
              class: "block w-full text-center py-2 border border-gaia-border text-mini uppercase " \
                     "text-gaia-primary-strong hover:border-gaia-primary hover:text-gaia-primary-strong transition-all " \
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
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-4") do
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
            class: "block mt-4 text-center p-2 border border-gaia-border-strong text-gaia-primary-strong " \
                   "hover:bg-gaia-primary hover:text-gaia-primary-text transition-all uppercase text-mini " \
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

      color = if drift_m < 50 then "text-gaia-primary-strong"
      elsif drift_m < 500 then "text-status-warning-accent"
      else "text-status-danger-accent"
      end

      div(class: "flex justify-between border-t border-gaia-border pt-2 mt-2") do
        span(class: "text-gaia-text-muted") { t(".gps.drift") }
        span(class: color) { "#{drift_m.round} m" }
      end
    end

    # =========================================================================
    # HARDWARE
    # =========================================================================
    def render_hardware_panel
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-4") do
        div(class: "flex justify-between items-center") do
          h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".hardware.heading") }
          if @record.hardware_verified
            span(class: "h-2 w-2 rounded-full bg-gaia-primary-strong shadow-[0_0_8px_#10b981]")
          else
            # [UI.1] `-accent`, не пастель: `bg-status-warning` у ролі крапки давав 1.17:1 у світлій.
            span(class: "h-2 w-2 rounded-full bg-status-warning-accent")
          end
        end

        div(class: "text-tiny font-mono space-y-3") do
          meta_row(t(".hardware.stm_verified"), @record.hardware_verified ? t(".hardware.verified") : t(".hardware.pending"))
          meta_row(t(".hardware.record_type"), @record.action_type_label.upcase)
        end

        if !@record.hardware_verified && mutable?
          div(class: "pt-4 border-t border-gaia-border") do
            button_to(
              t(".hardware.verify_now"),
              verify_maintenance_record_path(@record),
              method: :patch,
              class: "w-full py-2 border border-status-warning-accent text-mini uppercase text-status-warning-accent " \
                     "hover:bg-status-warning hover:text-status-warning-text transition-all",
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
    # [UI.1] Кольори = дзеркало ваг `Maintenance::Index#action_badge` (рішення там);
    # контур їде ОДНИМ токеном на border+text: пастельна рамка на світлій поверхні
    # невидима (1.1:1), а `-text` поза пастеллю — токен поза роллю (§3.2).
    def action_badge(type)
      colors = {
        "repair" => "border-status-warning-accent text-status-warning-accent",
        "installation" => "border-status-info-accent text-status-info-accent",
        "inspection" => "border-gaia-primary-strong text-gaia-primary-strong",
        "cleaning" => "border-gaia-primary-strong text-gaia-primary-strong",
        "decommissioning" => "border-status-neutral-accent text-status-neutral-accent",
        "biomass_extraction" => "border-status-danger-accent text-status-danger-accent"
      }
      cls = colors[type.to_s] || "border-gaia-border text-gaia-text-muted"
      span(class: tokens("text-mini px-2 py-0.5 border font-mono uppercase tracking-widest", cls)) do
        MaintenanceRecord.action_type_label(type)
      end
    end

    def hardware_badge(verified)
      if verified
        span(class: "text-mini px-2 py-0.5 border border-gaia-primary-strong text-gaia-primary-strong font-mono uppercase") do
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
        span(class: "text-gaia-text truncate ml-2") { value }
      end
    end

    # Haversine distance delegated to shared utility (SilkenNet::GeoUtils)
  end
end
