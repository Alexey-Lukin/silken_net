# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module TreeFamilies
  class Form < ApplicationComponent
    def initialize(family:)
      @family = family
    end

    def view_template
      div(class: "max-w-2xl mx-auto animate-in zoom-in duration-500") do
        form_with(model: @family, class: "space-y-8 p-10 border border-gaia-border bg-gaia-surface shadow-sm dark:shadow-none") do |f|
          # [SEC.25] Форма рендериться контролером на 422 у ДВОХ екшенах, і доти не
          # мала куди покласти причину: єдиним сигналом відмови лишалась зміна
          # заголовка сторінки. Канал (статус) полагодили раніше, споживача — тут.
          render Views::Shared::UI::ErrorSummary.new(messages: @family.errors.full_messages)

          div(class: "grid grid-cols-1 md:grid-cols-2 gap-6") do
            field_container(f, :name, t(".species_identity")) { f.text_field :name, class: input_classes, placeholder: t(".species_placeholder") }
            field_container(f, :scientific_name, t(".scientific_name")) { f.text_field :scientific_name, class: input_classes, placeholder: t(".scientific_placeholder") }
            field_container(f, :critical_z_min, t(".critical_z_min")) { f.number_field :critical_z_min, step: 0.1, class: input_classes }
            field_container(f, :critical_z_max, t(".critical_z_max")) { f.number_field :critical_z_max, step: 0.1, class: input_classes }
            field_container(f, :carbon_sequestration_coefficient, t(".co2_coefficient")) { f.number_field :carbon_sequestration_coefficient, step: 0.01, class: input_classes, placeholder: t(".co2_placeholder") }
            field_container(f, :sap_flow_index, t(".sap_flow")) { f.number_field :sap_flow_index, step: 0.01, class: input_classes }
            field_container(f, :bark_thickness, t(".bark_thickness")) { f.number_field :bark_thickness, class: input_classes }
          end

          div(class: "pt-10 border-t border-gaia-border") do
            f.submit t(".submit"), class: submit_classes
          end
        end
      end
    end

    private

    def field_container(form, attribute, label_text, &block)
      div(class: "space-y-2") do
        form.label attribute, label_text, class: "text-mini uppercase tracking-widest text-gaia-label"
        yield
      end
    end

    def input_classes
      "w-full bg-gaia-input-bg border border-gaia-input-border text-gaia-input-text p-3 font-mono text-xs " \
        "focus-visible:border-gaia-primary focus-visible:ring-2 focus-visible:ring-gaia-primary outline-none transition-all"
    end

    def submit_classes
      "w-full py-4 bg-gaia-primary/10 border border-gaia-primary text-gaia-primary uppercase text-xs tracking-widest " \
        "hover:bg-gaia-primary hover:text-black transition-all cursor-pointer " \
        "disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
    end
  end
end
