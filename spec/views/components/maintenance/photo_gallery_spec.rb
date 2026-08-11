# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.6] Лише блоб-стаби — маршрут-хелпер справжній (див. `photo_card_spec`).
unless Views::Shared::UI::PhotoCard.method_defined?(:_test_blob_helpers_stubbed)
  Views::Shared::UI::PhotoCard.prepend(Module.new do
    def _test_blob_helpers_stubbed = true
    def rails_blob_path(*, **) = "/rails/blobs/mock"
    def rails_representation_path(*, **) = "/rails/representations/mock"
  end)
end

RSpec.describe Maintenance::PhotoGallery do
  # [TEST.12] Реальний `Pagy::Offset` — той самий клас, що будує прод (`Maintenance::Form`),
  # тож `last`/`next` тепер ВИВОДЯТЬСЯ з `count`, а не переписуються формулою у фікстурі.
  def build_pagy(count: 6, page: 1)
    Pagy::Offset.new(count: count, page: page, limit: Maintenance::PhotoGallery::PHOTOS_PER_PAGE)
  end

  def build_record(id: 5) = MaintenanceRecord.new(id: id)

  # Форма фото — та, яку `PhotoCard` РЕАЛЬНО читає (`filename`/`byte_size`/`representable?`
  # напряму, не через `.blob`). Доти тут лежав мок протилежної форми, і саме тому він був
  # МЕРТВИЙ: жоден приклад його не викликав, бо підключений він би впав на `.filename`.
  def build_photo(name: "evidence.jpg")
    photo = OpenStruct.new(
      filename: ActiveStorage::Filename.new(name),
      byte_size: 120_000,
      representable?: true
    )
    photo.define_singleton_method(:variant) { |_style| "variant_thumb" }
    photo
  end

  def render_component(record:, photos:, pagy:, editable: false)
    ApplicationController.renderer.render(
      component_class.new(record: record, photos: photos, pagy: pagy, editable: editable),
      layout: false
    )
  end

  let(:record) { build_record }
  let(:pagy) { build_pagy(count: 4, page: 1) }
  let(:html) { render_component(record: record, photos: [], pagy: pagy) }

  describe "turbo frame ID" do
    it "renders the turbo frame with correct record id" do
      expect(html).to include('id="maintenance_photos_5"')
    end
  end

  describe "header" do
    it "renders the Evidence Protocol heading" do
      expect(html).to include("Evidence Protocol")
    end

    it "renders the total photo count" do
      expect(html).to include("4 Photos")
    end

    it "renders singular photo label for count of 1" do
      html = render_component(record: record, photos: [], pagy: build_pagy(count: 1, page: 1))
      expect(html).to include("1 Photo")
    end

    it "renders page indicator" do
      expect(html).to include("Page 1 of")
    end
  end

  describe "empty state" do
    it "renders empty state when photos list is empty" do
      expect(html).to include("No Photos")
    end
  end

  describe "load more link" do
    it "renders load more link when pagy.next is present" do
      pagy_with_next = build_pagy(count: 12, page: 1)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("Load More")
    end

    it "does not render load more link when on last page" do
      html = render_component(record: record, photos: [], pagy: build_pagy(count: 4, page: 1))
      expect(html).not_to include("Load More")
    end

    it "includes remaining count in load more link" do
      pagy_with_next = build_pagy(count: 12, page: 1)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("remaining")
    end

    it "includes the next page URL in the load more link" do
      pagy_with_next = build_pagy(count: 12, page: 1)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("page=2")
    end
  end

  describe "populated gallery" do
    # 🔴 Доти ЖОДЕН приклад файлу не подавав фото — усі рендери йшли з `photos: []`, а
    # приклад із назвою «when photos are present» подавав порожній масив і пінив «No Photos»,
    # визнаючи це власним коментарем. Тобто гілка `@photos.any?` — та, що виконується на
    # КОЖНОМУ записі з доказами, — не виконувалась у сюїті жодного разу.
    let(:photos) { [ build_photo(name: "evidence.jpg"), build_photo(name: "second.jpg") ] }
    let(:filled) do
      render_component(record: record, photos: photos, pagy: build_pagy(count: 2, page: 1))
    end

    it "renders the page-specific grid instead of the empty state" do
      expect(filled).to include('id="photos_grid_page_1"')
      expect(filled).not_to include("No Photos")
    end

    it "renders one card per photo" do
      expect(filled).to include("evidence.jpg")
      expect(filled).to include("second.jpg")
    end
  end
end
