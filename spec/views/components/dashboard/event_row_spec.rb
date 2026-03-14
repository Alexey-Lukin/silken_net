# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::EventRow do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  # Use allocate to bypass ActiveRecord initialization but keep class identity
  # so case/when (Module#===) pattern matching works correctly.

  describe "with an EwsAlert event" do
    let(:event) do
      mock_cluster = OpenStruct.new(name: "Carpathian-7")
      alert = EwsAlert.allocate
      alert.define_singleton_method(:alert_type) { "Thermal Anomaly" }
      alert.define_singleton_method(:cluster) { mock_cluster }
      alert.define_singleton_method(:created_at) { 30.seconds.ago }
      alert
    end
    let(:html) { render_component(event: event) }

    it "renders the threat summary" do
      expect(html).to include("Threat:")
      expect(html).to include("Thermal Anomaly")
      expect(html).to include("Carpathian-7")
    end

    it "uses red color for alert events" do
      expect(html).to include("text-red-400")
    end
  end

  describe "with a BlockchainTransaction event" do
    let(:event) do
      mock_tree = OpenStruct.new(did: "TREE::0xDEAD")
      mock_wallet = OpenStruct.new(tree: mock_tree)
      tx = BlockchainTransaction.allocate
      tx.define_singleton_method(:amount) { "0.005" }
      tx.define_singleton_method(:wallet) { mock_wallet }
      tx.define_singleton_method(:created_at) { 1.minute.ago }
      tx
    end
    let(:html) { render_component(event: event) }

    it "renders the mint summary with amount and DID" do
      expect(html).to include("Minted")
      expect(html).to include("0.005")
      expect(html).to include("TREE::0xDEAD")
    end

    it "uses emerald color for blockchain events" do
      expect(html).to include("text-emerald-400")
    end
  end

  describe "with a MaintenanceRecord event" do
    let(:event) do
      mock_user = OpenStruct.new(first_name: "Taras")
      record = MaintenanceRecord.allocate
      record.define_singleton_method(:action_type) { "repair" }
      record.define_singleton_method(:user) { mock_user }
      record.define_singleton_method(:created_at) { 5.minutes.ago }
      record
    end
    let(:html) { render_component(event: event) }

    it "renders the maintenance summary" do
      expect(html).to include("Repair")
      expect(html).to include("Taras")
    end

    it "uses warning color for maintenance events" do
      expect(html).to include("text-status-warning-text")
    end
  end

  describe "with an unknown event type" do
    let(:event) { OpenStruct.new(created_at: 10.seconds.ago) }
    let(:html) { render_component(event: event) }

    it "renders fallback text" do
      expect(html).to include("System pulse detected")
    end

    it "uses gray color for unknown events" do
      expect(html).to include("text-gray-400")
    end
  end

  describe "best practices compliance" do
    let(:event) { OpenStruct.new(created_at: 1.minute.ago) }
    let(:html) { render_component(event: event) }

    it "uses semantic text-tiny instead of arbitrary sizes" do
      expect(html).to include("text-tiny")
      expect(html).not_to include("text-[")
    end

    it "uses gap instead of space-x for flex layout" do
      expect(html).to include("gap-4")
    end
  end
end
