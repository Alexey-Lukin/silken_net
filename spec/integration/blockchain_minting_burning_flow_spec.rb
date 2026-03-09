# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Blockchain minting and burning pipeline" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }
  let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
  let!(:wallet) { tree.wallet || create(:wallet, tree: tree) }
  let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster) }

  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_PRIVATE_KEY"] ||= "0x" + "a" * 64
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x" + "0" * 40
    ENV["FOREST_COIN_CONTRACT_ADDRESS"] ||= "0x" + "1" * 40

    unless defined?(Kredis)
      kredis_mod = Module.new do
        def self.lock(*, **, &block)
          block&.call
        end
      end
      stub_const("Kredis", kredis_mod)
    end

    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_update)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(ActionCable.server).to receive(:broadcast)
  end

  # ---------------------------------------------------------------------------
  # BlockchainMintingService
  # ---------------------------------------------------------------------------
  describe "BlockchainMintingService" do
    let!(:tx) do
      create(:blockchain_transaction,
             wallet: wallet,
             status: :pending,
             amount: 1.0,
             token_type: :carbon_coin,
             to_address: organization.crypto_public_address)
    end

    let(:mock_client) { instance_double(Eth::Client) }
    let(:mock_key) { instance_double(Eth::Key, address: "0xOracle") }

    before do
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Key).to receive(:new).and_return(mock_key)
      allow(mock_client).to receive(:get_balance).and_return(1 * 10**18)
      allow(mock_client).to receive(:transact).and_return("0xfake_tx_hash")
      allow(Eth::Contract).to receive(:from_abi).and_return(double("contract"))
      allow(BlockchainConfirmationWorker).to receive(:perform_in)
    end

    it "mints a single carbon coin transaction" do
      BlockchainMintingService.call(tx.id)

      tx.reload
      expect(tx.status).to eq("sent")
      expect(tx.tx_hash).to eq("0xfake_tx_hash")
    end

    it "processes batch minting for multiple transactions" do
      tx2 = create(:blockchain_transaction,
                   wallet: wallet, status: :pending, amount: 2.0,
                   token_type: :carbon_coin, to_address: organization.crypto_public_address)

      BlockchainMintingService.call_batch([tx.id, tx2.id])

      [tx, tx2].each(&:reload)
      expect(tx.status).to eq("sent")
      expect(tx2.status).to eq("sent")
      expect(tx.tx_hash).to eq(tx2.tx_hash)
    end

    it "skips already confirmed transactions" do
      tx.update!(status: :confirmed)

      expect { BlockchainMintingService.call(tx.id) }.not_to raise_error
      tx.reload
      expect(tx.status).to eq("confirmed")
    end

    it "marks transactions as failed on error" do
      allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC Error")

      expect { BlockchainMintingService.call(tx.id) }.to raise_error(StandardError)
      tx.reload
      expect(tx.status).to eq("failed")
    end

    it "raises when oracle balance is critically low" do
      allow(mock_client).to receive(:get_balance).and_return(0)
      expect { BlockchainMintingService.call(tx.id) }.to raise_error(RuntimeError, /Критично низький баланс/)
    end

    it "supports forest_coin token type" do
      tx.update!(token_type: :forest_coin)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("FOREST_COIN_CONTRACT_ADDRESS").and_return("0xForestCoin")

      BlockchainMintingService.call(tx.id)
      tx.reload
      expect(tx.status).to eq("sent")
    end

    it "schedules confirmation worker after successful send" do
      expect(BlockchainConfirmationWorker).to receive(:perform_in).with(30.seconds, "0xfake_tx_hash")
      BlockchainMintingService.call(tx.id)
    end
  end

  # ---------------------------------------------------------------------------
  # BlockchainBurningService
  # ---------------------------------------------------------------------------
  describe "BlockchainBurningService" do
    let!(:confirmed_tx) do
      create(:blockchain_transaction,
             wallet: wallet, status: :confirmed, amount: 100.0,
             token_type: :carbon_coin, to_address: organization.crypto_public_address)
    end

    let(:mock_client) { instance_double(Eth::Client) }
    let(:mock_key) { instance_double(Eth::Key, address: "0xOracle") }

    before do
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Key).to receive(:new).and_return(mock_key)
      allow(mock_client).to receive(:transact_and_wait).and_return("0xburn_hash")
      allow(Eth::Contract).to receive(:from_abi).and_return(double("contract"))
    end

    it "burns tokens proportionally to damage ratio" do
      # Create AiInsight showing critical stress
      create(:ai_insight,
             analyzable: tree,
             insight_type: :daily_health_summary,
             target_date: cluster.local_yesterday,
             stress_index: 1.0)

      expect {
        BlockchainBurningService.call(organization.id, naas_contract.id, source_tree: tree)
      }.to change(BlockchainTransaction, :count).by(1)

      naas_contract.reload
      expect(naas_contract.status).to eq("breached")

      audit_tx = BlockchainTransaction.last
      expect(audit_tx.tx_hash).to eq("0xburn_hash")
      expect(audit_tx.notes).to include("SLASHING")
    end

    it "skips when no minted amount exists" do
      confirmed_tx.destroy!

      expect {
        BlockchainBurningService.call(organization.id, naas_contract.id)
      }.not_to change(BlockchainTransaction, :count)
    end

    it "creates EWS alert on slashing failure" do
      allow(mock_client).to receive(:transact_and_wait).and_raise(StandardError, "EVM Failure")

      expect {
        begin
          BlockchainBurningService.call(organization.id, naas_contract.id, source_tree: tree)
        rescue StandardError
          nil
        end
      }.to change(EwsAlert, :count).by(1)

      naas_contract.reload
      expect(naas_contract.status).to eq("breached")
    end

    it "calculates damage ratio from single tree death" do
      # No AI insights but source_tree provided → proportional to 1/total_trees
      BlockchainBurningService.call(organization.id, naas_contract.id, source_tree: tree)
      naas_contract.reload
      expect(naas_contract.status).to eq("breached")
    end
  end

  # ---------------------------------------------------------------------------
  # MintCarbonCoinWorker
  # ---------------------------------------------------------------------------
  describe "MintCarbonCoinWorker" do
    let!(:pending_tx) do
      create(:blockchain_transaction,
             wallet: wallet, status: :pending, amount: 5.0,
             token_type: :carbon_coin, to_address: organization.crypto_public_address)
    end

    before do
      allow(BlockchainMintingService).to receive(:call_batch)
    end

    it "processes pending transactions in batches" do
      expect(BlockchainMintingService).to receive(:call_batch).with([pending_tx.id])
      MintCarbonCoinWorker.new.perform([pending_tx.id])
    end

    it "auto-discovers pending transactions when no IDs given" do
      expect(BlockchainMintingService).to receive(:call_batch).with(array_including(pending_tx.id))
      MintCarbonCoinWorker.new.perform
    end

    it "skips when no pending transactions exist" do
      pending_tx.update!(status: :confirmed)
      expect(BlockchainMintingService).not_to receive(:call_batch)
      MintCarbonCoinWorker.new.perform
    end

    it "resets to pending on RPC error for retry" do
      allow(BlockchainMintingService).to receive(:call_batch).and_raise(StandardError, "RPC timeout")

      expect {
        MintCarbonCoinWorker.new.perform([pending_tx.id])
      }.to raise_error(StandardError)
    end
  end

  # ---------------------------------------------------------------------------
  # BurnCarbonTokensWorker
  # ---------------------------------------------------------------------------
  describe "BurnCarbonTokensWorker" do
    let!(:naas) { naas_contract }
    let(:executioner) { create(:user, :admin, organization: organization) }

    before do
      executioner # ensure user exists
      allow(BlockchainBurningService).to receive(:call)
      allow(ActionCable.server).to receive(:broadcast)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "calls burning service and creates maintenance record" do
      expect(BlockchainBurningService).to receive(:call)
        .with(organization.id, naas.id, source_tree: nil)

      expect {
        BurnCarbonTokensWorker.new.perform(organization.id, naas.id)
      }.to change(MaintenanceRecord, :count).by(1)

      record = MaintenanceRecord.last
      expect(record.action_type).to eq("decommissioning")
      expect(record.notes).to include("SLASHING EXECUTED")
    end

    it "includes source tree info when tree_id provided" do
      expect(BlockchainBurningService).to receive(:call)
        .with(organization.id, naas.id, source_tree: tree)

      BurnCarbonTokensWorker.new.perform(organization.id, naas.id, tree.id)

      record = MaintenanceRecord.last
      expect(record.notes).to include(tree.did)
    end

    it "skips already breached contracts" do
      naas.update!(status: :breached)
      expect(BlockchainBurningService).not_to receive(:call)
      BurnCarbonTokensWorker.new.perform(organization.id, naas.id)
    end

    it "skips when contract not found" do
      expect(BlockchainBurningService).not_to receive(:call)
      BurnCarbonTokensWorker.new.perform(organization.id, -1)
    end
  end

  # ---------------------------------------------------------------------------
  # BlockchainConfirmationWorker
  # ---------------------------------------------------------------------------
  describe "BlockchainConfirmationWorker" do
    let(:tx_hash) { "0xconfirmable" }
    let!(:bc_tx) do
      create(:blockchain_transaction,
             wallet: wallet, status: :sent, tx_hash: tx_hash,
             to_address: organization.crypto_public_address)
    end
    let(:mock_client) { instance_double(Eth::Client) }

    before do
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
    end

    it "confirms transaction when receipt shows success" do
      allow(mock_client).to receive(:eth_get_transaction_receipt)
        .and_return({ "result" => { "status" => "0x1" } })

      BlockchainConfirmationWorker.new.perform(tx_hash)
      bc_tx.reload
      expect(bc_tx.status).to eq("confirmed")
    end

    it "fails transaction when receipt shows revert" do
      allow(mock_client).to receive(:eth_get_transaction_receipt)
        .and_return({ "result" => { "status" => "0x0" } })

      BlockchainConfirmationWorker.new.perform(tx_hash)
      bc_tx.reload
      expect(bc_tx.status).to eq("failed")
    end

    it "retries when no receipt yet (mempool pending)" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(nil)

      expect {
        BlockchainConfirmationWorker.new.perform(tx_hash)
      }.to raise_error(RuntimeError, /Очікування підтвердження/)
    end

    it "ignores unknown tx hashes gracefully" do
      allow(mock_client).to receive(:eth_get_transaction_receipt)
        .and_return({ "result" => { "status" => "0x1" } })

      expect {
        BlockchainConfirmationWorker.new.perform("0xunknown_hash")
      }.not_to raise_error
    end
  end
end
