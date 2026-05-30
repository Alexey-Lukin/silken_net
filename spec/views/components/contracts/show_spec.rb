# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::Show do
  def mock_org(name: "Cherkasy Forest Fund")
    OpenStruct.new(name: name)
  end

  def mock_cluster(name: "Carpathian-Alpha", health_index: 0.85,
                   total_active_trees: 42, active_threats: false)
    c = OpenStruct.new(
      name: name,
      health_index: health_index,
      total_active_trees: total_active_trees
    )
    c.define_singleton_method(:active_threats?) { active_threats }
    c.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    c.define_singleton_method(:to_key) { [ 1 ] }
    c.define_singleton_method(:to_param) { "1" }
    c
  end

  def mock_blockchain_tx(tx_hash: "0xdeadbeef1234567890abcdef", amount: "5.00", created_at: 2.hours.ago)
    OpenStruct.new(tx_hash: tx_hash, amount: amount, created_at: created_at)
  end

  def mock_contract(id: 99, status: "active", org: nil, cluster: nil,
                    total_funding: 50_000, emitted_tokens: 1234.56,
                    start_date: 6.months.ago, end_date: 6.months.from_now,
                    cancellation_terms: nil)
    c = OpenStruct.new(
      id: id,
      status: status,
      organization: org || mock_org,
      cluster: cluster,
      total_funding: total_funding,
      emitted_tokens: emitted_tokens,
      start_date: start_date,
      end_date: end_date,
      cancellation_terms: cancellation_terms
    )
    c.define_singleton_method(:model_name) { ActiveModel::Name.new(NaasContract) }
    c.define_singleton_method(:to_key) { [ id ] }
    c.define_singleton_method(:to_param) { id.to_s }
    c
  end

  def render_component(contract:, history:)
    ApplicationController.renderer.render(
      component_class.new(contract: contract, history: history),
      layout: false
    )
  end

  describe "contract header" do
    let(:contract) { mock_contract(id: 99, status: "active") }
    let(:html) { render_component(contract: contract, history: []) }

    it "renders the contract ID in the hero" do
      expect(html).to include("#99")
    end

    it "renders organization name" do
      expect(html).to include("Cherkasy Forest Fund")
    end

    it "renders Contract Identity label" do
      expect(html).to include("Contract Identity")
    end

    it "renders the status in uppercase" do
      expect(html).to include("ACTIVE")
    end

    it "renders Current Yield label" do
      expect(html).to include("Current Yield")
    end

    it "renders emitted_tokens value" do
      expect(html).to include("1234.56")
    end
  end

  describe "cluster backing asset panel" do
    context "when cluster is present" do
      let(:contract) { mock_contract(cluster: mock_cluster) }
      let(:html) { render_component(contract: contract, history: []) }

      it "renders Backing Asset Health section" do
        expect(html).to include("Backing Asset Health")
      end

      it "renders Cluster Vitality metric" do
        expect(html).to include("Cluster Vitality")
      end

      it "renders Active Soldiers count" do
        expect(html).to include("42")
      end
    end

    context "when cluster is nil" do
      let(:contract) { mock_contract(cluster: nil) }
      let(:html) { render_component(contract: contract, history: []) }

      it "does not render backing asset panel" do
        expect(html).not_to include("Backing Asset Health")
      end
    end
  end

  describe "emission ledger" do
    context "with blockchain history" do
      let(:tx) { mock_blockchain_tx(tx_hash: "0xdeadbeef1234567890abcdef", amount: "7.50") }
      let(:html) { render_component(contract: mock_contract, history: [ tx ]) }

      it "renders Blockchain Emission History heading" do
        expect(html).to include("Blockchain Emission History")
      end

      it "renders truncated tx hash" do
        expect(html).to include("0xdeadbeef12")
      end

      it "renders amount with SCC" do
        expect(html).to include("7.50 SCC")
      end
    end

    context "with no blockchain history" do
      let(:html) { render_component(contract: mock_contract, history: []) }

      it "shows no emissions recorded message" do
        expect(html).to include("No emissions recorded.")
      end
    end
  end

  describe "legal vault" do
    context "with cancellation_terms present" do
      let(:contract) do
        mock_contract(cancellation_terms: {
          "early_exit_fee_percent" => 15,
          "burn_accrued_points" => true,
          "min_days_before_exit" => 30
        })
      end

      let(:html) { render_component(contract: contract, history: []) }

      it "renders Cancellation Terms section" do
        expect(html).to include("Cancellation Terms")
      end

      it "renders the Smart Contract Data section" do
        expect(html).to include("Smart Contract Data")
      end
    end

    context "without cancellation terms" do
      let(:html) { render_component(contract: mock_contract(cancellation_terms: nil), history: []) }

      it "still renders the legal vault without cancellation section" do
        expect(html).to include("Smart Contract Data")
      end
    end

    context "with populated cancellation values [coverage]" do
      let(:contract) do
        c = mock_contract(cancellation_terms: { "present" => true })
        c.early_exit_fee_percent = 15
        c.burn_accrued_points = true
        c.min_days_before_exit = 30
        c
      end
      let(:html) { render_component(contract: contract, history: []) }

      it "renders the early exit fee, burn flag and minimum days" do
        expect(html).to include(">15%<")
        expect(html).to include(">Yes<")
        expect(html).to include(">30<")
      end
    end
  end

  describe "backing asset alert states [coverage]" do
    it "flags vitality in red when cluster health is below 70%" do
      contract = mock_contract(cluster: mock_cluster(health_index: 0.5))
      html = render_component(contract: contract, history: [])
      expect(html).to include(">50%<")
      expect(html).to include("text-red-500")
      expect(html).to include("animate-pulse")
    end

    it "renders a DANGER threat status when the cluster has active threats" do
      contract = mock_contract(cluster: mock_cluster(active_threats: true))
      html = render_component(contract: contract, history: [])
      expect(html).to include("DANGER")
    end

    it "treats a nil health_index as zero" do
      contract = mock_contract(cluster: mock_cluster(health_index: nil))
      html = render_component(contract: contract, history: [])
      expect(html).to include(">0%<")
    end
  end

  describe "emission ledger pending block [coverage]" do
    it "shows the pending-block placeholder when a tx has no hash yet" do
      tx = mock_blockchain_tx(tx_hash: nil)
      html = render_component(contract: mock_contract, history: [ tx ])
      expect(html).to include("PENDING_BLOCK")
    end
  end

  describe "hero with missing optional fields [coverage / defensive]" do
    it "renders the hero when organization and contract dates are nil" do
      contract = mock_contract(start_date: nil, end_date: nil)
      contract.organization = nil
      html = render_component(contract: contract, history: [])
      expect(html).to include("Contract Identity")
    end
  end
end
