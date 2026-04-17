# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::CarbonAbsorption do

  def mock_org(name: "EcoDAO")
    OpenStruct.new(name: name)
  end

  def mock_data(total_carbon_points: 9_800, wallets_count: 45,
                trees_active: 280, trees_total: 320)
    {
      total_carbon_points: total_carbon_points,
      wallets_count: wallets_count,
      trees_active: trees_active,
      trees_total: trees_total
    }
  end

  let(:org)  { mock_org }
  let(:data) { mock_data }
  let(:html) { render_component(organization: org, data: data) }

  describe "header section" do
    it "renders Carbon Absorption Report label" do
      expect(html).to include("Carbon Absorption Report")
    end

    it "renders organization name" do
      expect(html).to include("EcoDAO")
    end

    it "renders generated timestamp" do
      expect(html).to include("Generated:")
    end
  end

  describe "stat cards" do
    it "renders Total Carbon Points stat card" do
      expect(html).to include("Total Carbon Points")
    end

    it "renders Active Wallets stat card" do
      expect(html).to include("Active Wallets")
    end

    it "renders Active Trees stat card" do
      expect(html).to include("Active Trees")
    end

    it "renders Total Trees stat card" do
      expect(html).to include("Total Trees")
    end
  end

  describe "metrics table" do
    it "renders total carbon points value" do
      expect(html).to include("9800")
    end

    it "renders wallets count" do
      expect(html).to include("45")
    end

    it "renders active trees count" do
      expect(html).to include("280")
    end

    it "renders total trees count" do
      expect(html).to include("320")
    end

    it "renders Trees Currently Online row label" do
      expect(html).to include("Trees Currently Online")
    end

    it "renders Trees Deployed row label" do
      expect(html).to include("Trees Deployed")
    end
  end

  describe "footer" do
    it "renders generated at footer" do
      expect(html).to include("Report generated at")
    end

    it "includes organization name in footer" do
      expect(html).to include("EcoDAO")
    end
  end
end
