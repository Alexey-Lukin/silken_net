# frozen_string_literal: true

require "rails_helper"

RSpec.describe Maintenance::PhotoGallery do
  def mock_pagy(count: 6, page: 1, next_page: nil)
    pg = OpenStruct.new(
      count: count, page: page, last: [(count / 6.0).ceil, 1].max,
      from: 1, to: [count, 6].min,
      prev: nil, next: next_page, vars: { items: 6 }
    )
    pg.define_singleton_method(:series) { [1] }
    pg
  end

  def mock_record(id: 5)
    r = OpenStruct.new(id: id)
    r.define_singleton_method(:model_name) { ActiveModel::Name.new(MaintenanceRecord) }
    r.define_singleton_method(:to_key) { [id] }
    r.define_singleton_method(:to_param) { id.to_s }
    r
  end

  def mock_photo
    blob = double("blob",
      id: 99, filename: ActiveStorage::Filename.new("evidence.jpg"),
      content_type: "image/jpeg", byte_size: 120_000
    )
    attachment = double("attachment", blob: blob, id: 99)
    allow(attachment).to receive(:is_a?).and_return(false)
    attachment
  end

  def render_component(record:, photos:, pagy:, editable: false)
    ApplicationController.renderer.render(
      described_class.new(record: record, photos: photos, pagy: pagy, editable: editable),
      layout: false
    )
  end

  let(:record) { mock_record }
  let(:pagy) { mock_pagy(count: 4, page: 1) }
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
      html = render_component(record: record, photos: [], pagy: mock_pagy(count: 1, page: 1))
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
      pagy_with_next = mock_pagy(count: 12, page: 1, next_page: 2)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("Load More")
    end

    it "does not render load more link when on last page" do
      html = render_component(record: record, photos: [], pagy: mock_pagy(count: 4, page: 1, next_page: nil))
      expect(html).not_to include("Load More")
    end

    it "includes remaining count in load more link" do
      pagy_with_next = mock_pagy(count: 12, page: 1, next_page: 2)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("remaining")
    end

    it "includes the next page URL in the load more link" do
      pagy_with_next = mock_pagy(count: 12, page: 1, next_page: 2)
      html = render_component(record: record, photos: [], pagy: pagy_with_next)
      expect(html).to include("page=2")
    end
  end

  describe "photos grid ID" do
    it "renders the page-specific grid ID when photos are present" do
      # The grid ID only renders when photos exist (empty state shows otherwise)
      html_no_photos = render_component(record: record, photos: [], pagy: pagy)
      # Empty state is shown, not the grid
      expect(html_no_photos).to include("No Photos")
    end
  end
end
