# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainMintingService do
  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_PRIVATE_KEY"] ||= "0x" + "a" * 64
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x" + "0" * 40
    ENV["FOREST_COIN_CONTRACT_ADDRESS"] ||= "0x" + "1" * 40
    ENV["DAO_TREASURY_ADDRESS"] ||= "0x" + "9" * 40

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
    # [B-05]: Stub balanceOf → 0 (below threshold) so insurance_pool_requires_funding? defaults to true.
    # Individual tests override this for specific scenarios.
    allow(mock_client).to receive(:call).and_return(0)
    allow(Kredis).to receive(:lock).and_yield
    Web3::RpcConnectionPool.reset!
    Rails.cache.delete(described_class::TREASURY_CACHE_KEY)
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

    context "when the tree is peaq_did_compromised (SEC.13)" do
      it "skips minting for the compromised tree (revocation guard)" do
        tree = create(:tree, peaq_did_compromised: true)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

        tx = wallet.blockchain_transactions.create!(
          amount: 100,
          token_type: :carbon_coin,
          status: :pending,
          to_address: wallet.crypto_public_address,
          locked_points: 1000
        )

        expect(mock_client).not_to receive(:transact)
        described_class.call(tx.id)

        expect(tx.reload.status).to eq("pending") # not minted — skipped
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

    # [S6.12]: Tokenomics-flow інваріанти.
    # `TokenomicsEvaluatorWorker` → `EvaluateTreeBatchWorker` → `wallet.lock_and_mint!`
    # → `BlockchainTransaction(:pending)` → `MintCarbonCoinWorker#process_batch`
    # → `BlockchainMintingService.call_batch(ids)` БЕЗ `telemetry_log:` параметра.
    #
    # Інваріант (фактичний, як описано у `05_02 §S6.12` PATH 2):
    # 1. Без `telemetry_log:` IoTeX/Chainlink guards СВІДОМО пропускаються —
    #    growth_points було зараховано через `Wallet#credit!` після AES-decrypt
    #    + `valid_sensor_data?` у `TelemetryUnpackerService`.
    # 2. Hadron KYC guard АКТИВНИЙ для всіх шляхів — це security perimeter
    #    тokenomics-flow проти non-compliant wallets.
    # 3. Якщо KYC не approved — raise ComplianceError, мінт не відбувається,
    #    `locked_points` залишаються заблокованими у Wallet (потребують admin
    #    розблокування або повторної KYC-верифікації).
    context "when tokenomics flow without telemetry_log [S6.12]" do
      it "skips IoTeX/Chainlink guards but enforces Hadron KYC" do
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

        # Ні з telemetry_log, ні з verified_by_iotex/oracle_status — все одно мінт проходить
        # бо growth_points вже зараховані через upstream pipeline (per-packet AES-decrypt).
        expect { described_class.call_batch([ tx.id ]) }.not_to raise_error

        tx.reload
        expect(tx.status).to eq("sent")
      end

      it "rejects mint when wallet is NOT Hadron KYC approved (security perimeter)" do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "pending")

        tx = wallet.blockchain_transactions.create!(
          amount: 100,
          token_type: :carbon_coin,
          status: :pending,
          to_address: wallet.crypto_public_address,
          locked_points: 1000
        )

        expect(mock_client).not_to receive(:transact)

        expect {
          described_class.call_batch([ tx.id ])
        }.to raise_error(/Compliance Breach: Wallet is not Hadron KYC approved/)

        # Транзакція залишається `pending` — locked_points не звільнені, чекають reconciliation.
        tx.reload
        expect(tx.status).to eq("pending")
      end

      it "rejects mint when wallet KYC is rejected (terminal state)" do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "rejected")

        tx = wallet.blockchain_transactions.create!(
          amount: 100,
          token_type: :carbon_coin,
          status: :pending,
          to_address: wallet.crypto_public_address,
          locked_points: 1000
        )

        expect {
          described_class.call_batch([ tx.id ])
        }.to raise_error(/Compliance Breach/)
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

    it "returns bare ORG_ for carbon_coin when the tx has no wallet at all" do
      tx = create(:tree).wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: "0x" + "b" * 40, locked_points: 1000
      )
      allow(tx).to receive(:wallet).and_return(nil)

      expect(service.send(:identifier_for, tx)).to eq("ORG_")
    end

    it "returns CLUSTER_GLOBAL for forest_coin when the tx has no wallet at all" do
      tx = create(:tree).wallet.blockchain_transactions.create!(
        amount: 100, token_type: :forest_coin, status: :pending,
        to_address: "0x" + "b" * 40, locked_points: 1000
      )
      allow(tx).to receive(:wallet).and_return(nil)

      expect(service.send(:identifier_for, tx)).to eq("CLUSTER_GLOBAL")
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

  describe "nil tx_hash from transact" do
    it "does not mark transactions as sent when transact returns nil" do
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

      allow(mock_client).to receive(:transact).and_return(nil)

      described_class.call(tx.id)

      tx.reload
      # When tx_hash is nil, the transaction should not be marked as sent
      expect(tx.status).not_to eq("sent")
    end
  end

  describe "DEFAULT_DYNAMIC_TAX_RATE constant [S6.17]" do
    it "is defined as BigDecimal 0.02" do
      expect(described_class::DEFAULT_DYNAMIC_TAX_RATE).to eq(BigDecimal("0.02"))
      expect(described_class::DEFAULT_DYNAMIC_TAX_RATE).to be_a(BigDecimal)
    end
  end

  describe "Dynamic Minting Tax (Hybrid Protocol Gaia)" do
    let(:tree1) { create(:tree) }
    let(:wallet1) { tree1.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved") } }
    let(:tree2) { create(:tree) }
    let(:wallet2) { tree2.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "c" * 40, hadron_kyc_status: "approved") } }
    let!(:tx1) do
      wallet1.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet1.crypto_public_address, locked_points: 1000
      )
    end
    let!(:tx2) do
      wallet2.blockchain_transactions.create!(
        amount: 200, token_type: :carbon_coin, status: :pending,
        to_address: wallet2.crypto_public_address, locked_points: 2000
      )
    end

    context "with batch carbon_coin when insurance pool requires funding" do
      it "doubles array size with forester and DAO Treasury entries" do
        expect(mock_client).to receive(:transact) do |_c, _m, recipients, amounts, identifiers, **_|
          expect(recipients.size).to eq(4)
          expect(amounts.size).to eq(4)
          expect(identifiers.size).to eq(4)
          fake_tx_hash
        end

        described_class.call_batch([ tx1.id, tx2.id ])
      end

      it "routes tax entries to DAO_TREASURY_ADDRESS with TAX_ prefix" do
        dao_treasury = ENV.fetch("DAO_TREASURY_ADDRESS")

        expect(mock_client).to receive(:transact) do |_c, _m, recipients, _amounts, identifiers, **_|
          expect(recipients[1]).to eq(dao_treasury)
          expect(recipients[3]).to eq(dao_treasury)
          expect(identifiers[1]).to start_with("TAX_")
          expect(identifiers[3]).to start_with("TAX_")
          fake_tx_hash
        end

        described_class.call_batch([ tx1.id, tx2.id ])
      end
    end

    context "with batch forest_coin transactions" do
      before do
        tx1.update_column(:token_type, "forest_coin")
        tx2.update_column(:token_type, "forest_coin")
      end

      it "does not apply dynamic tax for forest_coin" do
        expect(mock_client).to receive(:transact) do |_c, _m, recipients, amounts, _identifiers, **_|
          expect(recipients.size).to eq(2)
          expect(amounts.size).to eq(2)
          fake_tx_hash
        end

        described_class.call_batch([ tx1.id, tx2.id ])
      end
    end

    context "when insurance pool does not require funding" do
      before do
        allow_any_instance_of(described_class).to receive(:insurance_pool_requires_funding?).and_return(false)
      end

      it "does not apply tax split for carbon_coin" do
        expect(mock_client).to receive(:transact) do |_c, _m, recipients, amounts, _identifiers, **_|
          expect(recipients.size).to eq(2)
          expect(amounts.size).to eq(2)
          fake_tx_hash
        end

        described_class.call_batch([ tx1.id, tx2.id ])
      end
    end
  end

  describe "#insurance_pool_requires_funding?" do
    let(:service) { described_class.new([ -1 ]) }

    context "when treasury balance is below threshold" do
      before { allow(mock_client).to receive(:call).and_return(0) }

      it "returns true" do
        expect(service.send(:insurance_pool_requires_funding?)).to be true
      end
    end

    context "when treasury balance is above threshold" do
      before do
        # 200,000 SCC in wei (above 100,000 threshold)
        allow(mock_client).to receive(:call).and_return(200_000 * 10**18)
      end

      it "returns false" do
        expect(service.send(:insurance_pool_requires_funding?)).to be false
      end
    end

    context "when treasury balance equals threshold" do
      before do
        allow(mock_client).to receive(:call).and_return(100_000 * 10**18)
      end

      it "returns false" do
        expect(service.send(:insurance_pool_requires_funding?)).to be false
      end
    end

    context "when RPC call fails" do
      before do
        allow(mock_client).to receive(:call).and_raise(StandardError, "RPC 429 Too Many Requests")
      end

      it "returns false as safe fallback (E.46: no spurious 2% tax during RPC degradation)" do
        expect(service.send(:insurance_pool_requires_funding?)).to be false
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/DAO Treasury balance check failed/)
        service.send(:insurance_pool_requires_funding?)
      end
    end

    context "when RPC times out" do
      before do
        allow(mock_client).to receive(:call).and_raise(Timeout::Error, "execution expired")
      end

      it "returns false as safe fallback (E.46: no spurious 2% tax during RPC degradation)" do
        expect(service.send(:insurance_pool_requires_funding?)).to be false
      end
    end

    context "with caching" do
      it "caches the result and does not call RPC again" do
        allow(mock_client).to receive(:call).and_return(0)

        service.send(:insurance_pool_requires_funding?)
        service.send(:insurance_pool_requires_funding?)

        # balanceOf should only be called once (cached after first call)
        expect(mock_client).to have_received(:call).once
      end

      it "does not cache RPC failures" do
        responses = [ -> { raise StandardError, "RPC error" }, -> { 200_000 * 10**18 } ]
        allow(mock_client).to receive(:call) { responses.shift.call }

        # First call fails → false (E.46: not cached, graceful degradation)
        expect(service.send(:insurance_pool_requires_funding?)).to be false
        # Second call succeeds → false (pool has sufficient funds, now cached)
        expect(service.send(:insurance_pool_requires_funding?)).to be false
      end
    end
  end

  describe "DEFAULT_INSURANCE_POOL_THRESHOLD constant [S6.17]" do
    it "is defined as 100_000" do
      expect(described_class::DEFAULT_INSURANCE_POOL_THRESHOLD).to eq(100_000)
    end
  end

  describe "batch dry-run guard (Problem 1: Atomic Batch Revert)" do
    let(:tree1) { create(:tree) }
    let(:wallet1) { tree1.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved") } }
    let(:tree2) { create(:tree) }
    let(:wallet2) { tree2.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "c" * 40, hadron_kyc_status: "approved") } }
    let!(:tx1) do
      wallet1.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet1.crypto_public_address, locked_points: 1000
      )
    end
    let!(:tx2) do
      wallet2.blockchain_transactions.create!(
        amount: 200, token_type: :carbon_coin, status: :pending,
        to_address: wallet2.crypto_public_address, locked_points: 2000
      )
    end

    context "when dry-run succeeds (no revert)" do
      before do
        # eth_call (dry-run) succeeds → no revert
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything).and_return(nil)
      end

      it "proceeds with batch mint via transact" do
        allow(mock_client).to receive(:transact).with(anything, "batchMint", anything, anything, anything, anything).and_return(fake_tx_hash)

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(tx1.reload.status).to eq("sent")
        expect(tx2.reload.status).to eq("sent")
        expect(tx1.reload.tx_hash).to eq(fake_tx_hash)
      end
    end

    context "when dry-run detects EVM revert" do
      before do
        # eth_call (dry-run) fails with revert → fallback to individual mints
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything)
          .and_raise(StandardError, "execution reverted: KYC not approved")
        # balanceOf call for insurance pool
        allow(mock_client).to receive(:call).with(anything, "balanceOf", anything).and_return(0)
      end

      it "falls back to individual mint() calls" do
        # Expect individual mint calls (one per tx), not batchMint
        tx_hashes = [ "0x" + "a" * 64, "0x" + "b" * 64 ]
        call_count = 0

        allow(mock_client).to receive(:transact) do |_c, method, *_args, **_opts|
          expect(method).to eq("mint")
          hash = tx_hashes[call_count]
          call_count += 1
          hash
        end

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(tx1.reload.status).to eq("sent")
        expect(tx2.reload.status).to eq("sent")
        # Individual mints produce different tx_hashes
        expect(tx1.reload.tx_hash).to eq(tx_hashes[0])
        expect(tx2.reload.tx_hash).to eq(tx_hashes[1])
      end

      it "marks only the poisoned entry as failed when individual mint reverts" do
        # tx1 succeeds individually, tx2 fails
        allow(mock_client).to receive(:transact) do |_c, _method, to_address, *_args, **_opts|
          if to_address == wallet2.crypto_public_address
            raise StandardError, "KYC revoked for this wallet"
          end
          "0x" + "a" * 64
        end

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(tx1.reload.status).to eq("sent")
        expect(tx2.reload.status).to eq("failed")
        expect(tx2.reload.error_message).to include("KYC revoked")
      end
    end

    context "when dry-run fails with network error (not revert)" do
      before do
        # eth_call fails with timeout → NOT a revert, proceed optimistically
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything)
          .and_raise(Net::ReadTimeout, "RPC timeout")
        # balanceOf call for insurance pool
        allow(mock_client).to receive(:call).with(anything, "balanceOf", anything).and_return(0)
      end

      it "proceeds with batch mint optimistically (network error is not a revert)" do
        allow(mock_client).to receive(:transact).with(anything, "batchMint", anything, anything, anything, anything).and_return(fake_tx_hash)

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(tx1.reload.status).to eq("sent")
        expect(tx2.reload.status).to eq("sent")
      end
    end
  end

  describe "binary search poisoned record isolation" do
    # Create 6 wallets/trees to test binary search (above MIN_BINARY_SEARCH_SIZE=4)
    let(:trees) { Array.new(6) { create(:tree) } }
    let(:wallets) do
      trees.each_with_index.map do |tree, i|
        tree.wallet.tap do |w|
          w.update!(
            crypto_public_address: "0x" + (("a".ord + i).chr * 40),
            hadron_kyc_status: "approved"
          )
        end
      end
    end
    let!(:transactions) do
      wallets.map do |w|
        w.blockchain_transactions.create!(
          amount: 100, token_type: :carbon_coin, status: :pending,
          to_address: w.crypto_public_address, blockchain_network: "evm",
          locked_points: 1000
        )
      end
    end

    # Helper to identify which address is the poisoned one
    let(:poisoned_address) { wallets[2].crypto_public_address }

    context "when 1 out of 6 transactions is poisoned" do
      before do
        # Full batch dry-run reverts (initial trigger)
        # Sub-batch dry-runs: only reverts if poisoned_address is included
        call_count = 0
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything) do |_c, _m, recipients, *_args|
          call_count += 1
          if recipients.include?(poisoned_address)
            raise StandardError, "execution reverted: KYC not approved"
          end
          nil # success
        end
        # balanceOf for insurance pool
        allow(mock_client).to receive(:call).with(anything, "balanceOf", anything).and_return(0)
      end

      it "isolates the poisoned record and batch-mints the clean ones" do
        batch_mint_count = 0
        individual_mint_count = 0

        allow(mock_client).to receive(:transact) do |_c, method, *args, **_opts|
          if method == "batchMint"
            batch_mint_count += 1
            # Verify poisoned address is NOT in clean batches
            recipients = args[0]
            expect(recipients).not_to include(poisoned_address)
          else
            individual_mint_count += 1
          end
          "0x" + "f" * 64
        end

        described_class.call_batch(transactions.map(&:id))

        # Clean transactions should be sent via batchMint (not individual mints)
        expect(batch_mint_count).to be >= 1
        # The poisoned tx (and its sub-batch neighbors) go through individual mints
        expect(individual_mint_count).to be >= 1

        # All clean transactions should be sent
        clean_txs = transactions.reject { |tx| tx.to_address == poisoned_address }
        clean_txs.each do |tx|
          expect(tx.reload.status).to eq("sent")
        end
      end

      it "marks the poisoned transaction as failed" do
        allow(mock_client).to receive(:transact) do |_c, _method, to_address_or_recipients, *_args, **_opts|
          # Individual mint for poisoned address fails
          if to_address_or_recipients == poisoned_address
            raise StandardError, "KYC revoked for this wallet"
          end
          "0x" + "f" * 64
        end

        described_class.call_batch(transactions.map(&:id))

        poisoned_tx = transactions.find { |tx| tx.to_address == poisoned_address }
        expect(poisoned_tx.reload.status).to eq("failed")
        expect(poisoned_tx.reload.error_message).to include("KYC revoked")

        # Other transactions should succeed
        clean_txs = transactions.reject { |tx| tx.to_address == poisoned_address }
        clean_txs.each do |tx|
          expect(tx.reload.status).to eq("sent")
        end
      end
    end

    context "when binary search reaches minimum batch size" do
      before do
        # ALL dry-runs revert (all records appear poisoned)
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything)
          .and_raise(StandardError, "execution reverted: contract error")
        allow(mock_client).to receive(:call).with(anything, "balanceOf", anything).and_return(0)
      end

      it "falls back to individual mints when all sub-batches revert" do
        mint_methods = []
        allow(mock_client).to receive(:transact) do |_c, method, *_args, **_opts|
          mint_methods << method
          "0x" + "f" * 64
        end

        described_class.call_batch(transactions.map(&:id))

        # When every sub-batch reverts, eventually all txs are minted individually
        expect(mint_methods).to all(eq("mint"))
        transactions.each do |tx|
          expect(tx.reload.status).to eq("sent")
        end
      end
    end

    context "when clean sub-batch batchMint transact fails" do
      before do
        # First dry-run (full batch) reverts
        first_call = true
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything) do |*_args|
          if first_call
            first_call = false
            raise StandardError, "execution reverted: KYC not approved"
          end
          nil # sub-batch dry-runs succeed
        end
        allow(mock_client).to receive(:call).with(anything, "balanceOf", anything).and_return(0)
      end

      it "falls back to individual mints for the sub-batch if batchMint transact fails" do
        transact_count = 0
        allow(mock_client).to receive(:transact) do |_c, method, *_args, **_opts|
          transact_count += 1
          if method == "batchMint"
            raise StandardError, "nonce too low" # simulate transact failure
          end
          "0x" + "f" * 64 # individual mints succeed
        end

        described_class.call_batch(transactions.map(&:id))

        # All txs should still eventually be sent (via individual mint fallback)
        transactions.each do |tx|
          expect(tx.reload.status).to eq("sent")
        end
      end
    end
  end

  describe "#evm_revert?" do
    let(:service) { described_class.new([ -1 ]) }

    it "returns true for 'execution reverted' errors" do
      expect(service.send(:evm_revert?, StandardError.new("execution reverted: KYC"))).to be true
    end

    it "returns true for 'revert' errors" do
      expect(service.send(:evm_revert?, StandardError.new("Transaction revert"))).to be true
    end

    it "returns true for 'out of gas' errors" do
      expect(service.send(:evm_revert?, StandardError.new("out of gas"))).to be true
    end

    it "returns false for network errors" do
      expect(service.send(:evm_revert?, Net::ReadTimeout.new("RPC timeout"))).to be false
    end

    it "returns false for connection errors" do
      expect(service.send(:evm_revert?, Errno::ECONNREFUSED.new("Connection refused"))).to be false
    end
  end

  # -----------------------------------------------------------------------
  # S3.1: Comprehensive Guard Clause Tests (Oracle-driven vs Batch Emission)
  # -----------------------------------------------------------------------
  describe "S3.1 — guard clause scenarios" do
    let(:tree) { create(:tree) }
    let(:wallet) do
      tree.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved") }
    end
    let!(:tx) do
      wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )
    end

    context "when telemetry_log is present (oracle-driven flow)" do
      it "blocks minting when IoTeX not verified AND Chainlink not fulfilled" do
        log = create(:telemetry_log, tree: tree, verified_by_iotex: false, oracle_status: "pending")

        expect {
          described_class.call(tx.id, telemetry_log: log)
        }.to raise_error(RuntimeError, /Data not verified by IoTeX/)
      end

      it "blocks minting when IoTeX verified but Chainlink pending" do
        log = create(:telemetry_log, tree: tree, verified_by_iotex: true,
                                     oracle_status: "pending", zk_proof_ref: "zk-proof-123")

        expect {
          described_class.call(tx.id, telemetry_log: log)
        }.to raise_error(RuntimeError, /Chainlink Oracle consensus not fulfilled/)
      end

      it "blocks minting when IoTeX verified but Chainlink dispatched (not yet fulfilled)" do
        log = create(:telemetry_log, tree: tree, verified_by_iotex: true,
                                     oracle_status: "dispatched", zk_proof_ref: "zk-proof-123")

        expect {
          described_class.call(tx.id, telemetry_log: log)
        }.to raise_error(RuntimeError, /Chainlink Oracle consensus not fulfilled/)
      end

      it "blocks minting when IoTeX verified but Chainlink failed" do
        log = create(:telemetry_log, tree: tree, verified_by_iotex: true,
                                     oracle_status: "failed", zk_proof_ref: "zk-proof-123")

        expect {
          described_class.call(tx.id, telemetry_log: log)
        }.to raise_error(RuntimeError, /Chainlink Oracle consensus not fulfilled/)
      end

      it "allows minting when both IoTeX and Chainlink are fulfilled" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree)

        described_class.call(tx.id, telemetry_log: log)

        tx.reload
        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to be_present
      end

      it "stores verification audit trail on blockchain_transaction" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree)

        described_class.call(tx.id, telemetry_log: log)

        tx.reload
        expect(tx.chainlink_request_id).to eq(log.chainlink_request_id)
        expect(tx.zk_proof_ref).to eq(log.zk_proof_ref)
      end
    end

    context "without telemetry_log (batch emission flow)" do
      it "bypasses IoTeX and Chainlink guards when telemetry_log is nil" do
        # This is the tokenomics flow — growth_points already verified by pipeline
        described_class.call(tx.id)

        tx.reload
        expect(tx.status).to eq("sent")
      end

      it "does not store chainlink/iotex audit trail when telemetry_log is nil" do
        described_class.call(tx.id)

        tx.reload
        expect(tx.chainlink_request_id).to be_nil
        expect(tx.zk_proof_ref).to be_nil
      end
    end

    context "when hadron_kyc_status is not approved" do
      it "blocks minting with KYC pending in oracle-driven flow" do
        wallet.update!(hadron_kyc_status: "pending")
        log = create(:telemetry_log, :verified_telemetry, tree: tree)

        expect {
          described_class.call(tx.id, telemetry_log: log)
        }.to raise_error(RuntimeError, /Compliance Breach: Wallet is not Hadron KYC approved/)
      end

      it "blocks minting with KYC pending in batch emission flow" do
        wallet.update!(hadron_kyc_status: "pending")

        expect {
          described_class.call(tx.id)
        }.to raise_error(RuntimeError, /Compliance Breach: Wallet is not Hadron KYC approved/)
      end

      it "blocks minting with KYC rejected in oracle-driven flow" do
        wallet.update!(hadron_kyc_status: "rejected")
        log = create(:telemetry_log, :verified_telemetry, tree: tree)

        expect {
          described_class.call(tx.id, telemetry_log: log)
        }.to raise_error(RuntimeError, /Compliance Breach: Wallet is not Hadron KYC approved/)
      end

      it "blocks minting with KYC rejected in batch emission flow" do
        wallet.update!(hadron_kyc_status: "rejected")

        expect {
          described_class.call(tx.id)
        }.to raise_error(RuntimeError, /Compliance Breach: Wallet is not Hadron KYC approved/)
      end

      it "allows minting with KYC approved in both flows" do
        expect(wallet.hadron_kyc_status).to eq("approved")

        # Oracle-driven
        log = create(:telemetry_log, :verified_telemetry, tree: tree)
        described_class.call(tx.id, telemetry_log: log)
        tx.reload
        expect(tx.status).to eq("sent")

        # Batch emission (create new pending tx)
        tx2 = wallet.blockchain_transactions.create!(
          amount: 50, token_type: :carbon_coin, status: :pending,
          to_address: wallet.crypto_public_address, locked_points: 500
        )
        described_class.call(tx2.id)
        tx2.reload
        expect(tx2.status).to eq("sent")
      end
    end

    context "with Prometheus metrics during guard clause enforcement" do
      it "does not increment SCC_MINTED_TOTAL when IoTeX guard blocks minting" do
        log = create(:telemetry_log, tree: tree, verified_by_iotex: false, oracle_status: "fulfilled")
        metric = SilkenNet::Metrics::SCC_MINTED_TOTAL
        before_val = metric.get(labels: { token_type: "carbon_coin" })

        expect { described_class.call(tx.id, telemetry_log: log) }.to raise_error(RuntimeError)

        expect(metric.get(labels: { token_type: "carbon_coin" })).to eq(before_val)
      end

      it "does not increment SCC_MINTED_TOTAL when Hadron KYC blocks minting" do
        wallet.update!(hadron_kyc_status: "pending")
        metric = SilkenNet::Metrics::SCC_MINTED_TOTAL
        before_val = metric.get(labels: { token_type: "carbon_coin" })

        expect { described_class.call(tx.id) }.to raise_error(RuntimeError)

        expect(metric.get(labels: { token_type: "carbon_coin" })).to eq(before_val)
      end

      it "increments SCC_MINTED_TOTAL only after successful minting" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree)
        metric = SilkenNet::Metrics::SCC_MINTED_TOTAL
        before_val = metric.get(labels: { token_type: "carbon_coin" })

        described_class.call(tx.id, telemetry_log: log)

        expect(metric.get(labels: { token_type: "carbon_coin" })).to be > before_val
      end

      it "increments MINT_ATTEMPTS_TOTAL and MINT_SUCCESS_TOTAL on a successful mint" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree)
        attempts = SilkenNet::Metrics::MINT_ATTEMPTS_TOTAL
        success  = SilkenNet::Metrics::MINT_SUCCESS_TOTAL
        attempts_before = attempts.get(labels: { token_type: "carbon_coin" })
        success_before  = success.get(labels: { token_type: "carbon_coin" })

        described_class.call(tx.id, telemetry_log: log)

        expect(attempts.get(labels: { token_type: "carbon_coin" })).to be > attempts_before
        expect(success.get(labels: { token_type: "carbon_coin" })).to be > success_before
      end

      it "does not increment MINT_ATTEMPTS_TOTAL when a guard blocks before the on-chain attempt" do
        log = create(:telemetry_log, tree: tree, verified_by_iotex: false, oracle_status: "fulfilled")
        attempts = SilkenNet::Metrics::MINT_ATTEMPTS_TOTAL
        attempts_before = attempts.get(labels: { token_type: "carbon_coin" })

        expect { described_class.call(tx.id, telemetry_log: log) }.to raise_error(RuntimeError)

        expect(attempts.get(labels: { token_type: "carbon_coin" })).to eq(attempts_before)
      end
    end
  end

  describe "Kredis lock behavior (S6.5)" do
    it "acquires Kredis lock with 120 second timeout for minting" do
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

      expect(Kredis).to receive(:lock).with(
        anything,
        expires_in: 120.seconds,
        after_timeout: :raise
      ).and_yield

      described_class.call(tx.id)
    end

    it "raises when lock cannot be acquired (concurrent minting prevention)" do
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

      # Simulate lock timeout (another process holds the lock)
      allow(Kredis).to receive(:lock).and_raise(Kredis::LockTimeout, "Lock timeout")

      expect { described_class.call(tx.id) }.to raise_error(Kredis::LockTimeout)
    end

    it "releases lock even when RPC call fails (no lock leak)" do
      allow(mock_client).to receive(:transact).and_raise(StandardError, "Slow RPC timeout")

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

      lock_released = false
      allow(Kredis).to receive(:lock) do |*, **, &block|
        block.call
        lock_released = true
      rescue StandardError
        lock_released = true
        raise
      end

      expect { described_class.call(tx.id) }.to raise_error(StandardError, "Slow RPC timeout")
      expect(lock_released).to be true
    end
  end

  # --------------------------------------------------------------------
  # Coverage gaps for guard clauses,
  # binary-search edges, and finalize_sent_transaction telemetry write.
  # Each example targets a real-logic branch (guard / fallback / write),
  # NOT defensive `&.`-nil padding.
  # --------------------------------------------------------------------

  describe "missing-wallet guard (SEC.13 prerequisite)" do
    # belongs_to :wallet is `optional: true` — slashing audit-tx for a
    # cluster-wide kill is allowed to land without a wallet (see model
    # comment). Such tx must NOT reach the contract — the guard at L97
    # raises before any RPC call.
    let(:tree) { create(:tree) }
    let(:wallet) do
      tree.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved") }
    end
    let!(:tx) do
      wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )
    end

    it "raises Compliance Breach when tx.wallet is nil" do
      allow_any_instance_of(BlockchainTransaction).to receive(:wallet).and_return(nil)
      expect { described_class.call(tx.id) }
        .to raise_error(RuntimeError, /Compliance Breach: Missing wallet for TX/)
    end
  end

  describe "SEC.13 compromised-tree handling — edge cases" do
    let(:tree) { create(:tree) }
    let(:wallet) do
      tree.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved") }
    end
    let!(:tx) do
      wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )
    end

    it "returns early without RPC when every tx in the batch is peaq_did_compromised" do
      allow_any_instance_of(Tree).to receive(:peaq_did_compromised?).and_return(true)
      allow(Rails.logger).to receive(:warn)

      expect(mock_client).not_to receive(:transact)
      expect { described_class.call(tx.id) }.not_to raise_error

      expect(tx.reload.status).to eq("processing").or eq("pending")
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/\[SEC\.13\] Mint skipped for 1 peaq_did_compromised tree/))
    end

    it "skips the peaq compromise filter for org-level tx (wallet without tree)" do
      # Covers the `wallet&.tree&.peaq_did_compromised?` chained-nav
      # ELSE: wallet exists but has no tree → tx is NOT classified as
      # compromised and minting proceeds normally.
      allow_any_instance_of(Wallet).to receive(:tree).and_return(nil)

      expect { described_class.call(tx.id) }.not_to raise_error
      expect(tx.reload.status).to eq("sent")
    end

    it "filters compromised txs out of the batch but mints the rest" do
      # Partial-compromise: after deleting compromised entries, @wallet_mapping
      # is non-empty — service must keep going and mint surviving txs.
      good_tree = create(:tree)
      good_wallet = good_tree.wallet.tap do |w|
        w.update!(crypto_public_address: "0x" + "c" * 40, hadron_kyc_status: "approved")
      end
      good_tx = good_wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: good_wallet.crypto_public_address, locked_points: 1000
      )

      # Only `tree` (the compromised one) returns true.
      allow_any_instance_of(Tree).to receive(:peaq_did_compromised?) do |t|
        t.id == tree.id
      end

      described_class.call_batch([ tx.id, good_tx.id ])

      expect(tx.reload.status).not_to eq("sent")
      expect(good_tx.reload.status).to eq("sent")
    end
  end

  describe "send_clean_batch — size==1 short-circuit" do
    # When binary-search isolates a single clean tx, send_clean_batch
    # delegates to mint_individual instead of issuing a 1-element
    # batchMint (gas waste). Covers L383-384.
    let(:service) { described_class.new([ -1 ]) }
    let(:tree) { create(:tree) }
    let(:wallet) do
      tree.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved") }
    end
    let!(:tx) do
      wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )
    end

    it "delegates to mint_individual when there is exactly one clean tx" do
      expect(service).to receive(:mint_individual)
        .with(mock_client, mock_contract, mock_key, "carbon_coin", tx).once
      expect(mock_client).not_to receive(:transact)

      service.send(:send_clean_batch, mock_client, mock_contract, mock_key, "carbon_coin", [ tx ])
    end

    it "is a no-op for an empty txs array (defensive recursion guard)" do
      expect(mock_client).not_to receive(:transact)
      expect { service.send(:send_clean_batch, mock_client, mock_contract, mock_key, "carbon_coin", []) }
        .not_to raise_error
    end
  end

  describe "process_half — empty half guard" do
    # binary search splits an odd-sized array → one half can land empty
    # at recursive boundaries; process_half must short-circuit.
    let(:service) { described_class.new([ -1 ]) }

    it "returns immediately when half_txs is empty" do
      expect(service).not_to receive(:batch_dry_run_reverts?)
      service.send(:process_half, mock_client, mock_contract, mock_key, "carbon_coin", [],
                   [], [], depth: 0, original_batch_size: 6)
    end
  end

  describe "binary search >30% poisoned fallback" do
    # When the first split surfaces more than POISONED_RATIO_THRESHOLD
    # of the original batch as poisoned, the algorithm gives up and
    # routes the remainder straight to individual mints. Covers L317-321.
    let(:trees) { Array.new(8) { create(:tree) } }
    let(:wallets) do
      trees.each_with_index.map do |t, i|
        t.wallet.tap do |w|
          # 0x + 40 hex chars; use lower-nibble of index so all 8 wallets
          # produce valid addresses (a..h would fall outside 0-9a-f).
          w.update!(crypto_public_address: "0x" + i.to_s(16) * 40, hadron_kyc_status: "approved")
        end
      end
    end
    let!(:transactions) do
      wallets.map do |w|
        w.blockchain_transactions.create!(
          amount: 100, token_type: :carbon_coin, status: :pending,
          to_address: w.crypto_public_address, blockchain_network: "evm", locked_points: 1000
        )
      end
    end

    it "fallbacks to individual mints when poisoned ratio exceeds 30%" do
      # batchMint dry-run always reverts → drives binary search down to
      # MIN_BINARY_SEARCH_SIZE bottoms, accumulating poisoned > 30%.
      allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything)
        .and_raise(StandardError, "execution reverted: contract error")
      allow(mock_client).to receive(:call).with(anything, "balanceOf", anything).and_return(0)
      allow(Rails.logger).to receive(:warn)

      mint_calls = []
      allow(mock_client).to receive(:transact) do |_c, method, *_args, **_opts|
        mint_calls << method
        "0x" + "f" * 64
      end

      described_class.call_batch(transactions.map(&:id))

      expect(mint_calls).to all(eq("mint"))
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/\[Web3\] Binary search: >30% poisoned/)).at_least(:once)
    end
  end

  describe "finalize_sent_transaction — telemetry_log audit trail" do
    # When a poisoned record gets recovered through mint_individual
    # (not the inline batch path), finalize_sent_transaction is the
    # only place that writes chainlink_request_id / zk_proof_ref.
    let(:service) { described_class.new([ -1 ], telemetry_log: log) }
    let(:tree) { create(:tree) }
    let(:wallet) do
      tree.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved") }
    end
    let!(:tx) do
      wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )
    end
    let(:log) do
      create(:telemetry_log,
        tree: tree, verified_by_iotex: true, oracle_status: "fulfilled",
        chainlink_request_id: "chainlink-finalize-1", zk_proof_ref: "zk-finalize-1"
      )
    end

    it "persists chainlink_request_id and zk_proof_ref via finalize_sent_transaction" do
      service.send(:finalize_sent_transaction, tx, fake_tx_hash, "carbon_coin")

      tx.reload
      expect(tx.status).to eq("sent")
      expect(tx.tx_hash).to eq(fake_tx_hash)
      expect(tx.chainlink_request_id).to eq("chainlink-finalize-1")
      expect(tx.zk_proof_ref).to eq("zk-finalize-1")
    end

    it "leaves chainlink fields nil when no telemetry_log was attached" do
      bare = described_class.new([ -1 ])
      bare.send(:finalize_sent_transaction, tx, fake_tx_hash, "carbon_coin")

      tx.reload
      expect(tx.status).to eq("sent")
      expect(tx.chainlink_request_id).to be_nil
      expect(tx.zk_proof_ref).to be_nil
    end
  end
end
