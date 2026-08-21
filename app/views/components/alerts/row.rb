# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# app/views/components/alerts/row.rb
module Alerts
  class Row < ApplicationComponent
    # [UI.6] `current_user` — лише для видимості «Acknowledge»: список тривог відкритий
    # УСІМ ролям (investor теж), а `alerts#resolve` стоїть за `authorize_forester!,
    # only: :resolve`, тож read-only глядач бачив бойову кнопку, яка після
    # turbo-confirm мовчки вмирала в 403. Дефолт `nil` fail-CLOSED.
    # @param detail_href [String, nil] КОНТЕКСТ РЕНДЕРУ, не оздоблення, і адресу
    #   БУДУЄ ПРОДЮСЕР — точна форма `Wallets::TransactionRow#status_src`.
    #   `nil` = рядок стоїть УСЕРЕДИНІ самої сторінки тривоги, де посилання вело б
    #   на себе; рядок-адреса = рядок стоїть у РЕЄСТРІ `/alerts`, звідки тип веде
    #   на сторінку з SOP-панеллю.
    #   🔴 Чому не булевий прапорець із `alert_path` усередині: цей компонент
    #   рендериться ЩЕ Й через `.call` (turbo_stream-відповідь `alerts#resolve`),
    #   а там немає view-контексту — маршрут-хелпер падає
    #   `undefined method 'default_url_options' for nil`, тобто 500 на дії
    #   оператора. Виміряно: сусідній `resolve_alert_path` уцілів лише тому, що
    #   в тій відповіді рядок ЗАВЖДИ резолвлений і його гілка не виконується.
    #   Дефолт fail-closed: забутий kwarg дає рядок без входу, не виняток.
    def initialize(alert:, current_user: nil, detail_href: nil)
      @alert = alert
      @current_user = current_user
      @detail_href = detail_href
    end

    def view_template
      tr(id: dom_id(@alert), class: row_classes) do
        # `data-label` powers the CSS-only mobile card flip in
        # application.css § "Responsive Table Pattern". Each label mirrors
        # the column header in `Alerts::Index` so the visible text matches
        # what a desktop user would see in the <th>.
        td(class: "p-4", data_label: t("alerts.table.severity")) { severity_badge }
        # Мітка типу — через TextFormatter, а не власний лукап: одна деривація
        # ключа на застосунок (див. `ALERT_TYPE_SCOPE`), тож спека покриває оби́два
        # шляхи рендеру. Раніше тут жив locale-сліпий `.humanize`.
        # [ARCH.31] Тип — ЄДИНИЙ вхід на сторінку тривоги, а з нею й на SOP-панель.
        # Доти маршрут `GET /alerts/:id` існував, рендерив `Alerts::Show` із
        # операційним runbook'ом — і не мав ЖОДНОГО викликача `alert_path` у всьому
        # `app/`, тобто лісник міг дістатись інструкцій лише набравши адресу руками,
        # тоді як сам пункт обіцяє «інструкції ПРИ КЛІКУ на EwsAlert».
        # ⚠️ Без `aria-label` СВІДОМО: видимий текст локалізований, а мітка поверх
        # нього перекрила б accessible name (`04_04 §9` — ратифіковане правило цього
        # ж дерева). Призначення посилання визначає КОНТЕКСТ рядка — джерело, час і
        # рівень небезпеки стоять поруч, що і є критерієм WCAG 2.4.4 (In Context).
        td(class: "p-4 text-mini uppercase text-gaia-text-subtle tracking-widest", data_label: t("alerts.table.alert_type")) do
          if @detail_href
            a(href: @detail_href, class: alert_link_classes) do
              TreeChronicle::TextFormatter.alert_title(@alert)
            end
          else
            TreeChronicle::TextFormatter.alert_title(@alert)
          end
        end
        td(class: "p-4 text-gaia-primary-strong", data_label: t("alerts.table.source")) do
          "#{@alert.cluster&.name} // #{@alert.tree&.did || 'System'}"
        end
        td(class: "p-4 text-gaia-text-subtle", data_label: t("alerts.table.message")) do
          div { @alert.message }
        end
        td(class: "p-4 text-tiny text-gaia-text-muted", data_label: t("alerts.table.timestamp")) do
          @alert.created_at.strftime("%H:%M:%S")
        end
        # Action cell intentionally has no data-label — the CSS rule turns
        # it into a centred footer block on mobile (no column heading dupe).
        td(class: "p-4 text-right") { action_button }
      end
    end

    private


    def severity_badge
      color = case @alert.severity.to_s
      # [UI.3] Пульс знято: `critical` має ВЛАСНЕ тло серед чотирьох рівнів
      # (danger ⊥ warning ⊥ info ⊥ neutral), тож він нічого не розрізняв — лише
      # робив підпис нечитабельним у западині (6.80 → 2.45 світла, виміряно).
      when "critical" then "bg-status-danger text-status-danger-text"
      when "medium" then "bg-status-warning text-status-warning-text"
      when "low" then "bg-status-info text-status-info-text"
      else "bg-status-neutral text-status-neutral-text"
      end
      # Деривація через `SEVERITY_SCOPE` — одна на застосунок.
      # Раніше сюди летіло сире значення enum'а, ще й двічі: у видимий текст і
      # в перекладений aria-шаблон, тобто скрін-рідер читав англійське слово
      # всередині української фрази.
      label = TreeChronicle::TextFormatter.alert_severity_label(@alert)
      span(
        role: "status",
        aria_label: t(".severity_aria", severity: label),
        class: tokens("px-2 py-0.5 rounded-sm text-mini uppercase font-bold", color)
      ) { label }
    end

    def action_button
      if @alert.status_resolved?
        span(class: "text-gaia-text-muted text-mini uppercase tracking-widest", role: "status") do
          t(".resolved")
        end
      else
        # [UI.6] Гасити тривогу може лише forester+ (`authorize_forester!, only: :resolve`).
        # Нижчій ролі кнопку не показуємо взагалі: доти investor її бачив, тиснув, і
        # turbo-submission помирала в JSON-403 без жодного пояснення.
        return unless @current_user&.forest_commander?

        # Acknowledge form posts via Turbo Stream — single-row replace.
        button_to(
          t(".acknowledge"),
          resolve_alert_path(@alert),
          method: :patch,
          aria: { label: t(".resolve_aria", id: @alert.id) },
          class: resolve_button_classes,
          data: { turbo_confirm: t(".resolve_confirm", id: @alert.id) }
        )
      end
    end

    # 🔴 [UI.3] `opacity-40` тут глушила ВЕСЬ рядок разом із текстом: 16.10:1 →
    # **2.46:1** у світлій темі, 19.05:1 → 3.58:1 у темній, при порозі 4.5:1.
    # Прозорість на контейнері множить контраст КОЖНОГО нащадка, і жоден наш
    # прилад цього не бачить — токени правильні, пари fg/bg правильні.
    #
    # Знята без заміни, бо сигнал «закрито» вже несуть ДВА інші носії: фон
    # `surface-sunken` і слово `t(".resolved")` замість кнопки в колонці дії
    # (`action_button`). Прозорість була третім, надлишковим — і єдиним, що
    # коштував читабельності.
    def row_classes
      tokens(
        "transition-all duration-700",
        "bg-gaia-surface-sunken": @alert.status_resolved?,
        "hover:bg-gaia-surface-sunken": !@alert.status_resolved?
      )
    end

    # Форма — дзеркало `gateways/index` («відкрити деталі»): успадкований колір
    # комірки, брендовий hover і власне focus-кільце, бо посилання всередині
    # `<td>` інакше не має видимого фокуса.
    def alert_link_classes
      "hover:text-gaia-primary-strong focus-visible:outline-none focus-visible:ring-2 " \
        "focus-visible:ring-gaia-primary-strong transition-colors"
    end

    def resolve_button_classes
      "text-mini uppercase tracking-tighter border border-status-danger text-status-danger-text " \
        "hover:bg-status-danger hover:text-gaia-text-strong " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-status-danger-accent " \
        "px-3 py-1 transition-all"
    end
  end
end
