# frozen_string_literal: true

module Views
  module Components
    module Maintenance
      # Рендерить ТІЛЬКИ вміст Turbo Frame для пагінованого завантаження фото.
      # Використовується в `photos` action контролера.
      # Turbo замінює вміст фрейму `maintenance_photos_:id` новою сторінкою.
      class PhotosPage < ApplicationComponent
        def initialize(record:, photos:, pagy:, editable: false)
          @record   = record
          @photos   = photos
          @pagy     = pagy
          @editable = editable
        end

        def view_template
          # Turbo Frame з тим самим id — замінює вміст попереднього фрейму
          turbo_frame_tag("maintenance_photos_#{@record.id}") do
            render_grid
            render_load_more
          end
        end

        private

        def render_grid
          div(
            class: "grid grid-cols-2 sm:grid-cols-3 gap-3",
            id: "photos_grid_page_#{@pagy.page}"
          ) do
            @photos.each { |photo| render_photo_card(photo) }
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
                div(class: "w-full h-full flex flex-col items-center justify-center space-y-1 p-2 bg-zinc-900") do
                  span(class: "text-emerald-700 text-2xl") { "📎" }
                  span(class: "text-[9px] text-emerald-700 font-mono truncate text-center") { photo.filename.to_s }
                  span(class: "text-[8px] text-gray-600") { helpers.number_to_human_size(photo.byte_size) }
                end
              end
            end

            div(class: "absolute bottom-0 inset-x-0 bg-black/80 p-1.5 opacity-0 group-hover:opacity-100 transition-opacity") do
              p(class: "text-[8px] font-mono text-emerald-400 truncate") { photo.filename.to_s }
              p(class: "text-[7px] text-gray-500") { helpers.number_to_human_size(photo.byte_size) }
            end

            if @editable
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
          end
        end

        def render_load_more
          return unless @pagy.next

          remaining = [ @pagy.count - (@pagy.page * PhotoGallery::PHOTOS_PER_PAGE), 0 ].max
          next_url  = helpers.photos_api_v1_maintenance_record_path(@record, page: @pagy.next)

          div(class: "mt-4 text-center") do
            a(
              href: next_url,
              data: { turbo_frame: "maintenance_photos_#{@record.id}" },
              class: "inline-block px-6 py-2 border border-emerald-900 text-emerald-700 " \
                     "hover:border-emerald-500 hover:text-emerald-500 uppercase text-[9px] " \
                     "tracking-widest transition-all font-mono"
            ) { "Load More // #{remaining} remaining →" }
          end
        end
      end
    end
  end
end
