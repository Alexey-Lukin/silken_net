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

RSpec.describe Maintenance::PhotosPage do
  # [TEST.12] Реальний `Pagy::Offset` — той самий клас, що будує прод; доти фікстура
  # переписувала формулу сторінок власноруч і задавала `next` НЕЗАЛЕЖНО від `count`.
  def build_pagy(count: 6, page: 2)
    Pagy::Offset.new(count: count, page: page, limit: Maintenance::PhotoGallery::PHOTOS_PER_PAGE)
  end

  def build_record(id: 11) = MaintenanceRecord.new(id: id)

  def build_photo(name: "evidence.jpg")
    photo = OpenStruct.new(
      filename: ActiveStorage::Filename.new(name),
      byte_size: 1_024_000,
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
  let(:pagy) { build_pagy }
  let(:html) { render_component(record: record, photos: [], pagy: pagy) }

  describe "turbo frame" do
    it "renders a turbo frame with the correct record id" do
      expect(html).to include('id="maintenance_photos_11"')
    end

    it "uses the maintenance_photos_id pattern" do
      expect(html).to include("maintenance_photos_11")
    end
  end

  describe "photo grid" do
    it "renders the page-specific grid ID for page 2" do
      expect(html).to include('id="photos_grid_page_2"')
    end

    it "renders an empty grid when no photos" do
      expect(html).to include("photos_grid_page_2")
    end
  end

  describe "load more link" do
    it "renders load more when pagy.next is present" do
      pagy_with_next = build_pagy(count: 18, page: 2)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("Load More")
    end

    it "does not render load more when on last page" do
      html = render_component(record: record, photos: [], pagy: build_pagy(count: 6, page: 2))
      expect(html).not_to include("Load More")
    end

    it "includes correct next page in load more link" do
      pagy_with_next = build_pagy(count: 18, page: 2)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("page=3")
    end

    it "targets the same maintenance_photos frame in load more" do
      pagy_with_next = build_pagy(count: 18, page: 2)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("maintenance_photos_11")
    end
  end

  describe "editable mode" do
    # 🔴 Доти цей блок ніколи не ставив `editable: true` — тобто єдине, що цей прапорець
    # вмикає (кнопка видалення фото), не перевірялось у жодному прикладі, а назва обіцяла
    # «editable mode». Дефолт fail-closed, тож пара потрібна ОБИДВА боки: негативний
    # доводить, що кнопки нема без права, позитивний — що проводка `editable:` жива.
    it "renders the delete button only when editable" do
      photos = [ build_photo ]
      editable = render_component(record: record, photos: photos, pagy: build_pagy, editable: true)
      readonly = render_component(record: record, photos: photos, pagy: build_pagy, editable: false)

      expect(editable).to include(maintenance_record_photo_path(record, photos.first))
      expect(readonly).not_to include(maintenance_record_photo_path(record, photos.first))
    end

    it "renders without errors in non-editable mode" do
      expect(html).to include("photos_grid_page_2")
    end
  end

  describe "photo card rendering" do
    it "renders PhotoCard for each photo" do
      html = render_component(record: record, photos: [ build_photo ], pagy: build_pagy)
      expect(html).to include("evidence.jpg")
    end
  end
end
