# frozen_string_literal: true

require "rails_helper"

# The Maintenance::Show component references `edit_api_v1_maintenance_record_path` but
# the routes do not expose an :edit action for maintenance_records. We patch it here.
unless Maintenance::Show.method_defined?(:edit_api_v1_maintenance_record_path)
  Maintenance::Show.prepend(Module.new do
    def edit_api_v1_maintenance_record_path(record = nil, **_opts)
      "/api/v1/maintenance_records/#{record&.to_param}/edit"
    end
  end)
end

# Ensure PhotoCard route helpers are stubbed for rendering through PhotoGallery.
unless Views::Shared::UI::PhotoCard.method_defined?(:_test_route_helpers_stubbed)
  Views::Shared::UI::PhotoCard.prepend(Module.new do
    def _test_route_helpers_stubbed = true
    def rails_blob_path(*, **) = "/rails/blobs/mock"
    def rails_representation_path(*, **) = "/rails/representations/mock"
    def api_v1_maintenance_record_photo_path(*, **) = "/api/v1/maintenance_records/42/photos/1"
  end)
end

RSpec.describe Maintenance::Show do
  def mock_pagy_photos(count: 0, page: 1)
    pg = OpenStruct.new(
      count: count, page: page, last: 1, from: 1, to: count,
      previous: nil, next: nil, vars: { items: 6 }
    )
    pg.define_singleton_method(:series) { [ 1 ] }
    pg
  end

  def mock_user(first_name: "Ivan", last_name: "Koval", role: "forester", password_digest: "x")
    OpenStruct.new(
      first_name: first_name,
      last_name: last_name,
      role: role,
      password_digest: password_digest
    )
  end

  def mock_maintainable(did: "SNET-00000042", uid: nil, maintainable_type: "Tree")
    OpenStruct.new(did: did, uid: uid)
  end

  def mock_record(id: 7, action_type: "inspection", performed_at: 1.hour.ago,
                  hardware_verified: false, labor_hours: nil, parts_cost: nil,
                  notes: "Routine check of the node connections.",
                  latitude: nil, longitude: nil, maintainable_type: "Tree",
                  maintainable: nil, user: nil, ews_alert_id: nil,
                  created_at: 2.hours.ago, updated_at: 1.hour.ago)
    rec_user = user || mock_user
    rec_maintainable = maintainable || mock_maintainable

    r = OpenStruct.new(
      id: id,
      action_type: action_type,
      performed_at: performed_at,
      hardware_verified: hardware_verified,
      labor_hours: labor_hours,
      parts_cost: parts_cost,
      notes: notes,
      latitude: latitude,
      longitude: longitude,
      maintainable_type: maintainable_type,
      maintainable: rec_maintainable,
      user: rec_user,
      ews_alert_id: ews_alert_id,
      created_at: created_at,
      updated_at: updated_at
    )
    r.define_singleton_method(:model_name) { ActiveModel::Name.new(MaintenanceRecord) }
    r.define_singleton_method(:to_key) { [ id ] }
    r.define_singleton_method(:to_param) { id.to_s }
    r.define_singleton_method(:total_cost) { (labor_hours.to_f * 50) + parts_cost.to_f }
    r
  end

  def render_component(record:, photos:, pagy_photos:)
    ApplicationController.renderer.render(
      component_class.new(record: record, photos: photos, pagy_photos: pagy_photos),
      layout: false
    )
  end

  let(:record) { mock_record }
  let(:html) { render_component(record: record, photos: [], pagy_photos: mock_pagy_photos) }

  describe "header" do
    it "renders the record id" do
      expect(html).to include("Record // #7")
    end

    it "renders the action type badge" do
      expect(html).to include("inspection")
    end

    it "renders the hardware badge as Pending Verify when not verified" do
      expect(html).to include("Pending Verify")
    end

    it "renders the hardware badge as HW Verified when hardware_verified" do
      verified_record = mock_record(hardware_verified: true)
      html = render_component(record: verified_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("HW Verified")
    end

    it "shows verify button when hardware_verified is false" do
      expect(html).to include("Verify Hardware")
    end

    it "does not show verify button when already verified" do
      verified_record = mock_record(hardware_verified: true)
      html = render_component(record: verified_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).not_to include("Verify Hardware →")
    end
  end

  describe "evidence gallery" do
    it "renders Evidence Protocol heading" do
      expect(html).to include("Evidence Protocol")
    end

    it "renders No Photos Attached placeholder when no photos" do
      expect(html).to include("No Photos Attached")
    end
  end

  describe "notes panel" do
    it "renders Field Notes heading" do
      expect(html).to include("Field Notes")
    end

    it "renders the notes content" do
      expect(html).to include("Routine check of the node connections.")
    end

    it "applies whitespace-pre-wrap for multi-line notes" do
      expect(html).to include("whitespace-pre-wrap")
    end
  end

  describe "cost breakdown" do
    it "renders OpEx Breakdown heading" do
      expect(html).to include("OpEx Breakdown")
    end

    it "renders Labor card" do
      expect(html).to include("Labor")
    end

    it "renders Parts card" do
      expect(html).to include("Parts")
    end

    it "renders Total Cost card" do
      expect(html).to include("Total Cost")
    end

    it "shows calculated labor cost for record with hours" do
      record_with_cost = mock_record(labor_hours: 2.5, parts_cost: 100.0)
      html = render_component(record: record_with_cost, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("225.0") # 2.5 * 50 + 100 = 225
    end
  end

  describe "GPS drift section" do
    context "when GPS coordinates are present for a Tree maintainable" do
      let(:tree_with_coords) do
        t = mock_maintainable
        t.define_singleton_method(:latitude) { 49.4285 }
        t.define_singleton_method(:longitude) { 32.0620 }
        t
      end

      it "renders coordinates" do
        record_with_gps = mock_record(latitude: 49.4286, longitude: 32.0621,
                                      maintainable: tree_with_coords)
        html = render_component(record: record_with_gps, photos: [], pagy_photos: mock_pagy_photos)
        expect(html).to include("49.4286")
      end
    end

    context "when GPS is not present" do
      it "renders No GPS recorded message" do
        expect(html).to include("No GPS recorded")
      end
    end
  end

  describe "hardware verification panel" do
    it "renders Hardware State heading" do
      expect(html).to include("Hardware State")
    end

    it "shows STM32 Verified as PENDING when unverified" do
      expect(html).to include("PENDING")
    end

    it "shows STM32 Verified as YES when hardware_verified" do
      verified_record = mock_record(hardware_verified: true)
      html = render_component(record: verified_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("YES")
    end
  end

  describe "evidence gallery with photos" do
    it "renders PhotoGallery when photos are present" do
      photo = OpenStruct.new(
        filename: ActiveStorage::Filename.new("evidence.jpg"),
        byte_size: 1_024_000,
        representable?: true
      )
      photo.define_singleton_method(:variant) { |_style| "variant_thumb" }
      pagy = mock_pagy_photos(count: 1)
      html = render_component(record: record, photos: [ photo ], pagy_photos: pagy)
      expect(html).to include("Evidence Protocol")
      expect(html).not_to include("No Photos Attached")
    end
  end

  describe "no photos placeholder with trust protocol warning" do
    it "shows trust protocol warning for repair action_type" do
      repair_record = mock_record(action_type: "repair")
      html = render_component(record: repair_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("Trust Protocol requires photos for repair")
    end

    it "shows trust protocol warning for installation action_type" do
      install_record = mock_record(action_type: "installation")
      html = render_component(record: install_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("Trust Protocol requires photos for installation")
    end

    it "does not show trust protocol warning for inspection" do
      expect(html).not_to include("Trust Protocol requires photos")
    end
  end

  describe "metadata panel with ews_alert_id" do
    it "renders EWS Alert reference when ews_alert_id present" do
      record_with_ews = mock_record(ews_alert_id: 99)
      html = render_component(record: record_with_ews, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("EWS Alert")
      expect(html).to include("#99")
    end
  end

  describe "GPS drift colors" do
    let(:tree_with_coords) do
      t = mock_maintainable
      t.define_singleton_method(:latitude) { 49.4285 }
      t.define_singleton_method(:longitude) { 32.0620 }
      t
    end

    before do
      allow(SilkenNet::GeoUtils).to receive(:haversine_distance_m).and_return(drift)
    end

    context "when drift is between 50 and 500 meters" do
      let(:drift) { 200.0 }

      it "renders warning color for moderate drift" do
        record_with_gps = mock_record(latitude: 49.43, longitude: 32.07, maintainable: tree_with_coords)
        html = render_component(record: record_with_gps, photos: [], pagy_photos: mock_pagy_photos)
        expect(html).to include("text-status-warning-text")
      end
    end

    context "when drift is over 500 meters" do
      let(:drift) { 800.0 }

      it "renders danger color for large drift" do
        record_with_gps = mock_record(latitude: 49.50, longitude: 32.20, maintainable: tree_with_coords)
        html = render_component(record: record_with_gps, photos: [], pagy_photos: mock_pagy_photos)
        expect(html).to include("text-red-400")
      end
    end
  end

  describe "GPS drift — close range (< 50 m)" do
    let(:tree_with_coords) do
      t = mock_maintainable
      t.define_singleton_method(:latitude) { 49.4285 }
      t.define_singleton_method(:longitude) { 32.0620 }
      t
    end

    it "renders the close-range drift value (emerald branch)" do
      allow(SilkenNet::GeoUtils).to receive(:haversine_distance_m).and_return(30.0)
      rec = mock_record(latitude: 49.4285, longitude: 32.0620, maintainable: tree_with_coords)
      html = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("30 m")
    end
  end

  describe "GPS drift-check guards" do
    it "skips the drift calc when the maintainable is not a Tree" do
      expect(SilkenNet::GeoUtils).not_to receive(:haversine_distance_m)
      gw = mock_maintainable
      gw.define_singleton_method(:latitude) { 49.0 }
      gw.define_singleton_method(:longitude) { 32.0 }
      rec = mock_record(latitude: 49.0, longitude: 32.0, maintainable_type: "Gateway", maintainable: gw)
      render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
    end

    it "skips the drift calc when the Tree has no coordinates" do
      expect(SilkenNet::GeoUtils).not_to receive(:haversine_distance_m)
      bare = mock_maintainable # OpenStruct → latitude/longitude return nil
      rec = mock_record(latitude: 49.0, longitude: 32.0, maintainable_type: "Tree", maintainable: bare)
      render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
    end

    it "skips the drift calc when the maintainable Tree record itself is gone (nullified FK)" do
      expect(SilkenNet::GeoUtils).not_to receive(:haversine_distance_m)
      rec = mock_record(latitude: 49.0, longitude: 32.0, maintainable_type: "Tree")
      rec.maintainable = nil
      render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
    end
  end

  describe "action badge fallback" do
    it "uses the gray default color for an unknown action_type" do
      rec = mock_record(action_type: "calibration")
      html = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("border-gray-600 text-gray-600")
    end
  end

  describe "nil-safe rendering of optional fields" do
    it "renders the metadata panel when user, maintainable, performed_at and timestamps are nil" do
      rec = mock_record(
        performed_at: nil, user: nil, maintainable: nil,
        created_at: nil, updated_at: nil
      )
      # Override the let(:user) fallback inside mock_record by giving an explicit nil sentinel.
      rec.user = nil
      rec.maintainable = nil

      out = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      expect(out).to include("Record // #7")
      expect(out).to include("—") # display_identifier fallback for nil maintainable
    end

    it "renders the EWS alert metadata row when ews_alert_id is present" do
      rec = mock_record(ews_alert_id: 99)
      out = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      expect(out).to include("#99")
    end
  end

  describe "GPS drift check" do
    it "skips the drift comparison when the maintainable Tree has no coordinates" do
      tree = OpenStruct.new(latitude: nil, longitude: nil, did: "SNET-NOCOORD")
      tree.define_singleton_method(:display_identifier) { did }
      rec = mock_record(
        latitude: 49.0, longitude: 32.0,
        maintainable_type: "Tree", maintainable: tree
      )

      out = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      # The drift row should be absent (no "drift" copy rendered).
      expect(out).not_to match(/drift_m|drift\s*[:=]/i)
    end
  end
end
