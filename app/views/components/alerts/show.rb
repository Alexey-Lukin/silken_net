# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Alerts
  # [ARCH.31] Сторінка однієї тривоги: рядок телеметрії + SOP-панель реагування.
  #
  # Операційна половина SOP — НАША (присуд founder 2026-08-20): кроки, що їх
  # forester виконує в застосунку (acknowledge → звірка незалежного свідка →
  # Field-Audit), нікого не чекають. Доменна тактика (гасіння, правова
  # компетентність ЦЗ) має названого власника поза платформою (Ротар,
  # `07_03 §1.3`) — її секція чесно каже «контент відсутній», а не мовчить
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
        sop_panel
      end
    end

    private

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
            end
          end
        end

        domain_placeholder
      end
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
