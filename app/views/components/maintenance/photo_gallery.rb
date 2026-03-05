# frozen_string_literal: true

module Views
  module Components
    module Maintenance
      # Відображає сітку фотодоказів з Turbo Frame пагінацією.
      # Перша сторінка (6 фото) рендериться серверно в Show.
      # "Load More" підвантажує наступну сторінку через той самий Turbo Frame
      # без перезавантаження сторінки — файли вже на S3/CDN.
      class PhotoGallery < ApplicationComponent
        PHOTOS_PER_PAGE = 6

        def initialize(record:, photos:, pagy:, editable: false)
          @record   = record
          @photos   = photos
          @pagy     = pagy
          @editable = editable
        end

        def view_template
          div(class: "space-y-3") do
            render_header

            turbo_frame_tag(frame_id) do
              render_grid
              render_load_more
            end
          end
        end

        private

        def frame_id
          "maintenance_photos_#{@record.id}"
        end

        def render_header
          div(class: "flex justify-between items-center") do
            div(class: "text-[9px] uppercase tracking-widest text-emerald-700") do
              total = @pagy.count
              "Evidence Protocol // #{total} Photo#{total == 1 ? '' : 's'}"
            end
            span(class: "text-[8px] text-gray-600 font-mono") do
              "Page #{@pagy.page} of #{@pagy.last}"
            end
          end
        end

        def render_grid
          if @photos.any?
            div(
              class: "grid grid-cols-2 sm:grid-cols-3 gap-3",
              id: "photos_grid_page_#{@pagy.page}"
            ) do
              @photos.each { |photo| render_photo_card(photo) }
            end
          else
            render_empty_state
          end
        end

        def render_photo_card(photo)
          div(class: "relative group border border-emerald-900/50 hover:border-emerald-500 transition-all overflow-hidden bg-zinc-950") do
            a(
              href: helpers.rails_blob_path(photo, disposition: "inline"),
              target: "_blank",
              class: "block aspect-square overflow-hidden"
            ) do
              if photo.representable?
                img(
                  src: helpers.rails_representation_path(photo.variant(:thumb)),
                  alt: photo.filename.to_s,
                  loading: "lazy",
                  class: "w-full h-full object-cover hover:scale-105 transition-transform duration-300"
                )
              else
                render_file_fallback(photo)
              end
            end

            render_photo_meta(photo)
            render_delete_button(photo) if @editable
          end
        end

        def render_file_fallback(photo)
          div(class: "w-full h-full flex flex-col items-center justify-center space-y-1 p-2 bg-zinc-900") do
            span(class: "text-emerald-700 text-2xl") { "📎" }
            span(class: "text-[9px] text-emerald-700 font-mono truncate text-center") { photo.filename.to_s }
            span(class: "text-[8px] text-gray-600") { helpers.number_to_human_size(photo.byte_size) }
          end
        end

        def render_photo_meta(photo)
          div(class: "absolute bottom-0 inset-x-0 bg-black/80 p-1.5 opacity-0 group-hover:opacity-100 transition-opacity") do
            p(class: "text-[8px] font-mono text-emerald-400 truncate") { photo.filename.to_s }
            p(class: "text-[7px] text-gray-500") { helpers.number_to_human_size(photo.byte_size) }
          end
        end

        def render_delete_button(photo)
          div(class: "absolute top-1 right-1 opacity-0 group-hover:opacity-100 transition-opacity") do
            button_to(
              "×",
              helpers.api_v1_maintenance_record_photo_path(@record, photo),
              method: :delete,
              class: "h-6 w-6 bg-red-900/80 text-red-200 text-sm font-bold hover:bg-red-700 transition-colors",
              data: { turbo_confirm: "Remove this photo from the evidence record?" }
            )
          end
        end

        def render_load_more
          return unless @pagy.next

          remaining = @pagy.count - (@pagy.page * PHOTOS_PER_PAGE)
          next_url  = helpers.photos_api_v1_maintenance_record_path(@record, page: @pagy.next)

          div(class: "mt-4 text-center") do
            a(
              href: next_url,
              data: { turbo_frame: frame_id },
              class: "inline-block px-6 py-2 border border-emerald-900 text-emerald-700 " \
                     "hover:border-emerald-500 hover:text-emerald-500 uppercase text-[9px] " \
                     "tracking-widest transition-all font-mono"
            ) do
              "Load More // #{[ remaining, 0 ].max} remaining →"
            end
          end
        end

        def render_empty_state
          div(class: "border border-dashed border-emerald-900/40 p-8 text-center col-span-3") do
            p(class: "text-emerald-900 uppercase tracking-widest text-[9px]") { "No Photos" }
          end
        end
      end
    end
  end
end
