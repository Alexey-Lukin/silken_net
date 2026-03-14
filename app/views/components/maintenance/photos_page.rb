# frozen_string_literal: true

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
      render Views::Shared::UI::PhotoCard.new(photo: photo, record: @record, editable: @editable)
    end

    def render_load_more
      return unless @pagy.next

      remaining = [ @pagy.count - (@pagy.page * PhotoGallery::PHOTOS_PER_PAGE), 0 ].max
      next_url  = photos_api_v1_maintenance_record_path(@record, page: @pagy.next)

      div(class: "mt-4 text-center") do
        a(
          href: next_url,
          data: { turbo_frame: "maintenance_photos_#{@record.id}" },
          class: "inline-block px-6 py-2 border border-emerald-900 text-emerald-700 " \
                 "hover:border-emerald-500 hover:text-emerald-500 uppercase text-mini " \
                 "tracking-widest transition-all font-mono"
        ) { "Load More // #{remaining} remaining →" }
      end
    end
  end
end
