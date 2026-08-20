# SPDX-License-Identifier: AGPL-3.0-or-later
module Provisioning
  class New < ApplicationComponent
    def initialize(clusters:, families:, device: nil)
      @clusters = clusters
      @families = families
      @device = device
    end

    def view_template
      div(class: "max-w-3xl mx-auto") do
        header_section

        form_with(url: register_provisioning_index_path, scope: :provisioning, class: "space-y-8 p-10 border border-gaia-border bg-gaia-surface/80 backdrop-blur-md shadow-2xl") do |f|
          # [SEC.25] Заголовок ЛИШАЄТЬСЯ власним, а не спільним «перевірку не
          # пройдено»: більшість причин тут не з валідації моделі, а з guard-клауз
          # контролера (зайнятий UID → 409, чужий кластер → 404), які кладуться в
          # `errors` лише щоб доїхати сюди. `&.` законний — `device:` дефолтить у nil.
          render Views::Shared::UI::ErrorSummary.new(
            messages: @device&.errors&.full_messages,
            title:    t(".errors_title")
          )

          div(class: "grid grid-cols-1 md:grid-cols-2 gap-8") do
            field_container(f, :hardware_uid, t(".fields.hardware_uid")) do
              f.text_field :hardware_uid, class: input_classes, placeholder: t(".fields.hardware_uid_placeholder"), required: true
            end

            field_container(f, :device_type, t(".fields.node_class")) do
              f.select :device_type, [ [ t(".fields.soldier"), "tree" ], [ t(".fields.queen"), "gateway" ] ], {}, class: input_classes
            end

            field_container(f, :cluster_id, t(".fields.cluster")) do
              f.collection_select :cluster_id, @clusters, :id, :name, {}, class: input_classes
            end

            field_container(f, :family_id, t(".fields.family")) do
              f.collection_select :family_id, @families, :id, :name, {}, class: input_classes
            end

            field_container(f, :latitude, t(".fields.latitude")) do
              f.text_field :latitude, class: input_classes, placeholder: t(".fields.latitude_placeholder"), required: true
            end

            field_container(f, :longitude, t(".fields.longitude")) do
              f.text_field :longitude, class: input_classes, placeholder: t(".fields.longitude_placeholder"), required: true
            end
          end

          div(class: "pt-10 border-t border-emerald-900/30") do
            f.submit t(".submit"), class: "w-full py-4 bg-emerald-500/10 border border-gaia-primary-strong text-gaia-primary-strong uppercase text-xs tracking-[0.3em] hover:bg-emerald-500 hover:text-black transition-all cursor-pointer shadow-[0_0_30px_rgba(16,185,129,0.1)]"
          end
        end
      end
    end

    private

    def header_section
      div(class: "text-center mb-10 space-y-2") do
        p(class: "text-tiny font-mono text-gaia-text-muted uppercase tracking-[0.5em]") { t(".subtitle") }
      end
    end

    # [UI.3] Мітка йде через `form.label`, а не через голий `label` — той не має
    # `for=`, тож скрінрідер не звʼязує підпис із полем, а клік по підпису не
    # фокусує ввід. `id` тут уже генерує білдер (`form_with scope: :provisioning`
    # → `provisioning_hardware_uid`), тобто вся робота — передати атрибут.
    # Взірець і носій — `tree_families/form` + `sessions/new_spec`.
    def field_container(form, attribute, label_text, &block)
      div(class: "space-y-2") do
        form.label attribute, label_text, class: "text-mini uppercase tracking-widest text-gaia-label"
        yield
      end
    end

    def input_classes
      "w-full bg-zinc-950 border border-emerald-900/50 text-emerald-100 p-3 font-mono text-xs focus-visible:border-emerald-500 outline-none transition-all"
    end
  end
end
