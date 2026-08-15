# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Maintenance
  # Відображає сітку фотодоказів з Turbo Frame пагінацією.
  # Перша сторінка (6 фото) рендериться серверно в Show.
  # "Load More" підвантажує наступну сторінку через той самий Turbo Frame
  # без перезавантаження сторінки — файли вже на S3/CDN.
  class PhotoGallery < ApplicationComponent
    PHOTOS_PER_PAGE = 6

    # [UI.4] Дім КЛЮЧА кнопки «показати ще»: `PhotosPage` малює ту саму кнопку, але
    # автоскоуп `t(".load_more")` дав би там `maintenance.photos_page.*` — ключа, якого
    # немає. Константа робить залежність видимою: перейменування скоупа галереї тепер
    # ламає рядок ГУЧНО, а не тихо (`i18n-tasks` абсолютний ключ у чужому файлі не судить).
    LOAD_MORE_KEY = "maintenance.photo_gallery.load_more"

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

    # 🔴 [UI.4] Дім target-id галереї: цю адресу називали рукою ЧОТИРИ рази у двох
    # файлах (тут ×2 і в `PhotosPage` ×2), а вона є ціллю Turbo-фрейма — тобто
    # розходження не має симптому: «Показати ще» просто перестає замінювати вміст.
    # Той самий клас, що `wallet_balance_frame_`, лише всередині однієї родини.
    def self.frame_dom_id(record_id) = "maintenance_photos_#{record_id}"

    # Сітка сторінки пагінації — ціль, яку `PhotosPage` мусить назвати ІДЕНТИЧНО.
    def self.grid_dom_id(page) = "photos_grid_page_#{page}"

    private

    def frame_id = self.class.frame_dom_id(@record.id)

    def render_header
      div(class: "flex justify-between items-center") do
        div(class: "text-mini uppercase tracking-widest text-emerald-700") do
          total = @pagy.count
          "#{t('.evidence_heading')} // #{t('.photo_count', count: total)}"
        end
        span(class: "text-micro text-gray-600 font-mono") do
          t(".page_of", page: @pagy.page, total: @pagy.last)
        end
      end
    end

    def render_grid
      if @photos.any?
        div(
          class: "grid grid-cols-2 sm:grid-cols-3 gap-3",
          id: self.class.grid_dom_id(@pagy.page)
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
      next_url  = photos_maintenance_record_path(@record, page: @pagy.next)

      div(class: "mt-4 text-center") do
        a(
          href: next_url,
          data: { turbo_frame: frame_id },
          class: "inline-block px-6 py-2 border border-emerald-900 text-emerald-700 " \
                 "hover:border-emerald-500 hover:text-emerald-500 uppercase text-mini " \
                 "tracking-widest transition-all font-mono"
        ) do
          t(".load_more", remaining: [ remaining, 0 ].max)
        end
      end
    end

    def render_empty_state
      render Views::Shared::UI::EmptyState.new(
        title: t(".empty.title"),
        icon: "📷",
        description: t(".empty.description")
      )
    end
  end
end
