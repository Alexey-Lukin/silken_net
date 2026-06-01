# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::EventRow do
  # Render under :en so hardcoded English text in event_summary is matched correctly.
  # The component strings are intentional display text (not i18n-keyed), so we
  # lock the locale to avoid order-dependent failures if the default changes.
  around { |ex| I18n.with_locale(:en) { ex.run } }

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
      tx.define_singleton_method(:sourceable) { nil }
      tx.define_singleton_method(:created_at) { 1.minute.ago }
      tx
    end
    let(:html) { render_component(event: event) }

    it "renders the mint summary with amount and DID" do
      expect(html).to include("Minted")
      expect(html).to include("0.005")
      expect(html).to include("TREE::0xDEAD")
    end

    it "uses the gaia text token for blockchain events" do
      expect(html).to include("text-gaia-text")
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

    it "uses the gaia subtle text token for unknown events" do
      expect(html).to include("text-gaia-text-subtle")
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

  describe "EwsAlert with no cluster" do
    let(:event) do
      alert = EwsAlert.allocate
      alert.define_singleton_method(:alert_type) { "Seismic" }
      alert.define_singleton_method(:cluster) { nil }
      alert.define_singleton_method(:created_at) { 1.minute.ago }
      alert
    end

    it "falls back to the Unknown cluster label" do
      expect(render_component(event: event)).to include("Unknown")
    end
  end

  describe "BlockchainTransaction routed through Etherisc" do
    def etherisc_tx(to_address:)
      pi = ParametricInsurance.allocate
      pi.define_singleton_method(:uses_etherisc?) { true }
      tx = BlockchainTransaction.allocate
      tx.define_singleton_method(:amount) { "12.50" }
      tx.define_singleton_method(:to_address) { to_address }
      tx.define_singleton_method(:sourceable) { pi }
      tx.define_singleton_method(:created_at) { 1.minute.ago }
      tx
    end

    it "renders an Etherisc DIP claim with a truncated address" do
      html = render_component(event: etherisc_tx(to_address: "0x1234567890abcdef1234"))
      expect(html).to include("Etherisc DIP claim")
      expect(html).to include("0x1234…1234")
    end

    it "labels the destination as Pool when the address is blank" do
      html = render_component(event: etherisc_tx(to_address: nil))
      expect(html).to include("Pool")
    end
  end

  describe "BlockchainTransaction mint with no wallet" do
    let(:event) do
      tx = BlockchainTransaction.allocate
      tx.define_singleton_method(:amount) { "0.001" }
      tx.define_singleton_method(:wallet) { nil }
      tx.define_singleton_method(:sourceable) { nil }
      tx.define_singleton_method(:created_at) { 1.minute.ago }
      tx
    end

    it "falls back to the System mint target" do
      html = render_component(event: event)
      expect(html).to include("Minted")
      expect(html).to include("→ System")
    end
  end

  describe "MaintenanceRecord with no user or action" do
    let(:event) do
      record = MaintenanceRecord.allocate
      record.define_singleton_method(:action_type) { nil }
      record.define_singleton_method(:user) { nil }
      record.define_singleton_method(:created_at) { 1.minute.ago }
      record
    end

    it "renders the maintenance summary with the System fallback user" do
      expect(render_component(event: event)).to include("by System")
    end
  end
end
