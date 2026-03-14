# frozen_string_literal: true

module Views
  module Shared
    module UI
      class PhotoCard < ApplicationComponent
        # @param photo [ActiveStorage::Blob] must respond to :filename, :byte_size, :representable?
        # @param record [MaintenanceRecord] parent record for delete path
        # @param editable [Boolean] show delete button
        def initialize(photo:, record:, editable: false)
          raise ArgumentError, "photo must respond to :filename" unless photo.respond_to?(:filename)

          @photo    = photo
          @record   = record
          @editable = editable
        end

        def view_template
          div(class: "relative group border border-emerald-900/50 hover:border-emerald-500 transition-all overflow-hidden bg-zinc-950") do
            render_preview
            render_meta_overlay
            render_delete_button if @editable
          end
        end

        private

        def render_preview
          a(
            href: helpers.rails_blob_path(@photo, disposition: "inline"),
            target: "_blank",
            rel: "noopener noreferrer",
            aria_label: "View photo: #{@photo.filename}",
            class: "block aspect-square overflow-hidden focus:outline-none focus:ring-2 focus:ring-emerald-500"
          ) do
            if @photo.representable?
              img(
                src: helpers.rails_representation_path(@photo.variant(:thumb)),
                alt: @photo.filename.to_s,
                loading: "lazy",
                class: "w-full h-full object-cover hover:scale-105 transition-transform duration-300"
              )
            else
              render_file_fallback
            end
          end
        end

        def render_file_fallback
          div(class: "w-full h-full flex flex-col items-center justify-center space-y-1 p-2 bg-zinc-900") do
            span(class: "text-emerald-700 text-2xl", aria_hidden: "true") { "📎" }
            span(class: "text-[9px] text-emerald-700 font-mono truncate text-center") { @photo.filename.to_s }
            span(class: "text-[8px] text-gray-600") { helpers.number_to_human_size(@photo.byte_size) }
          end
        end

        def render_meta_overlay
          div(class: "absolute bottom-0 inset-x-0 bg-black/80 p-1.5 opacity-0 group-hover:opacity-100 transition-opacity") do
            p(class: "text-[8px] font-mono text-emerald-400 truncate") { @photo.filename.to_s }
            p(class: "text-[7px] text-gray-500") { helpers.number_to_human_size(@photo.byte_size) }
          end
        end

        def render_delete_button
          div(class: "absolute top-1 right-1 opacity-0 group-hover:opacity-100 transition-opacity") do
            button_to(
              "×",
              helpers.api_v1_maintenance_record_photo_path(@record, @photo),
              method: :delete,
              aria: { label: "Remove photo: #{@photo.filename}" },
              class: "h-6 w-6 bg-red-900/80 text-red-200 text-sm font-bold hover:bg-red-700 " \
                     "focus:outline-none focus:ring-2 focus:ring-red-500 transition-colors",
              data: { turbo_confirm: "Remove this photo from the evidence record?" }
            )
          end
        end
      end
    end
  end
end
