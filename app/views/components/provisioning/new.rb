# SPDX-License-Identifier: AGPL-3.0-or-later
module Provisioning
  class New < ApplicationComponent
    def initialize(clusters:, families:, device: nil)
      @clusters = clusters
      @families = families
      @device = device
    end

    def view_template
      div(class: "max-w-3xl mx-auto animate-in fade-in duration-1000") do
        header_section

        form_with(url: register_api_v1_provisioning_index_path, scope: :provisioning, class: "space-y-8 p-10 border border-emerald-900 bg-black/60 backdrop-blur-md shadow-2xl") do |f|
          render_errors if @device&.errors&.any?

          div(class: "grid grid-cols-1 md:grid-cols-2 gap-8") do
            field_container(t(".fields.hardware_uid")) do
              f.text_field :hardware_uid, class: input_classes, placeholder: t(".fields.hardware_uid_placeholder"), required: true
            end

            field_container(t(".fields.node_class")) do
              f.select :device_type, [ [ t(".fields.soldier"), "tree" ], [ t(".fields.queen"), "gateway" ] ], {}, class: input_classes
            end

            field_container(t(".fields.cluster")) do
              f.collection_select :cluster_id, @clusters, :id, :name, {}, class: input_classes
            end

            field_container(t(".fields.family")) do
              f.collection_select :family_id, @families, :id, :name, {}, class: input_classes
            end

            field_container(t(".fields.latitude")) do
              f.text_field :latitude, class: input_classes, placeholder: t(".fields.latitude_placeholder"), required: true
            end

            field_container(t(".fields.longitude")) do
              f.text_field :longitude, class: input_classes, placeholder: t(".fields.longitude_placeholder"), required: true
            end
          end

          div(class: "pt-10 border-t border-emerald-900/30") do
            f.submit t(".submit"), class: "w-full py-4 bg-emerald-500/10 border border-emerald-500 text-emerald-500 uppercase text-xs tracking-[0.3em] hover:bg-emerald-500 hover:text-black transition-all cursor-pointer shadow-[0_0_30px_rgba(16,185,129,0.1)]"
          end
        end
      end
    end

    private

    def header_section
      div(class: "text-center mb-10 space-y-2") do
        p(class: "text-tiny font-mono text-emerald-900 uppercase tracking-[0.5em]") { t(".subtitle") }
      end
    end

    def field_container(label, &block)
      div(class: "space-y-2") do
        label(class: "text-mini uppercase tracking-widest text-gray-600") { label }
        yield
      end
    end

    def input_classes
      "w-full bg-zinc-950 border border-emerald-900/50 text-emerald-100 p-3 font-mono text-xs focus-visible:border-emerald-500 outline-none transition-all"
    end

    def render_errors
      div(class: "p-4 border border-red-900 bg-red-950/20 text-red-500 text-xs font-mono") do
        p { t(".errors_title") }
        ul(class: "list-disc ml-4 mt-2") do
          @device.errors.full_messages.each { |msg| li { msg } }
        end
      end
    end
  end
end
