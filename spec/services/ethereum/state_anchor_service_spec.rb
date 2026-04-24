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
    it "returns a Hash with state_root as a 64-character SHA256 hex string" do
      result = described_class.new.generate_state_root

      expect(result).to be_a(Hash)
      expect(result[:state_root]).to match(/\A[a-f0-9]{64}\z/)
    end

    it "includes all components for reproducibility (BLOCKER-6)" do
      result = described_class.new.generate_state_root

      expect(result).to include(:state_root, :total_scc, :chain_hash, :anchored_at)
      expect(result[:anchored_at]).to be_a(Time)
    end

    it "incorporates total scc_balance from all wallets" do
      wallet.update!(scc_balance: 1000.0)

      root1 = described_class.new.generate_state_root[:state_root]

      wallet.update!(scc_balance: 2000.0)

      root2 = described_class.new.generate_state_root[:state_root]

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

        root1 = described_class.new.generate_state_root[:state_root]

        AuditLog.create!(
          user: user,
          organization: organization,
          action: "test_action_2",
          chain_hash: "def456"
        )

        root2 = described_class.new.generate_state_root[:state_root]

        expect(root1).not_to eq(root2)
      end
    end

    it "uses GENESIS fallback when no AuditLog exists" do
      expected_payload = "0.0|GENESIS|#{Time.current.utc.iso8601}"
      expected_hash = Digest::SHA256.hexdigest(expected_payload)

      freeze_time do
        result = described_class.new.generate_state_root
        expect(result[:state_root]).to eq(expected_hash)
        expect(result[:chain_hash]).to eq("GENESIS")
      end
    end

    it "incorporates timestamp so results differ over time" do
      root1 = travel_to(Time.utc(2026, 3, 1, 12, 0, 0)) { described_class.new.generate_state_root[:state_root] }
      root2 = travel_to(Time.utc(2026, 3, 1, 12, 0, 1)) { described_class.new.generate_state_root[:state_root] }

      expect(root1).not_to eq(root2)
    end

    it "executes within a REPEATABLE READ transaction for snapshot isolation" do
      # Verify that generate_state_root wraps SQL queries in a transaction
      # with isolation level :repeatable_read to prevent inconsistent snapshots
      # when parallel workers (MintCarbonCoinWorker, AuditLogWorker) write between queries.
      expect(ActiveRecord::Base).to receive(:transaction).with(isolation: :repeatable_read).and_call_original

      described_class.new.generate_state_root
    end
  end

  describe "#anchor_to_l1!" do
    let(:mock_client) { instance_double(Eth::Client) }
    let(:mock_key) { instance_double(Eth::Key, address: "0x" + "ab" * 20) }
    let(:mock_contract) { instance_double(Eth::Contract) }

    before do
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Key).to receive(:new).and_return(mock_key)
      allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)

      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ALCHEMY_ETHEREUM_RPC_URL").and_return("https://eth-mainnet.g.alchemy.com/v2/test-key")
      allow(ENV).to receive(:fetch).with("ETHEREUM_ANCHOR_PRIVATE_KEY").and_return("0x" + "ab" * 32)
      allow(ENV).to receive(:fetch).with("ETHEREUM_ANCHOR_CONTRACT").and_return("0x" + "cd" * 20)
      allow(ENV).to receive(:fetch).with("ETHEREUM_MAX_FEE_GWEI", anything).and_return(100)
      allow(ENV).to receive(:fetch).with("ETHEREUM_PRIORITY_FEE_GWEI", anything).and_return(2)
      allow(ENV).to receive(:fetch).with("ETHEREUM_GAS_LIMIT", anything).and_return(100_000)

      # [BLOCKER-4] Mock balance check — sufficient balance by default
      allow(mock_client).to receive(:get_balance).and_return(1 * (10**18))
    end

    it "returns an EthereumAnchor record on success (BLOCKER-2)" do
      expected_tx_hash = "0x" + "fa" * 32
      allow(mock_client).to receive(:transact).and_return(expected_tx_hash)

      result = described_class.new.anchor_to_l1!

      expect(result).to be_a(EthereumAnchor)
      expect(result).to be_persisted
      expect(result.tx_hash).to eq(expected_tx_hash)
      expect(result).to be_status_sent
    end

    it "persists state_root components for reproducibility (BLOCKER-6)" do
      allow(mock_client).to receive(:transact).and_return("0x" + "fa" * 32)

      result = described_class.new.anchor_to_l1!

      expect(result.state_root).to match(/\A[a-f0-9]{64}\z/)
      expect(result.total_scc).to be_present
      expect(result.chain_hash).to be_present
      expect(result.anchored_at).to be_present
      expect(result.verify_state_root).to be true
    end

    it "passes gas parameters to transact (BLOCKER-3)" do
      allow(mock_client).to receive(:transact).and_return("0x" + "aa" * 32)

      described_class.new.anchor_to_l1!

      expect(mock_client).to have_received(:transact) do |_contract, _method, _root, **opts|
        expect(opts[:gas_limit]).to eq(100_000)
        expect(opts[:max_fee_per_gas]).to eq(100 * (10**9))
        expect(opts[:max_priority_fee_per_gas]).to eq(2 * (10**9))
        expect(opts[:legacy]).to be false
      end
    end

    it "raises when ETH balance is insufficient (BLOCKER-4)" do
      allow(mock_client).to receive(:get_balance).and_return(0)

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Insufficient anchor wallet balance/)

      anchor = EthereumAnchor.last
      expect(anchor).to be_status_failed
      expect(anchor.error_message).to include("Insufficient ETH balance")
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

    it "rescues Net::OpenTimeout and keeps anchor as pending (S6.7 double-anchor guard)" do
      allow(mock_client).to receive(:transact).and_raise(Net::OpenTimeout, "execution expired")

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)

      anchor = EthereumAnchor.last
      expect(anchor).to be_status_pending
      expect(anchor.error_message).to include("Timeout")
    end

    it "rescues Net::ReadTimeout and keeps anchor as pending (S6.7 double-anchor guard)" do
      allow(mock_client).to receive(:transact).and_raise(Net::ReadTimeout, "Net::ReadTimeout")

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)

      anchor = EthereumAnchor.last
      expect(anchor).to be_status_pending
    end

    it "rescues IOError and keeps anchor as pending (S6.7 double-anchor guard)" do
      allow(mock_client).to receive(:transact).and_raise(IOError, "Connection reset by peer")

      expect(Rails.logger).to receive(:warn).with(/Connection error.*kept as :pending/)

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Connection Error/)

      expect(EthereumAnchor.last).to be_status_pending
    end

    it "logs successful anchoring" do
      allow(mock_client).to receive(:transact).and_return("0x" + "bb" * 32)

      expect(Rails.logger).to receive(:info).with(/State Root anchored/)

      described_class.new.anchor_to_l1!
    end

    context "with double-anchoring guard" do
      it "skips when a sent anchor exists within the last week" do
        sent_anchor = EthereumAnchor.create!(
          state_root: "c" * 64,
          total_scc: 500.0,
          chain_hash: "existing_hash",
          anchored_at: 1.hour.ago,
          status: :sent,
          tx_hash: "0x#{"dd" * 32}"
        )

        expect(Rails.logger).to receive(:info).with(/In-flight anchor detected/)

        result = described_class.new.anchor_to_l1!

        expect(result).to eq(sent_anchor)
        expect(EthereumAnchor.count).to eq(1)
      end

      it "resumes a pending anchor instead of creating a new one" do
        pending_anchor = EthereumAnchor.create!(
          state_root: "d" * 64,
          total_scc: 600.0,
          chain_hash: "pending_hash",
          anchored_at: 30.minutes.ago,
          status: :pending
        )

        expected_tx_hash = "0x#{"ee" * 32}"
        allow(mock_client).to receive(:transact).and_return(expected_tx_hash)

        result = described_class.new.anchor_to_l1!

        expect(result.id).to eq(pending_anchor.id)
        expect(result).to be_status_sent
        expect(result.tx_hash).to eq(expected_tx_hash)
        expect(EthereumAnchor.count).to eq(1)
      end

      it "ignores anchors older than one week" do
        travel_to(8.days.ago) do
          EthereumAnchor.create!(
            state_root: "e" * 64,
            total_scc: 700.0,
            chain_hash: "old_hash",
            anchored_at: Time.current,
            status: :sent,
            tx_hash: "0x#{"ff" * 32}"
          )
        end

        allow(mock_client).to receive(:transact).and_return("0x#{"ab" * 32}")

        result = described_class.new.anchor_to_l1!

        expect(result.state_root).not_to eq("e" * 64)
        expect(EthereumAnchor.count).to eq(2)
      end

      it "ignores failed anchors and creates a new one" do
        EthereumAnchor.create!(
          state_root: "f" * 64,
          total_scc: 800.0,
          chain_hash: "failed_hash",
          anchored_at: 1.hour.ago,
          status: :failed,
          error_message: "timeout"
        )

        allow(mock_client).to receive(:transact).and_return("0x#{"ab" * 32}")

        result = described_class.new.anchor_to_l1!

        expect(result.state_root).not_to eq("f" * 64)
        expect(result).to be_status_sent
        expect(EthereumAnchor.count).to eq(2)
      end
    end
  end
end
