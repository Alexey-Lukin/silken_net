# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# app/views/components/tree_families/show.rb
module TreeFamilies
  class Show < ApplicationComponent
    def initialize(family:)
      @family = family
    end

    def view_template
      div(class: "space-y-10") do
        render_hero

        render_biological_props
      end
    end

    private

    def render_hero
      div(class: "p-10 border border-emerald-900 bg-zinc-950 relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[120px] font-bold text-emerald-900/5 select-none uppercase", aria_hidden: "true") { @family.name.first(3) }

        h2(class: "text-5xl font-extralight tracking-tighter text-white") { @family.name }
        if @family.scientific_name.present?
          p(class: "text-sm italic text-emerald-500 mt-2") { @family.scientific_name }
        end
        p(class: "text-tiny font-mono text-emerald-700 uppercase tracking-[0.4em] mt-4") { t(".carbon_info", coef: @family.carbon_sequestration_coefficient) }
      end
    end

    def render_biological_props
      div(class: "p-8 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { t(".props_title") }
        div(class: "space-y-4 font-mono text-compact") do
          prop_row(t(".props.co2"), @family.carbon_sequestration_coefficient)
          prop_row(t(".props.sap_flow"), measured_prop(@family.sap_flow_index))
          prop_row(t(".props.bark_thickness"),
                   measured_prop(@family.bark_thickness) { |v| t(".props.bark_thickness_value", value: v) })
          prop_row(t(".props.foliage_density"),
                   measured_prop(@family.foliage_density) { |v| t(".props.foliage_density_value", value: v) })
          # [TEST.12] Значення — ПОРІГ температури в °C (`AlertDispatchService`
          # звіряє його з `telemetry_log.temperature_c`, дефолт 60), а не якісний
          # рейтинг, хоч мітка читається саме так. Без одиниці — як у сусідів
          # вище — адміністратор, що введе «3» за лісівничою шкалою, дістав би
          # пожежну тривогу на кожній телеметрії вище 3 °C.
          prop_row(t(".props.fire_rating"),
                   measured_prop(@family.fire_resistance_rating) { |v| t(".props.fire_rating_value", value: v) })
        end
      end
    end

    # [ARCH.84] Дім стану «не виміряно» один на всі поверхні — `ui.measurement.not_measured`,
    # той самий, що віддає `measured_value` на сенсорних величинах. Власний хелпер
    # родина потребує лише тому, що ОДИНИЦЯ тут локалізована («mm» ⊥ «мм»), тож
    # зашити її аргументом, як робить `measured_value`, не можна; спільним лишається
    # саме рішення про порожнечу, а не форматування.
    #
    # 🔴 Нуль тут не нейтральний: `sap_flow_index` МНОЖИТЬ поріг шкідників у
    # `AlertDispatchService` (`DEFAULT_PEST_THRESHOLD * sap_flow_index`), тож
    # надрукований «0.0» був рівно тим числом, яке робить порогом нуль — і сусідня
    # форма дозволяє його ввести, бо валідація нуль приймає.
    # ⚠️ Одиниця приходить БЛОКОМ, а не ключем-аргументом, і це не стиль: перша
    # редакція брала `unit_key` рядком, тож `t(".props.…_value")` переставав бути
    # ЛІТЕРАЛОМ — і `i18n-tasks unused` виріс на 12 ключів (622 → 634), тобто три
    # живі одиниці × 4 локалі стали кандидатами на видалення. Той сканер не
    # входить у pre-push-трійку, тож регресія поїхала б мовчки (§Guard-craft #23:
    # One-Home ОСЛІПЛЮЄ гейт, що ключувався на літеральній формі значення).
    def measured_prop(value)
      return t("ui.measurement.not_measured") if value.nil?

      block_given? ? yield(value) : value
    end

    def prop_row(label, value)
      div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
        span(class: "text-gray-600") { label }
        span(class: "text-emerald-100") { value }
      end
    end
  end
end
