# frozen_string_literal: true

module TreeFamilies
  class Form < ApplicationComponent
    def initialize(family:)
      @family = family
    end

    def view_template
      div(class: "max-w-2xl mx-auto animate-in zoom-in duration-500") do
        form_with(model: [ :api, :v1, @family ], class: "space-y-8 p-10 border border-gaia-border bg-gaia-surface shadow-sm dark:shadow-none") do |f|
          div(class: "grid grid-cols-1 md:grid-cols-2 gap-6") do
            field_container(f, :name, "Species Identity") { f.text_field :name, class: input_classes, placeholder: "e.g. Дуб звичайний" }
            field_container(f, :scientific_name, "Scientific Name (Latin)") { f.text_field :scientific_name, class: input_classes, placeholder: "e.g. Quercus robur" }
            field_container(f, :baseline_impedance, "Baseline Impedance (kΩ)") { f.number_field :baseline_impedance, step: 0.1, class: input_classes }
            field_container(f, :critical_z_min, "Critical Z Min") { f.number_field :critical_z_min, step: 0.1, class: input_classes }
            field_container(f, :critical_z_max, "Critical Z Max") { f.number_field :critical_z_max, step: 0.1, class: input_classes }
            field_container(f, :carbon_sequestration_coefficient, "CO₂ Sequestration Coefficient") { f.number_field :carbon_sequestration_coefficient, step: 0.01, class: input_classes, placeholder: "1.0" }
            field_container(f, :sap_flow_index, "Sap Flow Index") { f.number_field :sap_flow_index, step: 0.01, class: input_classes }
            field_container(f, :bark_thickness, "Bark Thickness (mm)") { f.number_field :bark_thickness, class: input_classes }
          end

          div(class: "pt-10 border-t border-gaia-border") do
            f.submit "WRITE GENETIC CODE", class: submit_classes
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
