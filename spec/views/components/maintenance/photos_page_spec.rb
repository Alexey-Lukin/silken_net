# frozen_string_literal: true

require "rails_helper"

RSpec.describe Maintenance::PhotosPage do
  def mock_pagy(count: 6, page: 2, next_page: nil)
    pg = OpenStruct.new(
      count: count, page: page, last: [(count / 6.0).ceil, 1].max,
      from: 7, to: [count, 12].min,
      prev: 1, next: next_page, vars: { items: 6 }
    )
    pg.define_singleton_method(:series) { [1, 2] }
    pg
  end

  def mock_record(id: 11)
    r = OpenStruct.new(id: id)
    r.define_singleton_method(:model_name) { ActiveModel::Name.new(MaintenanceRecord) }
    r.define_singleton_method(:to_key) { [id] }
    r.define_singleton_method(:to_param) { id.to_s }
    r
  end

  def render_component(record:, photos:, pagy:, editable: false)
    ApplicationController.renderer.render(
      component_class.new(record: record, photos: photos, pagy: pagy, editable: editable),
      layout: false
    )
  end

  let(:record) { mock_record }
  let(:pagy) { mock_pagy }
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
      pagy_with_next = mock_pagy(count: 18, page: 2, next_page: 3)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("Load More")
    end

    it "does not render load more when on last page" do
      html = render_component(record: record, photos: [], pagy: mock_pagy(count: 6, page: 2, next_page: nil))
      expect(html).not_to include("Load More")
    end

    it "includes correct next page in load more link" do
      pagy_with_next = mock_pagy(count: 18, page: 2, next_page: 3)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("page=3")
    end

    it "targets the same maintenance_photos frame in load more" do
      pagy_with_next = mock_pagy(count: 18, page: 2, next_page: 3)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("maintenance_photos_11")
    end
  end

  describe "editable mode" do
    it "renders without errors in non-editable mode" do
      expect(html).to include("photos_grid_page_2")
    end
  end
end
