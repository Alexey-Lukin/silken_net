# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::Index do
  def mock_org(id: 1, name: "ForestDAO")
    OpenStruct.new(id: id, name: name)
  end

  def mock_summary(total_trees: 300, health_score: 0.88, total_carbon_points: 12_500,
                   total_contracted: 50_000, total_clusters: 7, under_threat: false)
    {
      total_trees: total_trees,
      health_score: health_score,
      total_carbon_points: total_carbon_points,
      total_contracted: total_contracted,
      total_clusters: total_clusters,
      under_threat: under_threat
    }
  end

  let(:org)     { mock_org }
  let(:summary) { mock_summary }
  let(:html)    { render_component(organization: org, summary: summary) }

  describe "header section" do
    it "renders the Archive Reports Hub heading" do
      expect(html).to include("The Archive")
    end

    it "renders organization name" do
      expect(html).to include("ForestDAO")
    end
  end

  describe "performance stats" do
    it "renders Monitored Trees stat card" do
      expect(html).to include("Monitored Trees")
    end

    it "renders Health Score stat card" do
      expect(html).to include("Health Score")
    end

    it "renders SCC Minted stat card" do
      expect(html).to include("SCC Minted")
    end

    it "renders Contracted Amount stat card" do
      expect(html).to include("Contracted Amount")
    end

    it "renders Sectors stat card" do
      expect(html).to include("Sectors")
    end

    it "renders Threat Level as CLEAR when no threat" do
      expect(html).to include("CLEAR")
    end

    it "renders Threat Level as ACTIVE when under_threat is true" do
      html = render_component(organization: org, summary: mock_summary(under_threat: true))
      expect(html).to include("ACTIVE")
    end
  end

  describe "report cards" do
    it "renders Carbon Absorption Report card" do
      expect(html).to include("Carbon Absorption Report")
    end

    it "renders Financial Summary Report card" do
      expect(html).to include("Financial Summary Report")
    end

    it "renders Available Reports heading" do
      expect(html).to include("Available Reports")
    end

    it "renders View link for carbon absorption" do
      expect(html).to include("carbon_absorption")
    end

    it "renders CSV export link" do
      expect(html).to include(".csv")
    end

    it "renders PDF export link" do
      expect(html).to include(".pdf")
    end
  end
end
