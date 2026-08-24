# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Alerts
  # [ARCH.31] Сторінка однієї тривоги: рядок телеметрії + SOP-панель реагування.
  #
  # Операційна половина SOP — НАША (присуд founder 2026-08-20): кроки, що їх
  # forester виконує в застосунку (acknowledge → звірка незалежного свідка →
  # Field-Audit), нікого не чекають. Доменна тактика (гасіння, правова
  # компетентність ЦЗ) має названого власника поза платформою (Ротар,
  # `00_02 §1.3`) — її секція чесно каже «контент відсутній», а не мовчить
  # і не вигадує: плейсхолдер і є оголошенням межі (UNI.12).
  #
  # Обгортка table тут несуча, не косметика: `Alerts::Row` — це `<tr>`, і доти
  # show-сторінка рендерила його ГОЛИМ (tr поза table — невалідний DOM, який
  # браузер тихо викидає з дерева). Заголовки дзеркалять `Alerts::Index`.
  class Show < ApplicationComponent
    # Операційні кроки платформи — порядок несе сенс (ol), ключі локалізовані.
    # Дім кроків тут, поки їх читає одна сторінка; третій читач => константа моделі.
    SOP_STEPS = %i[acknowledge verify field_audit].freeze

    def initialize(alert:, current_user: nil)
      @alert = alert
      @current_user = current_user
    end

    def view_template
      div(class: "space-y-8") do
        alert_table
        assignment_panel
        sop_panel
      end
    end

    private

    # [E.20] «Хто зараз на гачку». Доти сторінка вміла показати лише «хто закрив»
    # (`resolver`), тобто адресата в неї не було взагалі — а Field-Audit саме
    # адресата й не мав.
    def assignment_panel
      section(aria_labelledby: "assignment-heading",
              class: "border border-gaia-border bg-gaia-surface p-6 space-y-3") do
        h3(id: "assignment-heading", class: "text-tiny uppercase tracking-widest text-gaia-text-muted") do
          t(".assignment.title")
        end

        p(class: "text-compact") { assignment_line }
        assignment_action
      end
    end

    def assignment_line
      if @alert.assignee.blank?
        span(class: "text-gaia-text-muted") { t(".assignment.unassigned") }
        return
      end

      span(class: "text-gaia-text-strong font-bold") { @alert.assignee.full_name }
      # Час — ДОДАТКОВИЙ, не обов'язковий: його відсутність просто не рендериться.
      # Вигаданого «—» тут немає свідомо — пара (виконавець, час) пишеться однією
      # операцією, тож розходження було б аномалією, яку прочерк сховав би.
      return if @alert.assigned_at.blank?

      span(class: "text-mini text-gaia-text-muted ml-2") do
        t(".assignment.since", at: @alert.assigned_at.strftime("%Y-%m-%d %H:%M"))
      end
    end

    # [UI.6] Обидві дії стоять за `authorize_forester!`, тож нижчій ролі кнопки не
    # показуємо — інакше вона обіцяла б дію, якої актор не має, і вмирала б у 403.
    # 🔴 Право ВІДПУСТИТИ ширше за право взяти (виконавець АБО admin+) — це
    # дзеркало `EwsAlert#release!`, і розходження тут дало б кнопку-обманку.
    def assignment_action
      return unless @current_user&.forest_commander?
      return unless @alert.status_active?

      if @alert.assigned_to_id.blank?
        assignment_button(:claim, claim_alert_path(@alert))
      elsif @alert.assigned_to_id == @current_user.id || @current_user.admin_or_above?
        assignment_button(:release, release_alert_path(@alert))
      end
    end

    def assignment_button(kind, path)
      button_to(
        t(".assignment.#{kind}"),
        path,
        method: :patch,
        aria: { label: t(".assignment.#{kind}_aria", id: @alert.id) },
        class: tokens(
          "text-mini uppercase tracking-widest px-3 py-1",
          "text-gaia-primary-strong border border-gaia-border-strong",
          "hover:text-gaia-text-strong transition-colors",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
        )
      )
    end

    def alert_table
      div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
        table(class: "w-full text-left border-collapse", role: "table") do
          thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
            tr do
              %w[severity alert_type source message timestamp].each do |col|
                th(scope: "col", class: "p-4") { t("alerts.table.#{col}") }
              end
              th(scope: "col", class: "p-4 text-right") { t("alerts.table.command") }
            end
          end
          tbody { render Alerts::Row.new(alert: @alert, current_user: @current_user) }
        end
      end
    end

    def sop_panel
      section(aria_labelledby: "sop-heading", class: "border border-gaia-border bg-gaia-surface p-6 space-y-6") do
        h3(id: "sop-heading", class: "text-tiny uppercase tracking-widest text-gaia-text-muted") do
          t(".sop.title")
        end

        ol(class: "space-y-4 list-decimal list-inside") do
          SOP_STEPS.each do |step|
            li(class: "text-compact text-gaia-text") do
              span(class: "font-bold text-gaia-text-strong") { t(".sop.steps.#{step}.title") }
              p(class: "text-mini text-gaia-text-muted mt-1 ml-5") { t(".sop.steps.#{step}.body") }
              field_audit_cta if step == :field_audit
            end
          end
        end

        domain_placeholder
      end
    end

    # [E.20] Крок SOP був ТУПИКОМ: `maintenance_records#new` уже читає
    # `ews_alert_id`, тобто зчеплення існувало в контролері, а пускача в UI не
    # було — оператор мусив піти в інший розділ і згадати номер тривоги руками.
    # Саме через це `EwsAlert.escalate_field_audit!` мав дванадцять продюсерів і
    # жодного споживача, що призначає чи виконує.
    #
    # [UI.6] Гейт той самий, що в `Alerts::Row#action_button`, і з тієї ж
    # підстави: ВЕСЬ `MaintenanceRecordsController` стоїть за
    # `authorize_forester!`, тож нижчій ролі посилання вело б у 403 — показувати
    # його означало б обіцяти дію, якої актор не має.
    def field_audit_cta
      return unless @current_user&.forest_commander?

      div(class: "mt-2 ml-5") do
        a(href: new_maintenance_record_path(**field_audit_query), class: cta_classes) do
          t(".sop.steps.field_audit.cta")
        end
      end
    end

    # Дерево прокидаємо ЛИШЕ коли воно є: cluster-level тривога (`tree_id` NULL —
    # так пишуться blackout і staleness-ескалації) єдиного `maintainable` не має,
    # і підставлений сюди id зробив би запис про НЕ ТОЙ об'єкт. `maintainable_type`
    # контролер дефолтить на "Tree" сам, тож без дерева не шлемо й тип.
    def field_audit_query
      return { ews_alert_id: @alert.id } if @alert.tree_id.blank?

      { ews_alert_id: @alert.id, maintainable_type: "Tree", maintainable_id: @alert.tree_id }
    end

    def cta_classes
      tokens(
        "inline-block text-mini uppercase tracking-widest px-3 py-1",
        "text-gaia-primary-strong border border-gaia-border-strong",
        "hover:text-gaia-text-strong transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
      )
    end

    # Чесний порожній стан: називає ВІДСУТНІСТЬ джерела, не тимчасовість —
    # «зачекайте» ховало б відкрите партнерське питання (прецедент ARCH.103:
    # порожнеча мусить мати голос і причину).
    def domain_placeholder
      div(class: "pt-4 border-t border-gaia-border") do
        h4(class: "text-mini uppercase tracking-widest text-gaia-text-muted") { t(".sop.domain.title") }
        p(class: "text-mini text-gaia-text-subtle italic mt-2") { t(".sop.domain.pending") }
      end
    end
  end
end
