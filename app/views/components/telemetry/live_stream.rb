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
    # 🔴 [UI.16, 2026-09-06] Третя колонка була `telemetry.table.payload` — «Сирий
    # вміст CoAP (HEX-потік)», — і заголовок чесно називав те, що показував: лісгосп
    # бачив шістнадцятковий дамп конверта. Одиниця стрічки стала ЗВЕДЕННЯМ БАТЧУ
    # (`Telemetry::BatchSummary`), тож колонка тепер про кількість записів.
    # ⚠️ Ключ ПЕРЕЙМЕНОВАНО, а не переписано значення: `payload` описував сирий дамп
    # правдиво, і лишити його з новим змістом означало б зробити чотири локалі
    # хибними мовчки.
    COLUMNS = %w[
      telemetry.table.timestamp
      telemetry.table.gateway
      telemetry.table.records
      telemetry.table.status
    ].freeze

    # `last_record` — НЕОБОВʼЯЗКОВИЙ, і дефолт `nil` тут не недбалість: компонент
    # рендериться і з контролера (де запит легальний), і зі спек. ⛔ Запиту в
    # `initialize` немає й бути не може — `04_04` забороняє БД у Phlex-конструкторі.
    def initialize(organization:, last_record: nil)
      @organization = organization
      @last_record = last_record
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
        div(class: "relative border border-gaia-border bg-gaia-surface min-h-[400px] md:min-h-[600px] overflow-hidden rounded-sm") do
          # ⛔ [UI.3] Радіальну віньєтку ЗНЯТО 2026-08-19, і не з естетики — вона
          # НЕ МАЛЮВАЛАСЬ. `bg-[radial-gradient(…var(--tw-gradient-stops))]` без
          # утиліти `bg-radial`/`bg-linear-*` лишає `--tw-gradient-position`
          # незаданою, тож увесь `var()`-ланцюг недійсний і `background-image`
          # обчислюється в `none` (виміряно браузером: `bgImage: "none"`,
          # `--tw-gradient-stops: ""`). Мертва з 2026-03-01, єдиний сайт патерну в
          # дереві, `bg-radial` не вживається ніде — тобто ніхто не помітив
          # відсутності пʼять із половиною місяців.
          # 🔴 Знято, а не полагоджено, і причина вимірна: попередня, ЖИВА редакція
          # цієї ж віньєтки (сирий `to-black`) і БУЛА тим дефектом, через який
          # світла половина `--gaia-text-subtle` була арифметично нездійсненна. А
          # оживлення її токенної версії зробило б текст панелі чесно НЕВИМІРНИМ
          # (градієнт під текстом → `painted_backdrop`), тобто обміняло б виміряну
          # поверхню на невимірну — проти критерію місії «правдиво · невідбирано ·
          # відтворювано». Панель лишається плоскою `bg-gaia-surface` в обох темах.
          # Оборотно одним рядком (`bg-radial` + ті самі стопи), і числа для того
          # ходу вже пораховані: найтонша пара сторінки зійшла б 4.83 → 4.63.

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
                  # 🔴 [UI.16] `flex` СТОЯВ ТУТ, НА `td` — і мовчки вимикав `colspan`.
                  # Tailwind-клас `flex` дає `display:flex`, що знімає з елемента
                  # `display:table-cell`; а `colspan` діє ВИКЛЮЧНО на table-cell.
                  # Браузер тоді загортає клітинку в анонімну шириною ОДНІЄЇ колонки,
                  # і заглушка стискається в ліву чверть замість того, щоб лягти на
                  # всю таблицю (виміряно на живому canopy 2026-09-05, скріншот founder-а).
                  # ⛔ Не повертати `flex` на `td`/`th`: тут потрібен ВНУТРІШНІЙ
                  # контейнер. Клас той самий, що [UI.3] у ЦЬОМУ Ж файлі (віньєтка,
                  # мертва 5,5 місяця) — CSS написаний, CSS не діє, симптому немає:
                  # обидва рази поверхня виглядала «майже правильно», тож ніхто не
                  # питав. Це ДРУГИЙ інстанс класу в одному компоненті.
                  td(colspan: 4, class: "p-12 text-center text-gaia-text-subtle") do
                    div(class: "flex flex-col items-center justify-center") do
                      div(class: "w-8 h-8 rounded-full border-b-2 border-gaia-border-strong animate-spin mb-4", aria_hidden: "true")
                      idle_notice
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    private

    # 🔴 [UI.16] Плейсхолдер казав «Очікування Starlink Uplink…» ЗАВЖДИ — і на
    # порожній базі, і над лісом, що передавав годину тому. Друга половина була
    # брехнею мовчанням: сторінка ЖИВА лише під час події, а backfill'у стрічки не
    # існує (флаш не є сутністю в БД — розбір у `UnpackTelemetryWorker#broadcast_to_matrix`).
    # При нашому реальному каденсі (≈48 хв між флашами на сотні дерев) глядач бачив
    # вічний спінер і читав його як «нічого немає».
    #
    # ⚠️ Лік — НЕ вигаданий backfill, а ВИМІР: коли історія є, показуємо, коли саме
    # був останній прийнятий запис і від якої Королеви. Це не стрічка, і воно себе
    # стрічкою не видає. Порожнеча лишається порожнечею рівно тоді, коли вона правдива.
    # 🔑 `t()` тут ЛЕГАЛЬНИЙ, на відміну від `Telemetry::BatchSummary`: цей компонент
    # рендериться в ЗАПИТІ, де `LocaleSettable` уже відпрацював (`04_04 §8.1а`).
    def idle_notice
      return p(class: "italic tracking-widest text-mini") { t(".awaiting") } if @last_record.nil?

      p(class: "italic tracking-widest text-mini") do
        plain t(".idle_since", gateway: @last_record.queen_uid.presence || Telemetry::BatchSummary::UNKNOWN_RELAY)
      end
      render Views::Shared::UI::RelativeTime.new(datetime: @last_record.created_at)
    end

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
      (column_label_properties + value_label_properties).join("; ")
    end

    def column_label_properties
      COLUMNS.each_with_index.map do |key, index|
        "--gaia-col-#{index + 1}: '#{css_string_literal(t(key).to_s)}'"
      end
    end

    # 🔴 [UI.16 / I18N.1, 2026-09-06] ТОЙ САМИЙ механізм, розширений із підписів на
    # ЗНАЧЕННЯ — і це не винахід, а виконання канону. `§8.1а` велить обирати клас
    # ЧИТАННЯМ значень: транслітерація (`ЧАНК`) робить клас 1 чесним, а ЖИВІ слова
    # роблять його «чистою втратою, яка лягає лише на не-англійців». «Стрес» ·
    # «Аномалія» · «Гомеостаз» — живі слова, тож рядок, що друкує `ANOMALY·1`
    # лісгоспові, і був тією втратою: хроніка ТОГО Ж дерева вже казала «Стрес».
    #
    # ⛔ Лік НЕ «додати `t()` у рядок»: він рендериться з Sidekiq, де локалі немає,
    # тож переклад був би МЕРТВИМ за побудовою. Мітку питає СТОРІНКА (у запиті),
    # рядок лишається порожнім і бере текст із `::before`. Payload стає навіть
    # ЧИСТІШИМ, ніж був: тепер у ньому немає й англійських слів.
    #
    # ⚠️ ОГОЛОШЕНА СТЕЛЯ: текст із `::before` невидимий для `innerText`-пінів, тож
    # компонентна спека мусить пінити ОПУБЛІКОВАНУ властивість і `data-*`-маркер, а
    # не вміст комірки; сам рендер тримає `:js`-приклад. Дім механізму — `04_04 §8.1а`.
    def value_label_properties
      TelemetryLog.bio_statuses.keys.map { |status|
        "--gaia-bio-#{status.tr('_', '-')}: '#{css_string_literal(TelemetryLog.bio_status_label(status))}'"
      } + TelemetryUnpackerService::BATCH_STATES.map do |state|
        "--gaia-bstate-#{state}: '#{css_string_literal(TelemetryUnpackerService.batch_state_label(state))}'"
      end
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

        div(class: "flex items-center gap-3 bg-gaia-surface-sunken px-4 py-2 border border-gaia-border") do
          div(class: "relative flex h-2 w-2", aria_hidden: "true") do
            span(class: "animate-ping absolute inline-flex h-full w-full rounded-full bg-gaia-primary-strong opacity-75")
            span(class: "relative inline-flex rounded-full h-2 w-2 bg-gaia-primary-strong")
          end
          span(class: "font-mono text-mini text-gaia-primary-strong uppercase tracking-widest") { t(".carrier_label") }
        end
      end
    end
  end
end
