# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Blockchain minting and burning pipeline" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }
  let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
  # [KYC.1] Власна адреса + approved: гейт = статус бенефіціара адреси
  # (без власної адреси правив би org-статус — kyc_approved_for_minting?).
  let!(:wallet) do
    (tree.wallet || create(:wallet, tree: tree)).tap do |w|
      w.update_columns(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
    end
  end
  let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster) }

  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_MINTER_PRIVATE_KEY"] ||= "0x" + "a" * 64
    ENV["ORACLE_SLASHER_PRIVATE_KEY"] ||= "0x" + "c" * 64
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x" + "0" * 40
    ENV["FOREST_COIN_CONTRACT_ADDRESS"] ||= "0x" + "1" * 40
    ENV["DAO_TREASURY_ADDRESS"] ||= "0x" + "2" * 40

    unless defined?(Kredis)
      kredis_mod = Module.new do
        def self.lock(*, **, &block)
          block&.call
        end
      end
      stub_const("Kredis", kredis_mod)
    end
    allow(Kredis).to receive(:lock).and_yield

    silence_broadcasts!(:wallet_balance)
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
      allow(mock_client).to receive_messages(get_balance: 1 * 10**18, transact: "0xfake_tx_hash")
      allow(mock_client).to receive(:call).and_return(0)
      allow(Eth::Contract).to receive(:from_abi).and_return(double("contract"))
      allow(BlockchainConfirmationWorker).to receive(:perform_in)
      Rails.cache.delete(BlockchainMintingService::TREASURY_BALANCE_CACHE_KEY)
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

      BlockchainMintingService.call_batch([ tx.id, tx2.id ])

      reloaded = BlockchainTransaction.where(id: [ tx.id, tx2.id ]).index_by(&:id)
      expect(reloaded[tx.id].status).to eq("sent")
      expect(reloaded[tx2.id].status).to eq("sent")
      expect(reloaded[tx.id].tx_hash).to eq(reloaded[tx2.id].tx_hash)
    end

    it "skips already confirmed transactions" do
      tx.update!(status: :confirmed)

      expect { BlockchainMintingService.call(tx.id) }.not_to raise_error
      tx.reload
      expect(tx.status).to eq("confirmed")
    end

    it "marks transactions as failed on a pre-broadcast error (revert)" do
      allow(mock_client).to receive(:transact).and_raise(StandardError, "execution reverted: RPC")

      expect { BlockchainMintingService.call(tx.id) }.to raise_error(StandardError)
      tx.reload
      expect(tx.status).to eq("failed")
    end

    it "escalates to manual_review on an ambiguous broadcast error (P0-1 double-mint guard)" do
      allow(mock_client).to receive(:transact).and_raise(Net::ReadTimeout, "reset after broadcast")

      expect { BlockchainMintingService.call(tx.id) }.not_to raise_error
      expect(tx.reload.status).to eq("manual_review")
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
      expect(BlockchainConfirmationWorker).to receive(:perform_in).with(30.seconds, "0xfake_tx_hash", kind_of(String))
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
      # [SLASH.2] transact + slashUpTo balanceOf pre-read (1000 SCC ≫ burn ≤100, clamp inert).
      allow(mock_client).to receive_messages(transact: "0xburn_hash", call: 1000 * (10**18))
      allow(Eth::Contract).to receive(:from_abi).and_return(double("contract"))
      allow(BlockchainConfirmationWorker).to receive(:perform_in)
      # [SLASH-1] Slash-path tests assume direct Category-A evidence (gate passes).
      allow_any_instance_of(Slashing::CauseEvidence).to receive(:positive_a?).and_return(true)
    end

    it "burns tokens proportionally to damage ratio" do
      # Create AiInsight showing critical stress
      create(:ai_insight,
             analyzable: tree,
             insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date,
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

    it "creates EWS alert on slashing failure WITHOUT breaching (ARCH.48 — retry can re-execute)" do
      allow(mock_client).to receive(:transact).and_raise(StandardError, "EVM Failure")

      expect {
        begin
          BlockchainBurningService.call(organization.id, naas_contract.id, source_tree: tree)
        rescue StandardError
          nil
        end
      }.to change(EwsAlert, :count).by(1)

      naas_contract.reload
      # [ARCH.48] a failed slash must NOT breach — that would make the worker's status_breached?
      # guard skip every retry (silent burn-abort). The contract stays :active for the retry.
      expect(naas_contract.status).not_to eq("breached")
    end

    it "calculates damage ratio from single tree death" do
      # No AI insights but source_tree provided → proportional to 1/total_trees
      BlockchainBurningService.call(organization.id, naas_contract.id, source_tree: tree)
      naas_contract.reload
      expect(naas_contract.status).to eq("breached")
    end

    # [SLASH-1 §3.2] End-to-end with the REAL CauseEvidence (not stubbed): no tamper alert →
    # no Category-A → freeze (Field Audit), never burn. Closes the false-slash on a natural
    # event (e.g. planned tree-death / drought-as-fraud / natural fire).
    it "freezes (no burn, no breach) end-to-end when there is no Category-A evidence" do
      allow_any_instance_of(Slashing::CauseEvidence).to receive(:positive_a?).and_call_original
      silence_broadcasts!(:alert_new, :alert_notify)

      result = BlockchainBurningService.call(organization.id, naas_contract.id, source_tree: tree)

      expect(result).to eq(:frozen)
      expect(mock_client).not_to have_received(:transact)
      expect(naas_contract.reload.status).not_to eq("breached")
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

    let!(:telemetry_log) do
      create(:telemetry_log, :verified_telemetry, tree: tree)
    end

    before do
      allow(BlockchainMintingService).to receive(:call_batch)
    end

    it "processes pending transactions via telemetry_log (oracle-driven flow)" do
      expect(BlockchainMintingService).to receive(:call_batch)
        .with([ pending_tx.id ], telemetry_log: telemetry_log, created_at_span: all(be_a(Time)).and(be_present))
      MintCarbonCoinWorker.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
    end

    it "auto-discovers pending transactions when no IDs given" do
      expect(BlockchainMintingService).to receive(:call_batch)
        .with(array_including(pending_tx.id), created_at_span: all(be_a(Time)).and(be_present))
      MintCarbonCoinWorker.new.perform
    end

    it "skips when no pending transactions exist" do
      pending_tx.update!(status: :confirmed)
      expect(BlockchainMintingService).not_to receive(:call_batch)
      MintCarbonCoinWorker.new.perform
    end

    it "resets to pending on RPC error for retry (auto-discovery)" do
      allow(BlockchainMintingService).to receive(:call_batch).and_raise(StandardError, "RPC timeout")

      expect {
        MintCarbonCoinWorker.new.perform
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
      # [SLASH-1] outcome :slashed → воркер пише «надгробок». Броадкастів у нього
      # більше немає (UI.4, 2026-07-27), тож стаби на них теж зняті.
      allow(BlockchainBurningService).to receive(:call).and_return(:slashed)
    end

    it "calls burning service and creates maintenance record" do
      expect {
        BurnCarbonTokensWorker.new.perform(organization.id, naas.id)
      }.to change(MaintenanceRecord, :count).by(1)

      expect(BlockchainBurningService).to have_received(:call)
        .with(organization.id, naas.id, source_tree: nil, contractual: false, target_date: nil)

      record = MaintenanceRecord.last
      expect(record.action_type).to eq("decommissioning")
      expect(record.notes).to include("SLASHING EXECUTED")
    end

    it "includes source tree info when tree_id provided" do
      BurnCarbonTokensWorker.new.perform(organization.id, naas.id, tree.id)

      expect(BlockchainBurningService).to have_received(:call)
        .with(organization.id, naas.id, source_tree: tree, contractual: false, target_date: nil)

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
      allow(Web3::RpcConnectionPool).to receive(:client_for).with("ALCHEMY_POLYGON_RPC_URL").and_return(mock_client)
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

  # ---------------------------------------------------------------------------
  # End-to-end Trustless Minting Flow
  # ---------------------------------------------------------------------------
  describe "End-to-end trustless minting flow" do
    let(:mock_client) { instance_double(Eth::Client) }
    let(:mock_key) { instance_double(Eth::Key, address: "0xOracle") }

    before do
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Key).to receive(:new).and_return(mock_key)
      allow(mock_client).to receive_messages(get_balance: 1 * 10**18, transact: "0xtrustless_tx")
      allow(Eth::Contract).to receive(:from_abi).and_return(double("contract"))
      allow(BlockchainConfirmationWorker).to receive(:perform_in)
    end

    it "mints only when both IoTeX and Chainlink verifications pass" do
      # 1. Створюємо pending транзакцію (як від TokenomicsEvaluatorWorker)
      pending_tx = create(:blockchain_transaction,
        wallet: wallet, status: :pending, amount: 1.0,
        token_type: :carbon_coin, to_address: organization.crypto_public_address,
        locked_points: 10_000)

      # 2. Створюємо верифіковану телеметрію (як після IoTeX + Chainlink)
      telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)

      # 3. Виконуємо мінтинг через trustless flow
      BlockchainMintingService.call(pending_tx.id, telemetry_log: telemetry_log)

      pending_tx.reload
      expect(pending_tx.status).to eq("sent")
      expect(pending_tx.tx_hash).to eq("0xtrustless_tx")
      # Перевіряємо аудит-зв'язок з децентралізованими доказами
      expect(pending_tx.chainlink_request_id).to eq(telemetry_log.chainlink_request_id)
      expect(pending_tx.zk_proof_ref).to eq(telemetry_log.zk_proof_ref)
    end

    it "rejects minting when IoTeX verification is missing" do
      pending_tx = create(:blockchain_transaction,
        wallet: wallet, status: :pending, amount: 1.0,
        token_type: :carbon_coin, to_address: organization.crypto_public_address)

      unverified_log = create(:telemetry_log, tree: tree,
        verified_by_iotex: false, oracle_status: "fulfilled")

      expect {
        BlockchainMintingService.call(pending_tx.id, telemetry_log: unverified_log)
      }.to raise_error(RuntimeError, /Data not verified by IoTeX/)

      pending_tx.reload
      expect(pending_tx.status).not_to eq("sent")
    end

    it "rejects minting when Chainlink Oracle consensus is missing" do
      pending_tx = create(:blockchain_transaction,
        wallet: wallet, status: :pending, amount: 1.0,
        token_type: :carbon_coin, to_address: organization.crypto_public_address)

      dispatched_log = create(:telemetry_log, tree: tree,
        verified_by_iotex: true, oracle_status: "dispatched")

      expect {
        BlockchainMintingService.call(pending_tx.id, telemetry_log: dispatched_log)
      }.to raise_error(RuntimeError, /Chainlink Oracle consensus not fulfilled/)
    end

    it "allows minting without telemetry_log (legacy batch flow)" do
      # TokenomicsEvaluatorWorker і InsurancePayoutWorker не передають telemetry_log —
      # guard clauses не активуються, мінтинг працює як раніше.
      pending_tx = create(:blockchain_transaction,
        wallet: wallet, status: :pending, amount: 1.0,
        token_type: :carbon_coin, to_address: organization.crypto_public_address)

      BlockchainMintingService.call(pending_tx.id)

      pending_tx.reload
      expect(pending_tx.status).to eq("sent")
      expect(pending_tx.chainlink_request_id).to be_nil
      expect(pending_tx.zk_proof_ref).to be_nil
    end

    it "correctly releases locked_balance on retries_exhausted rollback" do
      # Створюємо стан після lock_and_mint!: balance=20000, locked_balance=10000
      wallet.update!(balance: 20_000, locked_balance: 10_000)

      pending_tx = create(:blockchain_transaction,
        wallet: wallet, status: :pending, amount: 1.0,
        token_type: :carbon_coin, to_address: organization.crypto_public_address,
        locked_points: 10_000, tx_hash: nil)

      telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)

      job = {
        "args" => [ telemetry_log.id_value, telemetry_log.created_at.iso8601(6) ],
        "error_message" => "All 5 retries exhausted"
      }

      MintCarbonCoinWorker.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      wallet.reload
      pending_tx.reload

      # Balance НЕ змінюється — lock_and_mint! не змінює balance
      expect(wallet.balance).to eq(20_000)
      # locked_balance повертається до 0 — блокування знято
      expect(wallet.locked_balance).to eq(0)
      expect(wallet.available_balance).to eq(20_000)
      expect(pending_tx.status).to eq("failed")
    end
  end
end
