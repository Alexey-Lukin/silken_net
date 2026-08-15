# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Telemetry
  class LiveStream < ApplicationComponent
    # 🔴 [UI.4] Дім двох СТАТИЧНИХ target-id стрічки. Обидва називалися рукою по
    # обидва боки тракту — тут і в `UnpackTelemetryWorker`, — а розходження такої
    # пари не має жодного симптому: `replace`/`remove` у неіснуючу ціль Turbo
    # ковтає мовчки, тож стрічка просто перестає оновлюватись. Форма — константа,
    # бо адреса СИНГЛТОННА (сторінка одна, запису під нею немає), тобто метод
    # класу тут був би церемонією; прецедент у сусіда — `Wallets::Show::LEDGER_TARGET`.
    FEED_TARGET = "telemetry_feed"
    PLACEHOLDER_TARGET = "feed_placeholder"

    # Організація глядача — НЕ декорація: вона і є скоуп стріму. Голий
    # `"telemetry_stream"` віддавав кожному автентифікованому користувачу
    # телеметрію шлюзів УСІХ організацій, і жоден REST/Pundit-аудит цього не
    # бачив: HTTP-відповідь тенант-даних не несе взагалі, витік приїжджав
    # вебсокетом уже після підписки.
    # [I18N.2] Дім ПОРЯДКУ колонок: ті самі ключі живлять і `<thead>`, і
    # `--gaia-col-N`, тож заголовок і мобільна мітка не можуть розійтись.
    # Порядок несучий — CSS адресує колонки через `nth-child`.
    COLUMNS = %w[
      telemetry.table.timestamp
      telemetry.table.gateway
      telemetry.table.payload
      telemetry.table.status
    ].freeze

    def initialize(organization:)
      @organization = organization
    end

    def view_template
      div(class: "space-y-6") do
        header_section

        # Підписка на SolidCable / Turbo Streams. Без організації підписки
        # немає зовсім (fail-closed): сторінка лишається читабельною, живих
        # оновлень просто не надходить — дзеркало `Alerts::Index`.
        turbo_stream_from TurboStreams::Name.org(:telemetry, @organization) if @organization

        # Контейнер з відносною позицією для накладання градієнта й таблиці.
        # ⚖️ [UI.1] Декоративний matrix-rain canvas ЗНЯТО 2026-08-14 (присуд founder):
        # ~16 fps безперервного перемальовування коштували глядачеві 100–300 мВт —
        # більше, ніж уся різниця світлої й темної теми (~30 мВт). Це і є та форма,
        # у якій енергетичний аргумент про UI має право звучати в цьому проєкті.
        div(class: "relative border border-gaia-border bg-gaia-surface min-h-[400px] md:min-h-[600px] overflow-hidden rounded-sm shadow-[0_0_40px_rgba(6,78,59,0.2)]") do
          # Радіальний градієнт для глибини (decorative — raw classes allowed).
          # Градієнт «затемнення до країв» тепер іде за темою: сирий `to-black`
          # робив цю панель чорною і в СВІТЛІЙ, тобто був тем-інваріантною
          # підлогою під токенізованим текстом — саме через нього світла половина
          # `--gaia-text-subtle` була арифметично нездійсненна (`00_07` UI.3).
          # Намір збережено симетрично: краї глибші за панель в ОБОХ темах.
          div(class: "absolute inset-0 z-0 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-transparent via-gaia-surface-base/80 to-gaia-surface-base pointer-events-none", aria_hidden: "true")

          # HUD-таблиця поверх градієнта. Mobile рендериться як
          # стек карток через `gaia-responsive-table` (CSS-only flip).
          div(class: "relative z-10 w-full h-[400px] md:h-[600px] overflow-y-auto md:overflow-x-auto custom-scrollbar") do
            table(
              class: "gaia-responsive-table gaia-labels-published w-full text-left font-mono text-tiny md:min-w-[640px]",
              role: "table",
              style: published_column_labels
            ) do
              thead(class: "gaia-sticky-thead bg-gaia-surface-sunken/80 backdrop-blur-md text-gaia-text-muted uppercase tracking-widest border-b border-gaia-border shadow-md") do
                tr do
                  th(scope: "col", class: "p-4 w-32 font-medium") { COLUMNS[0].then { t(it) } }
                  th(scope: "col", class: "p-4 w-40 font-medium") { COLUMNS[1].then { t(it) } }
                  th(scope: "col", class: "p-4 font-medium") { COLUMNS[2].then { t(it) } }
                  th(scope: "col", class: "p-4 w-24 text-right font-medium") { COLUMNS[3].then { t(it) } }
                end
              end

              tbody(id: FEED_TARGET, class: "md:divide-y md:divide-gaia-border") do
                tr(id: PLACEHOLDER_TARGET) do
                  td(colspan: 4, class: "p-12 text-center text-gaia-text-subtle flex flex-col items-center justify-center") do
                    div(class: "w-8 h-8 rounded-full border-b-2 border-gaia-border-strong animate-spin mb-4", aria_hidden: "true")
                    p(class: "italic tracking-widest text-mini") { t(".awaiting") }
                  end
                end
              end
            end
          end
        end
      end
    end

    private

    # [I18N.2] Публікує мітки колонок як CSS custom properties, щоб рядок,
    # який приїде броадкастом, не мусив нести власну копію (він рендериться в
    # Sidekiq, де локалі немає — `04_04 §8.1а`).
    #
    # 🔴 Лапки обовʼязкові: `content` приймає РЯДОК, а не ключове слово, тож
    # без них правило просто не застосується. Одинарна лапка всередині
    # перекладу зламала б значення — екрануємо (`content` розуміє `\'`).
    # Крапку з комою прибираємо: вона розділяє декларації в `style`. Переноси
    # рядка — теж: неекранований LF усередині CSS-рядка це bad-string-token
    # (CSS Syntax L3 §4.3.5), а YAML тривіально дозволяє багаторядковий скаляр.
    # ⊥ Подвійну лапку НЕ чіпаємо свідомо: Phlex екранує атрибути сам
    # (`sgml/attributes.rb` — `gsub('"', "&quot;")`), тож наша копія була б
    # другим домом того самого правила.
    def published_column_labels
      COLUMNS.each_with_index.map do |key, index|
        value = css_string_literal(t(key).to_s)
        "--gaia-col-#{index + 1}: '#{value}'"
      end.join("; ")
    end

    # Один дім екранування, щоб ланцюг не читався як випадковий набір `gsub`.
    ESCAPE_IN_CSS_STRING = { "\\" => "\\\\", "'" => "\\'" }.freeze

    def css_string_literal(raw)
      raw.gsub(/[\\']/) { |char| ESCAPE_IN_CSS_STRING.fetch(char) }
         .delete(";")
         .gsub(/\s+/, " ")
         .strip
    end

    def header_section
      div(class: "flex flex-col sm:flex-row sm:justify-between sm:items-end gap-3 border-b border-gaia-border pb-4") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-gaia-text-muted flex items-center gap-2") do
            plain t(".header_eyebrow")
          end
          h2(class: "text-2xl font-light text-gaia-text mt-2") { t(".header_title") }
        end

        div(class: "flex items-center gap-3 bg-gaia-surface-sunken px-4 py-2 border border-gaia-border shadow-[inset_0_0_10px_rgba(6,78,59,0.5)]") do
          div(class: "relative flex h-2 w-2", aria_hidden: "true") do
            span(class: "animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75")
            span(class: "relative inline-flex rounded-full h-2 w-2 bg-emerald-500")
          end
          span(class: "font-mono text-mini text-gaia-primary uppercase tracking-widest") { t(".carrier_label") }
        end
      end
    end
  end
end
