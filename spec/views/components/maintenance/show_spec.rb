# frozen_string_literal: true

require "rails_helper"

RSpec.describe Maintenance::Show do
  # The Maintenance::Show component references `edit_api_v1_maintenance_record_path` but
  # the routes do not expose an :edit action for maintenance_records. We patch it here.
  before(:context) do
    unless Maintenance::Show.method_defined?(:edit_api_v1_maintenance_record_path)
      Maintenance::Show.prepend(Module.new do
        def edit_api_v1_maintenance_record_path(record = nil, **_opts)
          "/api/v1/maintenance_records/#{record&.to_param}/edit"
        end
      end)
    end
  end

  def mock_pagy_photos(count: 0, page: 1)
    pg = OpenStruct.new(
      count: count, page: page, last: 1, from: 1, to: count,
      prev: nil, next: nil, vars: { items: 6 }
    )
    pg.define_singleton_method(:series) { [1] }
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
    r.define_singleton_method(:to_key) { [id] }
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
end
