# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainMintingService do
  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_PRIVATE_KEY"] ||= "0x" + "a" * 64
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x" + "0" * 40
    ENV["FOREST_COIN_CONTRACT_ADDRESS"] ||= "0x" + "1" * 40

    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(BlockchainConfirmationWorker).to receive(:perform_in)
unless defined?(Kredis)
      kredis_mod = Module.new do
        def self.lock(*, **, &block)
          block&.call
        end
      end
      stub_const("Kredis", kredis_mod)
end

    allow(Eth::Client).to receive(:create).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
    allow(mock_client).to receive_messages(get_balance: 1 * 10**18, transact: fake_tx_hash)
    allow(Kredis).to receive(:lock).and_yield
  end

  let(:fake_tx_hash) { "0x" + "f" * 64 }
  let(:mock_client) { instance_double(Eth::Client) }
  let(:mock_key) { instance_double(Eth::Key, address: "0x" + "d" * 40) }
  let(:mock_contract) { double("contract") }
  let(:mock_lock) { double("kredis_lock") }


  describe ".call" do
    context "when no pending transactions exist" do
      it "returns early when no pending transactions" do
        expect(mock_client).not_to receive(:transact)

        described_class.call(-1)
      end
    end

    context "with a single carbon_coin transaction" do
      it "processes single carbon_coin transaction" do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

        tx = wallet.blockchain_transactions.create!(
          amount: 100,
          token_type: :carbon_coin,
          status: :pending,
          to_address: wallet.crypto_public_address,
          locked_points: 1000
        )

        described_class.call(tx.id)

        tx.reload
        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to eq(fake_tx_hash)
      end
    end

    context "with already confirmed transactions" do
      it "returns early when no pending transactions" do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

        tx = wallet.blockchain_transactions.create!(
          amount: 50,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: wallet.crypto_public_address,
          tx_hash: "0x" + "c" * 64,
          locked_points: 500
        )

        expect(mock_client).not_to receive(:transact)

        described_class.call(tx.id)
      end
    end
  end

  describe ".call_batch" do
    context "with multiple transactions" do
      it "processes batch transactions" do
        tree1 = create(:tree)
        wallet1 = tree1.wallet
        wallet1.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

        tree2 = create(:tree)
        wallet2 = tree2.wallet
        wallet2.update!(crypto_public_address: "0x" + "c" * 40, hadron_kyc_status: "approved")

        tx1 = wallet1.blockchain_transactions.create!(
          amount: 100,
          token_type: :carbon_coin,
          status: :pending,
          to_address: wallet1.crypto_public_address,
          locked_points: 1000
        )

        tx2 = wallet2.blockchain_transactions.create!(
          amount: 200,
          token_type: :carbon_coin,
          status: :pending,
          to_address: wallet2.crypto_public_address,
          locked_points: 2000
        )

        described_class.call_batch([ tx1.id, tx2.id ])

        tx1.reload
        tx2.reload
        expect(tx1.status).to eq("sent")
        expect(tx1.tx_hash).to eq(fake_tx_hash)
        expect(tx2.status).to eq("sent")
        # Batch mint: one blockchain call = shared tx_hash
        expect(tx2.tx_hash).to eq(fake_tx_hash)
      end
    end
  end

  describe "oracle balance check" do
    it "raises when oracle balance is critically low" do
      allow(mock_client).to receive(:get_balance).and_return(0)

      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 100,
        token_type: :carbon_coin,
        status: :pending,
        to_address: wallet.crypto_public_address,
        locked_points: 1000
      )

      expect { described_class.call(tx.id) }.to raise_error(RuntimeError, /Критично низький баланс/)
    end
  end

  describe "blockchain error handling" do
    it "marks transactions as failed on blockchain error" do
      allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC connection failed")

      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 100,
        token_type: :carbon_coin,
        status: :pending,
        to_address: wallet.crypto_public_address,
        locked_points: 1000
      )

      expect { described_class.call(tx.id) }.to raise_error(StandardError, "RPC connection failed")

      tx.reload
      expect(tx.status).to eq("failed")
    end
  end

  describe "#to_wei" do
    it "converts amounts to wei using BigDecimal precision" do
      service = described_class.new([ -1 ])

      # Use send to test the private method
      result = service.send(:to_wei, 1)
      expect(result).to eq(10**18)

      result = service.send(:to_wei, "0.5")
      expect(result).to eq(5 * 10**17)

      result = service.send(:to_wei, 1_000_000)
      expect(result).to eq(1_000_000 * 10**18)

      # Verify BigDecimal precision — no floating point drift
      result = service.send(:to_wei, "0.000000000000000001")
      expect(result).to eq(1)
    end
  end

  describe "worker scheduling" do
    it "schedules BlockchainConfirmationWorker after successful mint" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 100,
        token_type: :carbon_coin,
        status: :pending,
        to_address: wallet.crypto_public_address,
        locked_points: 1000
      )

      described_class.call(tx.id)

      expect(BlockchainConfirmationWorker).to have_received(:perform_in).with(30.seconds, fake_tx_hash)
    end
  end

  describe "#identifier_for" do
    let(:service) { described_class.new([ -1 ]) }

    it "returns CLUSTER identifier for forest_coin" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 100,
        token_type: :forest_coin,
        status: :pending,
        to_address: wallet.crypto_public_address,
        locked_points: 1000
      )

      result = service.send(:identifier_for, tx)
      expect(result).to eq("CLUSTER_#{tree.cluster_id}")
    end

    it "returns CLUSTER_GLOBAL when tree is nil for forest_coin" do
      org = create(:organization, crypto_public_address: "0x" + "b" * 40)
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 100,
        token_type: :forest_coin,
        status: :pending,
        to_address: wallet.crypto_public_address,
        locked_points: 1000
      )

      # Simulate nil tree by stubbing
      allow(wallet).to receive(:tree).and_return(nil)
      allow(tx).to receive(:wallet).and_return(wallet)

      result = service.send(:identifier_for, tx)
      expect(result).to eq("CLUSTER_GLOBAL")
    end

    it "falls back to ORG identifier when tree is nil for carbon_coin" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 100,
        token_type: :carbon_coin,
        status: :pending,
        to_address: wallet.crypto_public_address,
        locked_points: 1000
      )

      allow(wallet).to receive(:tree).and_return(nil)
      allow(tx).to receive(:wallet).and_return(wallet)

      result = service.send(:identifier_for, tx)
      expect(result).to eq("ORG_#{wallet.organization_id}")
    end
  end

  describe "trustless verification (guard clauses)" do
    let(:tree) { create(:tree) }
    let(:wallet) { tree.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved") } }
    let!(:tx) do
      wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )
    end

    it "raises when telemetry_log is not verified by IoTeX" do
      log = create(:telemetry_log, tree: tree, verified_by_iotex: false, oracle_status: "fulfilled")

      expect {
        described_class.call(tx.id, telemetry_log: log)
      }.to raise_error(RuntimeError, /Data not verified by IoTeX/)
    end

    it "raises when Chainlink Oracle consensus is not fulfilled" do
      log = create(:telemetry_log, tree: tree, verified_by_iotex: true, oracle_status: "dispatched")

      expect {
        described_class.call(tx.id, telemetry_log: log)
      }.to raise_error(RuntimeError, /Chainlink Oracle consensus not fulfilled/)
    end

    it "proceeds when telemetry_log is fully verified" do
      log = create(:telemetry_log,
        tree: tree,
        verified_by_iotex: true,
        oracle_status: "fulfilled",
        chainlink_request_id: "chainlink-req-123",
        zk_proof_ref: "zk-proof-456"
      )

      described_class.call(tx.id, telemetry_log: log)

      tx.reload
      expect(tx.status).to eq("sent")
      expect(tx.tx_hash).to eq(fake_tx_hash)
    end

    it "saves chainlink_request_id and zk_proof_ref to blockchain_transaction" do
      log = create(:telemetry_log,
        tree: tree,
        verified_by_iotex: true,
        oracle_status: "fulfilled",
        chainlink_request_id: "chainlink-req-audit-999",
        zk_proof_ref: "zk-proof-audit-777"
      )

      described_class.call(tx.id, telemetry_log: log)

      tx.reload
      expect(tx.chainlink_request_id).to eq("chainlink-req-audit-999")
      expect(tx.zk_proof_ref).to eq("zk-proof-audit-777")
    end

    it "does not save chainlink fields when telemetry_log is nil" do
      described_class.call(tx.id)

      tx.reload
      expect(tx.chainlink_request_id).to be_nil
      expect(tx.zk_proof_ref).to be_nil
    end
  end

  describe "Hadron RWA compliance (guard clause)" do
    it "raises when wallet is not Hadron KYC approved" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "pending")

      tx = wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )

      expect {
        described_class.call(tx.id)
      }.to raise_error(RuntimeError, /Compliance Breach: Wallet is not Hadron KYC approved/)
    end

    it "raises when wallet KYC status is rejected" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "rejected")

      tx = wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )

      expect {
        described_class.call(tx.id)
      }.to raise_error(RuntimeError, /Compliance Breach: Wallet is not Hadron KYC approved/)
    end

    it "proceeds when wallet KYC is approved" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )

      described_class.call(tx.id)

      tx.reload
      expect(tx.status).to eq("sent")
    end
  end

  describe "unknown token_type" do
    it "raises ArgumentError for unknown token_type" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )

      # Override token_type after creation
      tx.update_column(:token_type, "unknown_token")

      expect {
        described_class.call(tx.id)
      }.to raise_error(ArgumentError, /Невідомий тип токена/)
    end
  end

  describe "forest_coin transaction" do
    it "processes a forest_coin transaction using the correct contract" do
      ENV["FOREST_COIN_CONTRACT_ADDRESS"] = "0x" + "1" * 40

      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 50, token_type: :forest_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 500
      )

      described_class.call(tx.id)

      tx.reload
      expect(tx.status).to eq("sent")
    end
  end
end
