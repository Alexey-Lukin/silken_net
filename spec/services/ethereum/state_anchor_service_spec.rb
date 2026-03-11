# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ethereum::StateAnchorService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) { tree.wallet }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#generate_state_root" do
    it "returns a 64-character SHA256 hex string" do
      result = described_class.new.generate_state_root

      expect(result).to match(/\A[a-f0-9]{64}\z/)
    end

    it "incorporates total scc_balance from all wallets" do
      wallet.update!(scc_balance: 1000.0)

      root1 = described_class.new.generate_state_root

      wallet.update!(scc_balance: 2000.0)

      root2 = described_class.new.generate_state_root

      expect(root1).not_to eq(root2)
    end

    it "incorporates chain_hash from latest AuditLog" do
      user = create(:user, organization: organization)

      freeze_time do
        AuditLog.create!(
          user: user,
          organization: organization,
          action: "test_action_1",
          chain_hash: "abc123"
        )

        root1 = described_class.new.generate_state_root

        AuditLog.create!(
          user: user,
          organization: organization,
          action: "test_action_2",
          chain_hash: "def456"
        )

        root2 = described_class.new.generate_state_root

        expect(root1).not_to eq(root2)
      end
    end

    it "uses GENESIS fallback when no AuditLog exists" do
      # No audit logs — service falls back to GENESIS as chain_hash
      expected_payload = "0.0|GENESIS|#{Time.current.utc.iso8601}"
      expected_hash = Digest::SHA256.hexdigest(expected_payload)

      freeze_time do
        result = described_class.new.generate_state_root
        expect(result).to eq(expected_hash)
      end
    end

    it "incorporates timestamp so results differ over time" do
      root1 = travel_to(Time.utc(2026, 3, 1, 12, 0, 0)) { described_class.new.generate_state_root }
      root2 = travel_to(Time.utc(2026, 3, 1, 12, 0, 1)) { described_class.new.generate_state_root }

      expect(root1).not_to eq(root2)
    end
  end

  describe "#anchor_to_l1!" do
    let(:mock_client) { instance_double(Eth::Client) }
    let(:mock_key) { instance_double(Eth::Key) }
    let(:mock_contract) { instance_double(Eth::Contract) }

    before do
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Key).to receive(:new).and_return(mock_key)
      allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)

      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ALCHEMY_ETHEREUM_RPC_URL").and_return("https://eth-mainnet.g.alchemy.com/v2/test-key")
      allow(ENV).to receive(:fetch).with("ETHEREUM_ANCHOR_PRIVATE_KEY").and_return("0x" + "ab" * 32)
      allow(ENV).to receive(:fetch).with("ETHEREUM_ANCHOR_CONTRACT").and_return("0x" + "cd" * 20)
    end

    it "returns L1 transaction hash on success" do
      expected_tx_hash = "0x" + "fa" * 32
      allow(mock_client).to receive(:transact).and_return(expected_tx_hash)

      result = described_class.new.anchor_to_l1!

      expect(result).to eq(expected_tx_hash)
    end

    it "connects to Alchemy Ethereum RPC" do
      allow(mock_client).to receive(:transact).and_return("0x" + "aa" * 32)

      described_class.new.anchor_to_l1!

      expect(Eth::Client).to have_received(:create).with("https://eth-mainnet.g.alchemy.com/v2/test-key")
    end

    it "calls storeStateRoot with a 0x-prefixed bytes32 root" do
      allow(mock_client).to receive(:transact).and_return("0x" + "aa" * 32)

      described_class.new.anchor_to_l1!

      expect(mock_client).to have_received(:transact) do |contract, method, root, **_opts|
        expect(contract).to eq(mock_contract)
        expect(method).to eq("storeStateRoot")
        expect(root).to match(/\A0x[a-f0-9]{64}\z/)
      end
    end

    it "rescues Net::OpenTimeout and raises with descriptive message" do
      allow(mock_client).to receive(:transact).and_raise(Net::OpenTimeout, "execution expired")

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)
    end

    it "rescues Net::ReadTimeout and raises with descriptive message" do
      allow(mock_client).to receive(:transact).and_raise(Net::ReadTimeout, "Net::ReadTimeout")

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)
    end

    it "rescues IOError and raises with descriptive message" do
      allow(mock_client).to receive(:transact).and_raise(IOError, "Connection reset by peer")

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)
    end

    it "logs successful anchoring" do
      allow(mock_client).to receive(:transact).and_return("0x" + "bb" * 32)

      expect(Rails.logger).to receive(:info).with(/State Root anchored/)

      described_class.new.anchor_to_l1!
    end
  end
end
