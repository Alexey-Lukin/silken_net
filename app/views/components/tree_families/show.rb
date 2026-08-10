# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# app/views/components/tree_families/show.rb
module TreeFamilies
  class Show < ApplicationComponent
    def initialize(family:)
      @family = family
    end

    def view_template
      div(class: "space-y-10 animate-in slide-in-from-right duration-700") do
        render_hero

        div(class: "grid grid-cols-1 lg:grid-cols-2 gap-8") do
          render_threshold_viz
          render_biological_props
        end
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
        p(class: "text-tiny font-mono text-emerald-700 uppercase tracking-[0.4em] mt-4") { t(".baseline_info", baseline: @family.baseline_impedance, coef: @family.carbon_sequestration_coefficient) }
      end
    end

    def render_threshold_viz
      div(class: "p-8 border border-emerald-900 bg-black space-y-8") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".scale_title") }

        # Візуальна шкала
        div(class: "relative pt-10 pb-4") do
          # Лінія шкали
          div(class: "h-px w-full bg-emerald-900/50")

          # Маркери
          marker(@family.death_threshold_impedance, t(".markers.death"), "bg-red-900")
          marker(@family.critical_z_min, t(".markers.safe_min"), "bg-emerald-500")
          marker(@family.baseline_impedance, t(".markers.baseline"), "bg-white", active: true)
          marker(@family.critical_z_max, t(".markers.safe_max"), "bg-emerald-500")
        end
      end
    end

    def marker(value, label, color, active: false)
      # Дуже спрощена логіка позиціонування для прикладу
      left = [ (value.to_f / (@family.critical_z_max * 1.2) * 100), 100 ].min
      div(class: "absolute top-0 flex flex-col items-center", style: "left: #{left}%") do
         span(class: "text-micro text-gray-600 mb-2 font-mono") { t(".marker_value", value: value) }
         div(class: tokens("h-3 w-px", "bg-white": active, "bg-emerald-900": !active))
         span(class: tokens("mt-4 text-micro uppercase tracking-tighter", "text-white": active, "text-gray-700": !active)) { label }
      end
    end

    def render_biological_props
      div(class: "p-8 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { t(".props_title") }
        div(class: "space-y-4 font-mono text-compact") do
          prop_row(t(".props.co2"), @family.carbon_sequestration_coefficient)
          prop_row(t(".props.sap_flow"), @family.sap_flow_index || t(".defaults.zero"))
          prop_row(t(".props.bark_thickness"), t(".props.bark_thickness_value", value: @family.bark_thickness || 0))
          prop_row(t(".props.foliage_density"), t(".props.foliage_density_value", value: @family.foliage_density || 0))
          # [TEST.12] Значення — ПОРІГ температури в °C (`AlertDispatchService`
          # звіряє його з `telemetry_log.temperature_c`, дефолт 60), а не якісний
          # рейтинг, хоч мітка читається саме так. Без одиниці — як у сусідів
          # вище — адміністратор, що введе «3» за лісівничою шкалою, дістав би
          # пожежну тривогу на кожній телеметрії вище 3 °C.
          prop_row(t(".props.fire_rating"),
                   if @family.fire_resistance_rating
                     t(".props.fire_rating_value", value: @family.fire_resistance_rating)
                   else
                     t(".defaults.not_available")
                   end)
        end
      end
    end

    def prop_row(label, value)
      div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
        span(class: "text-gray-600") { label }
        span(class: "text-emerald-100") { value }
      end
    end
  end
end
