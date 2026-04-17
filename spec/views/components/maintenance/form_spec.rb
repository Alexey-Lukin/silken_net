# frozen_string_literal: true

require "rails_helper"

RSpec.describe Maintenance::Form do
  def render_component(record:, existing_photos: [])
    ApplicationController.renderer.render(
      described_class.new(record: record, existing_photos: existing_photos),
      layout: false
    )
  end

  describe "new record form" do
    let(:record) { build(:maintenance_record) }
    let(:html) { render_component(record: record) }

    it "renders the form action URL for new record" do
      expect(html).to include("/api/v1/maintenance_records")
    end

    it "renders the form heading for new record" do
      expect(html).to include("Register Intervention Ritual")
    end

    it "renders the target type select field" do
      expect(html).to include('name="maintenance_record[maintainable_type]"')
    end

    it "renders Tree and Gateway as select options" do
      expect(html).to include("Tree")
      expect(html).to include("Gateway")
    end

    it "renders the action_type select field" do
      expect(html).to include('name="maintenance_record[action_type]"')
    end

    it "renders the performed_at datetime field" do
      expect(html).to include('name="maintenance_record[performed_at]"')
    end

    it "renders the notes textarea" do
      expect(html).to include('name="maintenance_record[notes]"')
    end

    it "renders the labor_hours field in OpEx section" do
      expect(html).to include('name="maintenance_record[labor_hours]"')
    end

    it "renders the parts_cost field in OpEx section" do
      expect(html).to include('name="maintenance_record[parts_cost]"')
    end

    it "renders OpEx Financial Tracking label" do
      expect(html).to include("OpEx Financial Tracking")
    end

    it "renders the GPS coordinates section" do
      expect(html).to include("Intervention Coordinates")
    end

    it "renders latitude and longitude fields" do
      expect(html).to include('name="maintenance_record[latitude]"')
      expect(html).to include('name="maintenance_record[longitude]"')
    end

    it "renders the photo upload section" do
      expect(html).to include("Evidence Protocol")
    end

    it "renders the file upload field" do
      expect(html).to include('name="maintenance_record[photos][]"')
    end

    it "renders Commit to Matrix as submit text for new record" do
      expect(html).to include("Commit to Matrix")
    end

    it "does not render hardware verified checkbox for new record" do
      expect(html).not_to include("Hardware Verified")
    end
  end

  describe "edit record form" do
    let(:record) { create(:maintenance_record) }
    let(:html) { render_component(record: record) }

    it "renders the edit heading with record ID" do
      expect(html).to include("Edit Intervention Record")
      expect(html).to include("##{record.id}")
    end

    it "renders Update Record as submit text" do
      expect(html).to include("Update Record")
    end

    it "renders hardware verified checkbox in edit mode" do
      expect(html).to include("Hardware Verified")
    end

    it "renders a cancel link back to the show page" do
      expect(html).to include("Cancel")
    end
  end

  describe "error display" do
    let(:record) do
      rec = build(:maintenance_record, notes: "")
      rec.validate
      rec
    end

    it "renders validation errors section when record has errors" do
      expect(html_with_errors(record)).to include("Validation Errors")
    end

    def html_with_errors(rec)
      rec.errors.add(:notes, "can't be blank") if rec.errors[:notes].empty?
      render_component(record: rec)
    end
  end
end
