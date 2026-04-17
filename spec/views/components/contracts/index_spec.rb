# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::Index do
  def mock_org(name: "Cherkasy Forest Fund")
    OpenStruct.new(name: name)
  end

  def mock_cluster(name: "Carpathian-Alpha")
    c = OpenStruct.new(name: name)
    c.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    c.define_singleton_method(:to_key) { [ 1 ] }
    c.define_singleton_method(:to_param) { "1" }
    c
  end

  def mock_contract(id: 42, status: "active", org_name: "Cherkasy Forest Fund",
                    cluster_name: "Carpathian-Alpha", total_value: 10_000,
                    emitted_tokens: 350, performance: 50,
                    start_date: 6.months.ago, end_date: 6.months.from_now)
    c = OpenStruct.new(
      id: id,
      status: status,
      organization: mock_org(name: org_name),
      cluster: mock_cluster(name: cluster_name),
      total_value: total_value,
      emitted_tokens: emitted_tokens,
      current_yield_performance: performance,
      start_date: start_date,
      end_date: end_date
    )
    c.define_singleton_method(:model_name) { ActiveModel::Name.new(NaasContract) }
    c.define_singleton_method(:to_key) { [ id ] }
    c.define_singleton_method(:to_param) { id.to_s }
    c
  end

  def mock_stats(total_invested: 50_000, total_minted: 1234.5, avg_health: 87)
    { total_invested: total_invested, total_minted: total_minted, avg_health: avg_health }
  end

  def render_component(contracts:, stats:, pagy:)
    ApplicationController.renderer.render(
      component_class.new(contracts: contracts, stats: stats, pagy: pagy),
      layout: false
    )
  end

  let(:contract) { mock_contract }
  let(:html) { render_component(contracts: [ contract ], stats: mock_stats, pagy: mock_pagy(last: 1)) }

  describe "header" do
    it "renders Active Asset Portfolio heading" do
      expect(html).to include("Active Asset Portfolio")
    end
  end

  describe "StatCards" do
    it "renders Portfolio Capital stat card" do
      expect(html).to include("Portfolio Capital")
    end

    it "renders Biogenic Yield stat card" do
      expect(html).to include("Biogenic Yield")
    end

    it "renders Network Health stat card" do
      expect(html).to include("Network Health")
    end

    it "displays the avg_health value with percent" do
      expect(html).to include("87%")
    end
  end

  describe "contract rows" do
    it "renders the contract id" do
      expect(html).to include("#42")
    end

    it "renders the organization name" do
      expect(html).to include("Cherkasy Forest Fund")
    end

    it "renders the cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "renders the investment total_value with SCC" do
      expect(html).to include("10000 SCC")
    end

    it "renders emitted_tokens with SCC" do
      expect(html).to include("350 SCC")
    end

    it "renders the performance gauge" do
      expect(html).to include("50%")
    end

    it "renders audit details link" do
      expect(html).to include("AUDIT_DETAILS")
    end
  end

  describe "status colors" do
    it "colors active contracts with emerald" do
      html = render_component(contracts: [ mock_contract(status: "active") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("text-emerald-500")
    end

    it "colors fulfilled contracts with blue" do
      html = render_component(contracts: [ mock_contract(status: "fulfilled") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("text-blue-400")
    end

    it "colors breached contracts with red" do
      html = render_component(contracts: [ mock_contract(status: "breached") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("text-red-500")
    end

    it "colors cancelled contracts with gray and line-through" do
      html = render_component(contracts: [ mock_contract(status: "cancelled") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("line-through")
    end
  end

  describe "empty state" do
    it "renders table even with no contracts" do
      html = render_component(contracts: [], stats: mock_stats, pagy: mock_pagy(count: 0, last: 1))
      expect(html).to include("Active Asset Portfolio")
    end
  end

  describe "status colors else branch" do
    it "colors unknown status with warning text" do
      html = render_component(contracts: [ mock_contract(status: "expired") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("text-status-warning-text")
    end
  end

  describe "pagination rendering" do
    it "renders pagination component" do
      pagy = mock_pagy(count: 50, page: 1, last: 3)
      html = render_component(contracts: [ mock_contract ], stats: mock_stats, pagy: pagy)
      expect(html).to be_present
    end
  end
end
