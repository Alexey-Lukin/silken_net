# frozen_string_literal: true

require "rails_helper"

RSpec.describe MaintenanceRecordBlueprint, type: :model do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  let(:user) { create(:user, first_name: "Andriy", last_name: "Melnyk") }
  let(:tree) { create(:tree) }
  let(:maintenance_record) do
    create(:maintenance_record, :with_cost, user: user, maintainable: tree,
                                            notes: "Replaced sensor module",
                                            latitude: 49.4285, longitude: 32.0620,
                                            hardware_verified: true)
  end

  describe ":index view" do
    subject(:parsed) { JSON.parse(described_class.render(maintenance_record, view: :index)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(maintenance_record.id)
    end

    it "includes action_type and timing" do
      expect(parsed["action_type"]).to eq("inspection")
      expect(parsed).to have_key("performed_at")
    end

    it "includes notes" do
      expect(parsed["notes"]).to eq("Replaced sensor module")
    end

    it "includes cost fields" do
      expect(parsed["labor_hours"]).to be_a(Numeric)
      expect(parsed["parts_cost"]).to be_a(Numeric)
    end

    it "includes hardware_verified flag" do
      expect(parsed["hardware_verified"]).to be true
    end

    it "includes location" do
      expect(parsed["latitude"]).to be_a(Numeric)
      expect(parsed["longitude"]).to be_a(Numeric)
    end

    it "includes computed total_cost" do
      expected_cost = (maintenance_record.labor_hours.to_f * MaintenanceRecord::LABOR_RATE_PER_HOUR) +
                      maintenance_record.parts_cost.to_f
      expect(parsed["total_cost"]).to eq(expected_cost.round(2))
    end

    it "includes computed photo_count" do
      expect(parsed["photo_count"]).to eq(0)
    end

    it "includes computed maintainable_label with Tree did" do
      expect(parsed["maintainable_label"]).to eq("Tree // #{tree.did}")
    end

    it "includes user association in :minimal view" do
      user_data = parsed["user"]
      expect(user_data).to be_a(Hash)
      expect(user_data["first_name"]).to eq("Andriy")
      expect(user_data["last_name"]).to eq("Melnyk")
      expect(user_data["full_name"]).to eq("Andriy Melnyk")
    end

    it "user does not include fields beyond :minimal" do
      user_data = parsed["user"]
      expect(user_data).not_to have_key("email_address")
      expect(user_data).not_to have_key("role")
    end
  end

  describe ":show view" do
    subject(:parsed) { JSON.parse(described_class.render(maintenance_record, view: :show)) }

    it "inherits all :index fields" do
      expect(parsed["action_type"]).to eq("inspection")
      expect(parsed["notes"]).to eq("Replaced sensor module")
      expect(parsed).to have_key("total_cost")
      expect(parsed).to have_key("photo_count")
      expect(parsed).to have_key("maintainable_label")
      expect(parsed).to have_key("user")
    end

    it "includes photo_urls as an empty array when no photos attached" do
      expect(parsed["photo_urls"]).to eq([])
    end
  end

  describe "maintainable_label with Gateway" do
    let(:gateway) { create(:gateway, cluster: create(:cluster)) }
    let(:gateway_record) do
      create(:maintenance_record, user: user, maintainable: gateway)
    end

    it "renders Gateway uid in label" do
      parsed = JSON.parse(described_class.render(gateway_record, view: :index))
      expect(parsed["maintainable_label"]).to eq("Gateway // #{gateway.uid}")
    end
  end

  describe "total_cost without cost trait" do
    let(:no_cost_record) do
      create(:maintenance_record, user: user, maintainable: tree)
    end

    it "returns 0.0 when labor_hours and parts_cost are nil" do
      parsed = JSON.parse(described_class.render(no_cost_record, view: :index))
      expect(parsed["total_cost"]).to eq(0.0)
    end
  end

  describe "collection rendering" do
    let!(:records) do
      create_list(:maintenance_record, 3, user: user, maintainable: tree)
    end

    it "renders an array of maintenance records" do
      parsed = JSON.parse(described_class.render(records, view: :index))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
      parsed.each do |r|
        expect(r).to have_key("total_cost")
        expect(r).to have_key("maintainable_label")
      end
    end
  end
end
