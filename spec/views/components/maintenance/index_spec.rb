# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Maintenance::Index do
  def mock_pagy(count: 2, page: 1)
    pg = OpenStruct.new(
      count: count, page: page, last: 1, from: 1, to: count,
      previous: nil, next: nil, vars: { items: 50 }
    )
    pg.define_singleton_method(:series) { [ 1 ] }
    pg
  end

  def mock_user(first_name: "Ivan", last_name: "Koval")
    OpenStruct.new(first_name: first_name, last_name: last_name)
  end

  def mock_maintainable(display_identifier: "SNET-00000042")
    OpenStruct.new(display_identifier: display_identifier)
  end

  def mock_record(id: 1, action_type: "inspection", performed_at: 2.hours.ago,
                  hardware_verified: false, total_cost: 0,
                  photos_count: 0, maintainable_type: "Tree",
                  user: nil, maintainable: nil, notes: "Routine check")
    rec_user = user || mock_user
    rec_maintainable = maintainable || mock_maintainable

    # photos_attachments mock
    photos_mock = double("photos_attachments", size: photos_count)

    r = OpenStruct.new(
      id: id,
      action_type: action_type,
      performed_at: performed_at,
      hardware_verified: hardware_verified,
      total_cost: total_cost,
      maintainable_type: maintainable_type,
      user: rec_user,
      maintainable: rec_maintainable,
      notes: notes
    )
    r.define_singleton_method(:photos_attachments) { photos_mock }
    r.define_singleton_method(:model_name) { ActiveModel::Name.new(MaintenanceRecord) }
    r.define_singleton_method(:to_key) { [ id ] }
    r.define_singleton_method(:to_param) { id.to_s }
    r
  end

  def render_component(records:, pagy:)
    ApplicationController.renderer.render(
      component_class.new(records: records, pagy: pagy),
      layout: false
    )
  end

  let(:record) { mock_record }
  let(:html) { render_component(records: [ record ], pagy: mock_pagy) }

  describe "header" do
    it "renders the Maintenance Records heading" do
      expect(html).to include("Maintenance Records")
    end

    it "renders the record count from pagy" do
      expect(html).to include("2 interventions")
    end

    it "renders Register Intervention link" do
      expect(html).to include("Register Intervention")
    end
  end

  describe "action type filters" do
    it "renders filter links for each action type" do
      expect(html).to include("inspection")
      expect(html).to include("repair")
      expect(html).to include("installation")
    end

    it "renders a verified-only filter" do
      expect(html).to include("Verified Only")
    end

    it "renders a clear filter link" do
      expect(html).to include("Clear")
    end
  end

  describe "table rows" do
    it "renders technician name" do
      expect(html).to include("Ivan Koval")
    end

    it "renders action_type in the row" do
      expect(html).to include("inspection")
    end

    it "renders the maintainable type" do
      expect(html).to include("Tree")
    end

    it "renders the DID of the maintainable" do
      expect(html).to include("SNET-00000042")
    end

    it "renders a timestamp for performed_at" do
      # performed_at is 2.hours.ago, formatted as dd.mm.yy // HH:MM
      expect(html).to match(/\d{2}\.\d{2}\.\d{2} \/\/ \d{2}:\d{2}/)
    end
  end

  describe "hardware verified indicator" do
    it "renders the verified checkmark for hardware_verified records" do
      verified_record = mock_record(hardware_verified: true)
      html = render_component(records: [ verified_record ], pagy: mock_pagy)
      expect(html).to include("✓")
    end

    it "renders the pending indicator for unverified records" do
      html = render_component(records: [ mock_record(hardware_verified: false) ], pagy: mock_pagy)
      expect(html).to include("◌")
    end
  end

  describe "photo count" do
    it "renders photo count when photos are attached" do
      record_with_photos = mock_record(photos_count: 3)
      html = render_component(records: [ record_with_photos ], pagy: mock_pagy)
      expect(html).to include("📷 3")
    end

    it "renders em dash when no photos attached" do
      html = render_component(records: [ mock_record(photos_count: 0) ], pagy: mock_pagy)
      expect(html).to include("—")
    end
  end

  describe "cost display" do
    it "renders cost in dollars when total_cost is positive" do
      record_with_cost = mock_record(total_cost: 275.50)
      html = render_component(records: [ record_with_cost ], pagy: mock_pagy)
      expect(html).to include("$275.5")
    end
  end

  describe "empty state" do
    it "renders no interventions message when records are empty" do
      html = render_component(records: [], pagy: mock_pagy(count: 0))
      expect(html).to include("No interventions recorded")
    end
  end

  describe "action badge fallback" do
    it "uses the gray fallback color for an unknown action_type" do
      html = render_component(records: [ mock_record(action_type: "calibration") ], pagy: mock_pagy)
      expect(html).to include("text-gray-500")
    end
  end

  describe "row with missing user, maintainable and timestamp" do
    it "renders gracefully when those fields are nil" do
      rec = mock_record(performed_at: nil)
      rec.user = nil
      rec.maintainable = nil
      html = render_component(records: [ rec ], pagy: mock_pagy)
      expect(html).to include("Tree //") # maintainable_type still renders
      expect(html).to include("—")        # maintainable&.display_identifier || "—"
    end
  end
end
