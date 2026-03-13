# frozen_string_literal: true

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
      render Views::Shared::UI::PhotoCard.new(photo: photo, record: @record, editable: @editable)
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
