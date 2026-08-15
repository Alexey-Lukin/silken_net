# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module OracleVisions
  class ForecastCard < ApplicationComponent
    def initialize(insight:)
      @insight = insight
    end

    def view_template
      div(class: "p-6 border border-emerald-900 bg-zinc-950 group relative overflow-hidden transition-all hover:border-emerald-500") do
        # Неоновий індикатор впевненості Оракула.
        #
        # 🔴 [UI.3] Прозорості тут БУТИ НЕ МОЖЕ, і це не «занизьке значення», а
        # структурна несумісність. `opacity-40` давала композит 1.70:1 (червоний)
        # · 2.09:1 (смарагд) · 2.12:1 (нейтраль) на `bg-zinc-950` — при порозі
        # 3:1 для `text-2xl`. А підняти її до прохідної НЕМОЖЛИВО одним числом:
        # α для рівно 3:1 різна на кожен колір (0.692 · 0.549 · 0.544), а колір
        # деривується РАНТАЙМ із `yield_impact`. Спільне безпечне значення = 0.70,
        # тобто ефект вироджується в невидиму різницю.
        #
        # ⚠️ «На hover видно» ліком не є: на тачі hover'а немає, а WCAG 1.4.3
        # винятку «читабельно при наведенні» не має.
        div(class: tokens("absolute top-0 right-0 p-4 font-mono text-2xl", confidence_text_class)) do
          plain probability_reading
        end

        header_section
        render_mini_trend
        impact_assessment # Новий блок оцінки впливу на SCC
      end
    end

    private

    def header_section
      div(class: "mb-4") do
        span(class: "text-mini px-2 py-0.5 border border-emerald-800 text-emerald-600 uppercase tracking-tighter") { @insight.insight_type_label }
        h4(class: "text-lg font-light text-emerald-100 mt-2") { t(".predicted_window") }
        p(class: "text-tiny text-gray-500 font-mono flex items-center gap-2") do
          # [TEST.12] `ai_insights.target_date` — колонка `date`, без часу, тож
          # «// %H:%M UTC» друкував вічне «00:00» як справжню годину прогнозу.
          # Спека це ховала, подаючи `Time.utc(...)`, якого модель не віддає.
          plain @insight.target_date.strftime("%d.%m.%Y")
        end
      end
    end

    # 🔴 [ARCH.84] СЬОМИЙ інстанс класу, і він жив у ТОМУ САМОМУ файлі, що
    # шостий (`yield_impact`) — прохід, який полагодив сусіда за двадцять
    # рядків нижче, цього не побачив. Обидва поля мають нуль писачів:
    # `InsightGeneratorService` створює лише `daily_health_summary`, тож
    # прогноз-інсайт у проді не народжується взагалі, а `probability_score`
    # приходить винятково з `db/seeds.rb`.
    #
    # Що саме друкувалось при `nil` (виміряно рендером, не виведено):
    # текст — голий «%» без числа, а смуга — `style="width: %"`, тобто
    # НЕВАЛІДНИЙ CSS. Модель при цьому чесна: `#confidence_level` віддає
    # `:n_a`. Розходились не дані з даними, а компонент із власною моделлю.
    #
    # Смуга не малюється взагалі, і це та сама межа, що для стрес-дуги
    # ([ARCH.84], `trees/show`): будь-яка довжина є ТВЕРДЖЕННЯМ про вимір,
    # а нульова читається як виміряний нуль — тобто гірше за відсутність.
    def render_mini_trend
      if probability_score
        div(class: "h-1 w-full bg-emerald-950 my-4") do
          div(class: tokens("h-full transition-all duration-1000", confidence_bar_class),
              style: "width: #{formatted_probability}%")
        end
      end
      p(class: "text-compact text-gray-400 italic leading-relaxed") { @insight.summary }
    end

    def probability_score = @insight.probability_score

    # [UI.13] ⚖️ founder 2026-08-14: ціле друкується цілим, дробове лишається
    # дробовим. Колонка `numeric` віддає BigDecimal, тож без цього кожна картка
    # несла хвостовий нуль («40.0 %», `width: 40.0%`).
    #
    # 🔴 Чому НЕ `.round`, хоч він коротший: прецедент платформи
    # (`ApplicationComponent#formatted_points`, [ARCH.88]) виводить точність із
    # КРОКУ ДЖЕРЕЛА — а джерела тут немає взагалі, писачів нуль ([ARCH.84]).
    # Кроку, з якого можна вивести округлення, не існує, тож `.round` тихо
    # зʼїв би 40.5 → 41 у день, коли писач нарешті зʼявиться. Ця форма не
    # втрачає інформації в жодному майбутньому.
    #
    # ⚠️ Формат ОДИН на текст і на `width:` — інакше картка показувала б
    # «40 %» над смугою `width: 40.0%`, тобто два написання одного числа.
    def formatted_probability
      value = probability_score
      (value % 1).zero? ? value.to_i : value
    end

    # Дзеркало `impact_reading`: невиміряне має ІМʼЯ, а не порожнє місце
    # поруч зі знаком відсотка.
    def probability_reading
      return t("ui.measurement.not_measured") if probability_score.nil?

      t(".probability", value: formatted_probability)
    end

    # 🔴 [ARCH.84] Доти відсутність даних друкувалась як `-0.04%` — ВИГАДАНЕ
    # точне число, однакове в чотирьох локалях, під підписом «Economic Impact».
    # Тобто картка без жодного прогнозу стверджувала конкретний збиток, ще й
    # смарагдовим кольором (бо `nil.to_f` не відʼємний), — текст казав одне,
    # колір протилежне. Тепер «не виміряно» має ІМʼЯ й власний нейтральний
    # стан: станів ТРИ, і третій не є ні добрим, ні поганим.
    def impact_assessment
      div(class: "mt-4 pt-4 border-t border-emerald-900/50 flex justify-between items-center") do
        span(class: "text-mini uppercase text-gray-600") { t(".economic_impact") }
        span(class: tokens("text-xs font-mono", confidence_text_class)) do
          plain impact_reading
        end
      end
    end

    def impact_reading
      return t("ui.measurement.not_measured") if yield_impact.nil?

      t(".impact_value", value: yield_impact)
    end

    # [UI.13] Присуд founder 2026-08-14: критичний прогноз ДІСТАЄ власний
    # візуальний стан — і сигналом є ЗНАК `yield_impact`, не поріг імовірності.
    #
    # Підстава вибору сигналу: він УЖЕ живе в цьому файлі (`impact_assessment`
    # фарбує ним сусідній рядок), тобто ми нічого не вводимо. Поріг на
    # `probability_score` виглядав інтуїтивнішим («95 % посухи має бути
    # червоним»), але число довелось би взяти зі стелі — дому для «яка
    # ймовірність тривожна» в платформі немає, і це рівно той клас, що
    # закривав [UI.10] (00_07 §🗄️).
    #
    # ⚠️ Доти тут стояла МЕРТВА від народження гілка `insight_type ==
    # "emergency"` ([TEST.12]) — значення, якого enum не приймав ніколи, тож
    # високоймовірний негативний прогноз не міг почервоніти в принципі, а
    # зеленою її тримала фікстура, що подавала неможливе значення.
    def yield_impact
      @insight.prediction_data&.dig("yield_impact").presence
    end

    def adverse_forecast?
      yield_impact.to_f.negative?
    end

    # Невиміряне не є ні добрим, ні поганим — і колір теж є твердженням, тож
    # третій стан мусить бути нейтральним, а не «зеленим за замовчуванням».
    # ⚠️ Нейтраль тут тема-ІНВАРІАНТНА свідомо: поверхня картки (`bg-zinc-950`)
    # з темою не фліпається, тож токен, що фліпається, дав би на ній
    # недосяжну AA — виміряний урок (00_07 §🗄️ UI.10).
    def unmeasured_impact?
      yield_impact.nil?
    end

    # Дім сигналу ОДИН: доти деривація стояла двома копіями (тут і в
    # `impact_text_color`), тобто картка могла показати червоний вплив під
    # зеленим індикатором — стан, у якому два вузли однієї картки
    # суперечать одне одному.
    def confidence_text_class
      return "text-gray-400" if unmeasured_impact?

      adverse_forecast? ? "text-red-500" : "text-emerald-500"
    end

    # [UI.1] Смуга й індикатор доти малювались інлайн-`style:` із зашитим
    # `#10b981` — а це виміряна СЛІПА ЗОНА обох токен-інструментів: і
    # `gaia:lint_tokens`, і `design_token_existence_spec` скануть КЛАСИ, тож
    # колір без класу для них не існує. Це були ОБИДВА відомі сайти класу.
    # Ширина лишається інлайн свідомо — вона рантайм-значення, класу не має.
    def confidence_bar_class
      return "bg-gray-500" if unmeasured_impact?

      adverse_forecast? ? "bg-red-500 shadow-[0_0_15px_#ef4444]" : "bg-emerald-500 shadow-[0_0_15px_#10b981]"
    end
  end
end
