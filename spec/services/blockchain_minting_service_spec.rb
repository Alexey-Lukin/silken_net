# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainMintingService do
  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_MINTER_PRIVATE_KEY"] ||= "0x" + "a" * 64
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x" + "0" * 40
    ENV["FOREST_COIN_CONTRACT_ADDRESS"] ||= "0x" + "1" * 40
    ENV["DAO_TREASURY_ADDRESS"] ||= "0x" + "9" * 40

    silence_broadcasts!(:wallet_balance, :tree_map)
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
    Rails.cache.delete(described_class::TREASURY_BALANCE_CACHE_KEY)
  end

  let(:fake_tx_hash) { "0x" + "f" * 64 }
  let(:mock_client) { instance_double(Eth::Client) }
  let(:mock_key) { instance_double(Eth::Key, address: "0x" + "d" * 40) }
  let(:mock_contract) { instance_double(Eth::Contract) }


  describe ".call" do
    context "when no pending transactions exist" do
      it "returns early when no pending transactions" do
        described_class.call(-1)

        expect(mock_client).not_to have_received(:transact)
      end
    end

    context "with the ARCH.62 mint circuit-breaker" do
      let(:tx) do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
        wallet.blockchain_transactions.create!(
          amount: 10.0, token_type: :carbon_coin, status: :pending, to_address: "0x" + "b" * 40
        )
      end

      it "holds the batch as :pending WITHOUT minting when the circuit flag is set (re-runnable)" do
        allow(Kredis).to receive(:flag).and_return(instance_double(Kredis::Types::Flag, marked?: true))

        described_class.call(tx.id)

        expect(mock_client).not_to have_received(:transact)

        # HOLD leaves the tx :pending (auto-recovers next cycle when the flag clears) — NOT
        # escalated to manual_review (that would orphan a clean, never-broadcast tx).
        expect(tx.reload.status).to eq("pending")
      end

      it "mints normally when the circuit flag is clear (default)" do
        allow(Kredis).to receive(:flag).and_return(instance_double(Kredis::Types::Flag, marked?: false))
        allow(mock_client).to receive(:transact).and_return(fake_tx_hash)

        described_class.call(tx.id)

        expect(tx.reload.status).to eq("sent")
      end

      it "fails OPEN (mint proceeds) when the circuit-flag read raises (Redis blip)" do
        allow(Kredis).to receive(:flag).and_raise(StandardError, "redis down")
        allow(Rails.logger).to receive(:error)
        allow(mock_client).to receive(:transact).and_return(fake_tx_hash)

        described_class.call(tx.id)

        expect(tx.reload.status).to eq("sent")
      end

      it "halts ONLY the tripped token, mints the other (per-token isolation)" do
        tree_c = create(:tree)
        tree_c.wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
        txc = tree_c.wallet.blockchain_transactions.create!(amount: 10.0, token_type: :carbon_coin, status: :pending, to_address: "0x" + "b" * 40)
        tree_f = create(:tree)
        tree_f.wallet.update!(crypto_public_address: "0x" + "c" * 40, hadron_kyc_status: "approved")
        txf = tree_f.wallet.blockchain_transactions.create!(amount: 10.0, token_type: :forest_coin, status: :pending, to_address: "0x" + "c" * 40)

        allow(Kredis).to receive(:flag).with("#{described_class::MINT_CIRCUIT_FLAG_PREFIX}carbon_coin")
          .and_return(instance_double(Kredis::Types::Flag, marked?: true))
        allow(Kredis).to receive(:flag).with("#{described_class::MINT_CIRCUIT_FLAG_PREFIX}forest_coin")
          .and_return(instance_double(Kredis::Types::Flag, marked?: false))
        allow(mock_client).to receive(:transact).and_return(fake_tx_hash)

        described_class.call_batch([ txc.id, txf.id ])

        # 🔴 [DOC-T.89] Доти цей приклад доводив ізоляцію end-to-end: carbon held ⊥ SFC
        # ЗАМІНЧЕНО. Після гарда активації governance SFC не мінтиться НІКОЛИ, тож
        # інвертувати умову не можна — приклад став би зеленим із ДВОХ причин одразу
        # (circuit tripped ⊥ SFC-гард), тобто вакуумним щодо самої ізоляції.
        # Ізоляція лишається доказовною на рівні ПРЕДИКАТА: він per-token і від гарда
        # не залежить. End-to-end доказ через SFC-двері повернеться разом із SEC.1.
        expect(txc.reload.status).to eq("pending") # carbon held circuit-breaker'ом
        expect(txf.reload.status).to eq("pending") # forest held DOC-T.89-гардом, не circuit'ом

        service = described_class.new(txc.id)
        expect(service.send(:mint_circuit_broken?, "carbon_coin")).to be(true)
        expect(service.send(:mint_circuit_broken?, "forest_coin")).to be(false)
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

        described_class.call(tx.id)

        expect(mock_client).not_to have_received(:transact)
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

        described_class.call(tx.id)

        expect(mock_client).not_to have_received(:transact)
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

      # [S2 FIX] Non-approved KYC → per-tx SKIP (не raise на весь батч). tx лишається :pending
      # (чекає KYC), transact НЕ викликається, батч не абортується.
      it "skips (does not mint) a non-Hadron-KYC-approved wallet without aborting" do
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

        expect { described_class.call_batch([ tx.id ]) }.not_to raise_error

        expect(mock_client).not_to have_received(:transact)
        # Транзакція лишається `pending` — locked_points не звільнені, чекають KYC-верифікації.
        expect(tx.reload.status).to eq("pending")
      end

      it "skips a wallet with rejected KYC (terminal state) without aborting" do
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

        expect { described_class.call_batch([ tx.id ]) }.not_to raise_error
        expect(tx.reload.status).to eq("pending")
      end

      # [S2 blast-radius] The load-bearing regression: one non-approved wallet must NOT block the
      # rest of the pending pool (old raise aborted the whole batch → mass rollback of others).
      it "mints approved wallets and skips the non-approved one in the same batch" do
        tree1 = create(:tree)
        good = tree1.wallet
        good.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
        good_tx = good.blockchain_transactions.create!(
          amount: 100, token_type: :carbon_coin, status: :pending,
          to_address: good.crypto_public_address, locked_points: 1000
        )

        tree2 = create(:tree)
        bad = tree2.wallet
        bad.update!(crypto_public_address: "0x" + "c" * 40, hadron_kyc_status: "pending")
        bad_tx = bad.blockchain_transactions.create!(
          amount: 100, token_type: :carbon_coin, status: :pending,
          to_address: bad.crypto_public_address, locked_points: 1000
        )

        expect { described_class.call_batch([ good_tx.id, bad_tx.id ]) }.not_to raise_error

        expect(good_tx.reload.status).to eq("sent")     # approved minted
        expect(bad_tx.reload.status).to eq("pending")   # non-approved left waiting, NOT rolled back
      end

      # [KYC.1] Custodial-гаманець (без власної адреси) мінтить на адресу організації
      # → KYC-гейт = статус БЕНЕФІЦІАРА (org), не мертвий wallet-pending.
      it "mints a custodial wallet (no own address) when its ORGANIZATION is KYC-approved" do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update_column(:crypto_public_address, nil)
        wallet.organization.update!(hadron_kyc_status: "approved")

        tx = wallet.blockchain_transactions.create!(
          amount: 100, token_type: :carbon_coin, status: :pending,
          to_address: wallet.organization.crypto_public_address, locked_points: 1000
        )

        expect { described_class.call_batch([ tx.id ]) }.not_to raise_error
        expect(tx.reload.status).to eq("sent")
      end

      it "skips a custodial wallet while its organization is still pending" do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update_column(:crypto_public_address, nil)
        wallet.organization.update!(hadron_kyc_status: "pending")

        tx = wallet.blockchain_transactions.create!(
          amount: 100, token_type: :carbon_coin, status: :pending,
          to_address: wallet.organization.crypto_public_address, locked_points: 1000
        )

        expect { described_class.call_batch([ tx.id ]) }.not_to raise_error
        expect(mock_client).not_to have_received(:transact)
        expect(tx.reload.status).to eq("pending")
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
    it "marks transactions as failed on a pre-broadcast blockchain error (revert)" do
      allow(mock_client).to receive(:transact).and_raise(StandardError, "execution reverted: gas")

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

      expect { described_class.call(tx.id) }.to raise_error(StandardError, /execution reverted/)

      tx.reload
      expect(tx.status).to eq("failed")
    end

    # [P0-1] Ambiguous broadcast error on the PRIMARY path (dry-run passes → transact) must escalate
    # to manual_review, NOT fail! (which now releases locked_points via M2 → double-mint if the tx
    # actually landed). The hot path had a bare fail! before this fix.
    it "escalates to manual_review on an ambiguous broadcast error (no fail!+release → no double-mint)" do
      allow(mock_client).to receive(:transact).and_raise(Net::ReadTimeout, "connection reset after broadcast")

      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved", balance: 1000, locked_balance: 1000)

      tx = wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )

      expect { described_class.call(tx.id) }.not_to raise_error  # ambiguous → no retry
      expect(tx.reload.status).to eq("manual_review")            # NOT failed
      expect(wallet.reload.locked_balance).to eq(1000)           # locked NOT released (no double-mint)
    end

    # [P0-1] A crash AFTER mark_as_sent! (tx already :sent = broadcast landed) → escalate, never
    # fail! (the tokens are on-chain; fail!+release would set up a re-mint).
    it "escalates an already-:sent tx to manual_review on a post-broadcast finalize crash" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved", balance: 1000, locked_balance: 1000)
      tx = wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )
      allow(mock_client).to receive(:transact).and_return(fake_tx_hash) # mint lands
      # Шов ін'єкції краху = перший виклик ПІСЛЯ `mark_as_sent!` у `finalize_sent_transaction`,
      # тобто в момент, коли tx уже `:sent`. Метрика для цього надійніша за лічильник
      # викликів: вона стоїть буквально наступним рядком і в застосунку єдина, тож
      # «другий виклик» неможливо зсунути рефактором сусіднього коду.
      # (Раніше шов сидів на `broadcast_tx_update` — його знято як надлишковий, UI.4.)
      allow(SilkenNet::Metrics::SCC_MINTED_TOTAL).to receive(:increment).and_raise(StandardError, "post-send crash")

      expect { described_class.call(tx.id) }.not_to raise_error
      expect(tx.reload.status).to eq("manual_review")   # :sent → escalate (not fail!)
      expect(wallet.reload.locked_balance).to eq(1000)  # NOT released
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

      expect(BlockchainConfirmationWorker).to have_received(:perform_in).with(30.seconds, fake_tx_hash, kind_of(String)) # [ARCH.52] +created_at
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
    # [S2 FIX] non-approved → per-tx SKIP (не raise). Захисний інваріант «не мінтимо non-approved»
    # збережено (transact не викликається, tx лишається :pending), але без abort всього батчу.
    it "skips (does not mint) when wallet is not Hadron KYC approved" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "pending")

      tx = wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )

      expect { described_class.call(tx.id) }.not_to raise_error
      expect(mock_client).not_to have_received(:transact)
      expect(tx.reload.status).to eq("pending")
    end

    it "skips (does not mint) when wallet KYC status is rejected" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "rejected")

      tx = wallet.blockchain_transactions.create!(
        amount: 100, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 1000
      )

      expect { described_class.call(tx.id) }.not_to raise_error
      expect(mock_client).not_to have_received(:transact)
      expect(tx.reload.status).to eq("pending")
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
    # 🔴 [DOC-T.89, ⚖️ 2026-08-26] Приклад ПЕРЕВЕРНУТО, і це не «фікс тесту»: доти він
    # доводив, що SFC мінтиться правильним контрактом. Присуд заблокував SFC-мінт до
    # активації governance (SEC.1) — quorum Governor'а рахується від `totalSupply` при
    # нульовому genesis-supply, тож перші 10k SFC дають своєму власникові 100% голосів,
    # а єдиний живий writer сьогодні — страхова виплата (голоси ЗА ЗБИТОК, без зняття).
    # Тепер приклад стереже сам гард; контракт-резолв нижче по методу недосяжний.
    it "НЕ мінтить forest_coin до активації governance — tx лишається :pending" do
      ENV["FOREST_COIN_CONTRACT_ADDRESS"] = "0x" + "1" * 40

      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      tx = wallet.blockchain_transactions.create!(
        amount: 50, token_type: :forest_coin, status: :pending,
        to_address: wallet.crypto_public_address, locked_points: 500
      )

      described_class.call(tx.id)

      expect(mock_client).not_to have_received(:transact)
      expect(tx.reload.status).to eq("pending")
    end
  end

  # 🔴 [DOC-T.89, ⚖️ 2026-08-26] Страхова емісія мусить бути ВІДРІЗНЕННОЮ on-chain.
  # Доти `identifier_for` віддавав той самий tree-DID і за верифікований ріст, і за
  # страховий випадок, а subgraph зберігає поле як є й додає суму до `totalMinted`
  # без гілкування — тобто аудитор не відділяв «намінтили за вимір» від «намінтили
  # за збиток», а MRV-lineage payout-мінта вів до вимірів, яких не було.
  describe "attribution of insurance-sourced mints [DOC-T.89]" do
    it "префіксує ідентифікатор страхового мінту, лишаючи звичайний недоторканим" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
      insurance = create(:parametric_insurance, organization: wallet.organization, cluster: tree.cluster)

      growth_tx = wallet.blockchain_transactions.create!(
        amount: 10, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address
      )
      payout_tx = wallet.blockchain_transactions.create!(
        amount: 10, token_type: :carbon_coin, status: :pending,
        to_address: wallet.crypto_public_address, sourceable: insurance
      )

      service = described_class.new(growth_tx.id)
      expect(service.send(:identifier_for, growth_tx)).to eq(tree.did)
      expect(service.send(:identifier_for, payout_tx)).to eq("INS_#{tree.did}")
    end

    # ⚠️ Гілка `ORG_…` досяжна НЕ через гаманець без дерева (`Wallet belongs_to :tree`
    # без `optional`, тож такого не буває), а через транзакцію без ГАМАНЦЯ — це
    # cluster-sourced гроші [ARCH.98]. Пін тримає саме цей шлях, інакше гілка
    # читалася б як мертва й перший рефактор зняв би її.
    it "падає на org-форму для транзакції без гаманця (cluster-sourced)" do
      tree = create(:tree)
      tx = BlockchainTransaction.create!(
        wallet: nil, cluster_id: tree.cluster_id, amount: 1,
        token_type: :carbon_coin, status: :pending, to_address: "0x" + "e" * 40
      )

      service = described_class.new(tx.id)
      expect(service.send(:identifier_for, tx)).to eq("ORG_")
    end

    # [DOC-T.89] Цей приклад пінить інкремент у `dispatch_archive_group` — звичайний
    # батч-шлях. Близнюк у `send_clean_batch` має власний пін (binary-search context
    # нижче): один коментар над одним прикладом не свідчить про два різні тракти.
    # ⛔ Гілка резолву SFC-контракту лишається недосяжною за гардом і НЕ пінена свідомо:
    # `04_06 §B.4` велить financial-safety-defensive лишати з поясненням, а не оживляти
    # `send`-піном заради відсотка (§A.4 BP 16-17); її надгробок стоїть у самому сервісі.
    # 🔴 А от `tax_rate: nil` більше НЕ в тому переліку: [DOC-T.89] звів умову на One-Home
    # `taxing?`, тож гілка стала ДОСЯЖНОЮ. Пін на НЕЇ живе не тут, а в `archive-batch root
    # wiring [E.60]` — тільки там `windowed_tx!` створює РЯДОК батчу; спроба пінити її
    # звідси дала вакуумний зелений (windowless-диспатч не створює рядка, тож
    # `TelemetryArchiveBatch.last` = nil в обох світах, і мутація це показала).
    it "не інкрементує лічильник податку, коли пул не потребує поповнення" do
      allow_any_instance_of(described_class).to receive(:insurance_pool_requires_funding?).and_return(false)
      allow(mock_client).to receive(:transact).and_return(fake_tx_hash)
      tree_a = create(:tree)
      tree_b = create(:tree)
      [ tree_a, tree_b ].each do |t|
        t.wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
      end
      txs = [ tree_a, tree_b ].map do |t|
        t.wallet.blockchain_transactions.create!(
          amount: 10, token_type: :carbon_coin, status: :pending,
          to_address: t.wallet.crypto_public_address
        )
      end

      expect { described_class.call_batch(txs.map(&:id)) }
        .not_to(change { SilkenNet::Metrics::TAX_COLLECTED_TOTAL.get(labels: { token_type: "carbon_coin" }) })
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
      # [O2/O4 FIX] N forester + ONE aggregated treasury entry = N+1 (не 2N) — headroom під
      # on-chain MAX_BATCH_SIZE=100.
      it "aggregates tax into a single DAO Treasury entry (N+1, not 2N)" do
        allow(mock_client).to receive(:transact) do |_c, _m, recipients, amounts, identifiers, **_|
          expect(recipients.size).to eq(3)  # 2 forester + 1 aggregated treasury
          expect(amounts.size).to eq(3)
          expect(identifiers.size).to eq(3)
          fake_tx_hash
        end

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(mock_client).to have_received(:transact)
      end

      it "routes the single aggregated tax entry to DAO_TREASURY_ADDRESS (sum of all txs)" do
        dao_treasury = ENV.fetch("DAO_TREASURY_ADDRESS")
        # tax_total = 100*0.02 + 200*0.02 = 6 SCC → to_wei(6)
        expected_tax_wei = Web3::WeiConverter.to_wei(6)

        allow(mock_client).to receive(:transact) do |_c, _m, recipients, amounts, identifiers, **_|
          expect(recipients.last).to eq(dao_treasury)
          expect(recipients[0...-1]).not_to include(dao_treasury)  # foresters only before the tax entry
          expect(amounts.last).to eq(expected_tax_wei)
          expect(identifiers.last).to start_with("TAX_BATCH_")
          fake_tx_hash
        end

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(mock_client).to have_received(:transact)
      end
    end

    context "with batch forest_coin transactions" do
      before do
        tx1.update_column(:token_type, "forest_coin")
        tx2.update_column(:token_type, "forest_coin")
      end

      # ⚠️ [DOC-T.89] Твердження «SFC не оподатковується» лишається ІСТИННИМ, але доводити
      # його батч-формою більше не можна: SFC не доходить до `build_batch_arrays` взагалі —
      # гард активації governance відсікає раніше. Приклад переорієнтовано на те, що
      # реально спостережне сьогодні, інакше він був би зеленим із ДВОХ причин одразу
      # (не оподатковано ⊥ не відправлено) — тобто вакуумним.
      it "не доходить до податкової гілки — SFC відсічено гардом раніше" do
        allow(mock_client).to receive(:transact).and_return(fake_tx_hash)

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(mock_client).not_to have_received(:transact)
        expect([ tx1.reload.status, tx2.reload.status ]).to all(eq("pending"))
      end
    end

    context "when insurance pool does not require funding" do
      before do
        allow_any_instance_of(described_class).to receive(:insurance_pool_requires_funding?).and_return(false)
      end

      it "does not apply tax split for carbon_coin" do
        allow(mock_client).to receive(:transact) do |_c, _m, recipients, amounts, _identifiers, **_|
          expect(recipients.size).to eq(2)
          expect(amounts.size).to eq(2)
          fake_tx_hash
        end

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(mock_client).to have_received(:transact)
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
        allow(Rails.logger).to receive(:error).with(/DAO Treasury balance check failed/)
        service.send(:insurance_pool_requires_funding?)
        expect(Rails.logger).to have_received(:error).with(/DAO Treasury balance check failed/)
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
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything, anything).and_return(nil)
      end

      it "proceeds with batch mint via transact" do
        allow(mock_client).to receive(:transact).with(anything, "batchMint", anything, anything, anything, anything, anything).and_return(fake_tx_hash)

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(tx1.reload.status).to eq("sent")
        expect(tx2.reload.status).to eq("sent")
        expect(tx1.reload.tx_hash).to eq(fake_tx_hash)
      end
    end

    context "when dry-run detects EVM revert" do
      before do
        # eth_call (dry-run) fails with revert → fallback to individual mints
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything, anything)
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
        # tx1 succeeds individually, tx2 reverts (execution reverted = pre-broadcast, safe fail)
        allow(mock_client).to receive(:transact) do |_c, _method, to_address, *_args, **_opts|
          if to_address == wallet2.crypto_public_address
            raise StandardError, "execution reverted: KYC revoked for this wallet"
          end
          "0x" + "a" * 64
        end

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(tx1.reload.status).to eq("sent")
        expect(tx2.reload.status).to eq("failed")
        expect(tx2.reload.error_message).to include("KYC revoked")
      end

      # [M6] Individual mint on an AMBIGUOUS network error (may have landed) → manual_review,
      # NOT a blind fail! (which would release locked_points while tokens sit on-chain → double).
      it "escalates the individual mint to manual_review on an ambiguous broadcast error" do
        allow(mock_client).to receive(:transact) do |_c, _method, to_address, *_args, **_opts|
          raise Net::ReadTimeout, "RPC timeout after broadcast" if to_address == wallet2.crypto_public_address
          "0x" + "a" * 64
        end

        described_class.call_batch([ tx1.id, tx2.id ])

        expect(tx1.reload.status).to eq("sent")
        expect(tx2.reload.status).to eq("manual_review")
      end

      # [M6] else-branch: an already-:manual_review tx has no valid escalate transition
      # (may_escalate_to_review? false) → the ambiguous handler is a no-op, not a crash.
      it "does not re-escalate an already-:manual_review tx on ambiguous individual mint" do
        wallet1.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
        tx = wallet1.blockchain_transactions.create!(
          amount: 100, token_type: :carbon_coin, status: :manual_review,
          to_address: wallet1.crypto_public_address, tx_hash: "0x" + "e" * 64, locked_points: 1000
        )
        service = described_class.new([ tx.id ])
        allow(mock_client).to receive(:transact).and_raise(Net::ReadTimeout, "timeout")

        expect {
          service.send(:mint_individual, mock_client, instance_double(Eth::Contract), mock_key, "carbon_coin", tx, "0x" + "0" * 64)
        }.not_to raise_error
        expect(tx.reload.status).to eq("manual_review")
      end

      it "does not re-escalate already-:manual_review txs on ambiguous batchMint (send_clean_batch else)" do
        wallet1.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
        wallet2.update!(crypto_public_address: "0x" + "c" * 40, hadron_kyc_status: "approved")
        txs = [ wallet1, wallet2 ].map do |w|
          w.blockchain_transactions.create!(
            amount: 100, token_type: :carbon_coin, status: :manual_review,
            to_address: w.crypto_public_address, tx_hash: "0x" + "f" * 64, locked_points: 1000
          )
        end
        service = described_class.new(txs.map(&:id))
        allow_any_instance_of(described_class).to receive(:insurance_pool_requires_funding?).and_return(false)
        allow(mock_client).to receive(:transact).and_raise(Net::ReadTimeout, "timeout")

        expect {
          service.send(:send_clean_batch, mock_client, instance_double(Eth::Contract), mock_key, "carbon_coin", txs, "0x" + "0" * 64)
        }.not_to raise_error
        txs.each { |t| expect(t.reload.status).to eq("manual_review") }
      end
    end

    context "when dry-run fails with network error (not revert)" do
      before do
        # eth_call fails with timeout → NOT a revert, proceed optimistically
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything, anything)
          .and_raise(Net::ReadTimeout, "RPC timeout")
        # balanceOf call for insurance pool
        allow(mock_client).to receive(:call).with(anything, "balanceOf", anything).and_return(0)
      end

      it "proceeds with batch mint optimistically (network error is not a revert)" do
        allow(mock_client).to receive(:transact).with(anything, "batchMint", anything, anything, anything, anything, anything).and_return(fake_tx_hash)

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
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything, anything) do |_c, _m, recipients, *_args|
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
          # Individual mint for poisoned address reverts (execution reverted = pre-broadcast)
          if to_address_or_recipients == poisoned_address
            raise StandardError, "execution reverted: KYC revoked for this wallet"
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
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything, anything)
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

    # [DOC-T.89] Інкрементів `TAX_COLLECTED_TOTAL` у сервісі ДВА: у `dispatch_archive_group`
    # (звичайний батч) і близнюк у `send_clean_batch` — той досяжний ЛИШЕ через
    # binary-search, тож пін звичайного шляху про нього не свідчить нічого. Глобальний
    # `before` (:30) стабить `balanceOf → 0`, тобто вся сюїта живе з ПОРОЖНІМ пулом і
    # вправляє лише гілку «податок є». Тут — дзеркальна: пул повний, податку немає.
    context "when the insurance pool needs no funding" do
      before do
        first_call = true
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything, anything) do |*_args|
          if first_call
            first_call = false
            raise StandardError, "execution reverted: KYC not approved"
          end
          nil # sub-batch dry-runs succeed → чистий sub-batch іде в send_clean_batch
        end
        allow_any_instance_of(described_class).to receive(:insurance_pool_requires_funding?).and_return(false)
      end

      it "не інкрементує лічильник податку на чистому sub-batch" do
        allow(mock_client).to receive(:transact).and_return(fake_tx_hash)

        expect { described_class.call_batch(transactions.map(&:id)) }
          .not_to(change { SilkenNet::Metrics::TAX_COLLECTED_TOTAL.get(labels: { token_type: "carbon_coin" }) })

        expect(transactions.map { |tx| tx.reload.status }).to all(eq("sent"))
      end
    end

    context "when clean sub-batch batchMint transact fails" do
      before do
        # First dry-run (full batch) reverts
        first_call = true
        allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything, anything) do |*_args|
          if first_call
            first_call = false
            raise StandardError, "execution reverted: KYC not approved"
          end
          nil # sub-batch dry-runs succeed
        end
        allow(mock_client).to receive(:call).with(anything, "balanceOf", anything).and_return(0)
      end

      it "falls back to individual mints for the sub-batch if batchMint transact fails (pre-broadcast)" do
        transact_count = 0
        allow(mock_client).to receive(:transact) do |_c, method, *_args, **_opts|
          transact_count += 1
          if method == "batchMint"
            raise StandardError, "execution reverted: gas" # pre-broadcast: tx did NOT land → safe re-mint
          end
          "0x" + "f" * 64 # individual mints succeed
        end

        described_class.call_batch(transactions.map(&:id))

        # All txs should still eventually be sent (via individual mint fallback)
        transactions.each do |tx|
          expect(tx.reload.status).to eq("sent")
        end
      end

      # [P2-4] `nonce too low` is NOT pre-broadcast (our prior tx may have landed) → ambiguous →
      # escalate, NOT a blind individual re-mint (which would double-mint).
      it "escalates the sub-batch to manual_review on a nonce-too-low batchMint error" do
        individual_calls = 0
        allow(mock_client).to receive(:transact) do |_c, method, *_args, **_opts|
          raise StandardError, "nonce too low" if method == "batchMint"
          individual_calls += 1
          "0x" + "f" * 64
        end

        described_class.call_batch(transactions.map(&:id))

        expect(individual_calls).to eq(0)
        transactions.each { |tx| expect(tx.reload.status).to eq("manual_review") }
      end

      # [M6] Ambiguous batchMint broadcast (may have landed) → escalate the whole sub-batch to
      # manual_review, NOT a blind individual re-mint (which would double-mint if it landed).
      it "escalates the sub-batch to manual_review on an ambiguous batchMint broadcast" do
        individual_calls = 0
        allow(mock_client).to receive(:transact) do |_c, method, *_args, **_opts|
          if method == "batchMint"
            raise Net::ReadTimeout, "RPC timeout after broadcast" # ambiguous: may have landed
          end
          individual_calls += 1
          "0x" + "f" * 64
        end

        described_class.call_batch(transactions.map(&:id))

        expect(individual_calls).to eq(0) # NO blind individual re-mints
        transactions.each do |tx|
          expect(tx.reload.status).to eq("manual_review")
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
      # [S2 FIX] non-approved → SKIP (не raise); tx лишається :pending, transact не викликається.
      it "blocks minting (skip) with KYC pending in oracle-driven flow" do
        wallet.update!(hadron_kyc_status: "pending")
        log = create(:telemetry_log, :verified_telemetry, tree: tree)

        expect { described_class.call(tx.id, telemetry_log: log) }.not_to raise_error
        expect(mock_client).not_to have_received(:transact)
        expect(tx.reload.status).to eq("pending")
      end

      it "blocks minting (skip) with KYC pending in batch emission flow" do
        wallet.update!(hadron_kyc_status: "pending")

        expect { described_class.call(tx.id) }.not_to raise_error
        expect(mock_client).not_to have_received(:transact)
        expect(tx.reload.status).to eq("pending")
      end

      it "blocks minting (skip) with KYC rejected in oracle-driven flow" do
        wallet.update!(hadron_kyc_status: "rejected")
        log = create(:telemetry_log, :verified_telemetry, tree: tree)

        expect { described_class.call(tx.id, telemetry_log: log) }.not_to raise_error
        expect(mock_client).not_to have_received(:transact)
        expect(tx.reload.status).to eq("pending")
      end

      it "blocks minting (skip) with KYC rejected in batch emission flow" do
        wallet.update!(hadron_kyc_status: "rejected")

        expect { described_class.call(tx.id) }.not_to raise_error
        expect(mock_client).not_to have_received(:transact)
        expect(tx.reload.status).to eq("pending")
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

      it "does not increment SCC_MINTED_TOTAL when Hadron KYC skips minting" do
        wallet.update!(hadron_kyc_status: "pending")
        metric = SilkenNet::Metrics::SCC_MINTED_TOTAL
        before_val = metric.get(labels: { token_type: "carbon_coin" })

        expect { described_class.call(tx.id) }.not_to raise_error

        expect(metric.get(labels: { token_type: "carbon_coin" })).to eq(before_val)
      end

      it "increments SCC_MINTED_TOTAL only after successful minting" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree)
        metric = SilkenNet::Metrics::SCC_MINTED_TOTAL
        before_val = metric.get(labels: { token_type: "carbon_coin" })

        described_class.call(tx.id, telemetry_log: log)

        expect(metric.get(labels: { token_type: "carbon_coin" })).to be > before_val
      end

      # 🔴 [INF.26] Приклад вище стереже УМОВУ («лише після успіху») і на осі ОДИНИЦІ
      # сліпий за побудовою: `be > before_val` зелений і при голому `.increment`, тобто
      # при лічбі ТРАНЗАКЦІЙ під іменем «tokens minted». Вирішив питання не докстрінг, а
      # споживач — обидві серії стоять на одній панелі «SCC Minted vs Slashed», і сусідня
      # вже інкрементиться `by: effective_burn`.
      it "increments SCC_MINTED_TOTAL by the AMOUNT, not by one (unit of count)" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree)
        metric = SilkenNet::Metrics::SCC_MINTED_TOTAL
        before_val = metric.get(labels: { token_type: "carbon_coin" })

        described_class.call(tx.id, telemetry_log: log)

        expect(metric.get(labels: { token_type: "carbon_coin" }) - before_val).to eq(tx.amount)
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

      # [ARCH.106] Пін на КОНСТАНТУ, не на літерал: доти тут стояло `120.seconds`,
      # тобто спека цементувала число, МЕНШЕ за задокументований worst case
      # (~130 с) — і тому мовчки підтверджувала авто-реліз локу під час легального
      # проходу. ⚠️ Пін на саму константу не довів би нічого про її ВЕЛИЧИНУ, тож
      # поруч стоїть окремий приклад, який порівнює її з worst case.
      allow(Kredis).to receive(:lock).with(
        anything,
        expires_in: described_class::MINT_LOCK_TTL,
        after_timeout: :raise
      ).and_yield

      described_class.call(tx.id)

      expect(Kredis).to have_received(:lock).with(
        anything,
        expires_in: described_class::MINT_LOCK_TTL,
        after_timeout: :raise
      )
    end

    # [ARCH.106] Величина, а не лише ідентичність. Лок є авто-релізним, тож TTL,
    # МЕНШИЙ за найдовший легальний прохід, відпускає підписанта, поки холдер ще
    # працює — і повертає рівно той double-mint, заради якого його підіймали з
    # 30 с. Worst case задокументовано на місці виклику: dry-run (~5 с) +
    # binary-search до 6 рівнів × 2 eth_call (~36 с) + fallback individual mints
    # (~90 с) ≈ 130 с.
    it "holds the signer lock LONGER than the documented worst-case batch (~130s)" do
      documented_worst_case = 130.seconds
      expect(described_class::MINT_LOCK_TTL).to be > documented_worst_case
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
      allow(mock_client).to receive(:transact).and_raise(StandardError, "execution reverted: slow")

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

      expect { described_class.call(tx.id) }.to raise_error(StandardError, /execution reverted/)
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

    it "skips (does not mint) a tx with a nil wallet without aborting the batch" do
      # [S2 FIX] missing wallet → per-tx skip (не raise); transact не викликається.
      allow_any_instance_of(BlockchainTransaction).to receive(:wallet).and_return(nil)
      expect { described_class.call(tx.id) }.not_to raise_error
      expect(mock_client).not_to have_received(:transact)
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

      expect { described_class.call(tx.id) }.not_to raise_error

      expect(mock_client).not_to have_received(:transact)
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
      allow(service).to receive(:mint_individual)
        .with(mock_client, mock_contract, mock_key, "carbon_coin", tx, "0x" + "0" * 64)

      service.send(:send_clean_batch, mock_client, mock_contract, mock_key, "carbon_coin", [ tx ], "0x" + "0" * 64)

      expect(service).to have_received(:mint_individual)
        .with(mock_client, mock_contract, mock_key, "carbon_coin", tx, "0x" + "0" * 64).once
      expect(mock_client).not_to have_received(:transact)
    end

    it "is a no-op for an empty txs array (defensive recursion guard)" do
      expect { service.send(:send_clean_batch, mock_client, mock_contract, mock_key, "carbon_coin", [], "0x" + "0" * 64) }
        .not_to raise_error
      expect(mock_client).not_to have_received(:transact)
    end
  end

  describe "process_half — empty half guard" do
    # binary search splits an odd-sized array → one half can land empty
    # at recursive boundaries; process_half must short-circuit.
    let(:service) { described_class.new([ -1 ]) }

    it "returns immediately when half_txs is empty" do
      allow(service).to receive(:batch_dry_run_reverts?)
      service.send(:process_half, mock_client, mock_contract, mock_key, "carbon_coin", [],
                   [], [], "0x" + "0" * 64, depth: 0, original_batch_size: 6)
      expect(service).not_to have_received(:batch_dry_run_reverts?)
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
      allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything, anything)
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

  # [E.60 Фаза 1б] Per-archive_batch transact-цикл: один on-chain виклик = один root.
  describe "archive-batch root wiring [E.60]" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    def windowed_tx!(tree, address_nibble)
      wallet = tree.wallet
      wallet.update!(balance: 5000, crypto_public_address: "0x" + address_nibble * 40,
                     hadron_kyc_status: "approved")
      allow_any_instance_of(Tree).to receive(:active?).and_return(true)
      create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      wallet.reload.lock_and_mint!(500, 100)
    end

    # [DOC-T.89] Пара на `tax_rate_applied` архів-рядка. Пінити її можна ЛИШЕ тут: у
    # решті спеки диспатч windowless, а windowless свідомо НЕ створює рядка (ZERO_ROOT
    # derived-only), тож будь-який `TelemetryArchiveBatch.last&.…` там зелений в обох
    # світах. ⚠️ Обидві половини несучі: без НЕГАТИВНОЇ повертається сам дефект (поле
    # стверджує ставку, якої не стягували), без ПОЗИТИВНОЇ пін не відрізняє «правильно
    # nil» від «завжди nil» — тобто від зламаного `taxing?`, який просто не таксує.
    it "артефакт НЕ стверджує ставку, коли пул повний (tax_rate_applied = nil)" do
      allow_any_instance_of(described_class).to receive(:insurance_pool_requires_funding?).and_return(false)
      allow(mock_client).to receive(:transact).and_return(fake_tx_hash)
      tx = windowed_tx!(create(:tree, cluster: cluster), "7")

      described_class.call_batch([ tx.id ])

      batch = tx.reload.archive_batch
      expect(batch).to be_present, "фікстура не створила архів-рядка — пін був би вакуумним"
      expect(batch.tax_rate_applied).to be_nil
    end

    it "артефакт НЕСЕ ставку, коли пул потребує поповнення" do
      allow_any_instance_of(described_class).to receive(:insurance_pool_requires_funding?).and_return(true)
      allow(mock_client).to receive(:transact).and_return(fake_tx_hash)
      tx = windowed_tx!(create(:tree, cluster: cluster), "8")

      described_class.call_batch([ tx.id ])

      batch = tx.reload.archive_batch
      expect(batch).to be_present
      expect(batch.tax_rate_applied).to eq(BlockchainMintingService::DEFAULT_DYNAMIC_TAX_RATE)
    end

    it "одиночний windowed-мінт несе root свого батчу (≡ telemetry_merkle_root)" do
      tx = windowed_tx!(create(:tree, cluster: cluster), "b")
      calls = []
      allow(mock_client).to receive(:transact) do |_c, method, *args, **_o|
        calls << [ method, args.last ]
        fake_tx_hash
      end

      described_class.call_batch([ tx.id ])

      expect(calls).to eq([ [ "mint", "0x#{tx.reload.telemetry_merkle_root}" ] ])
      expect(tx.archive_batch_id).to be_present
    end

    it "windowless-мінт несе zero32 і НЕ створює batch-row" do
      tree = create(:tree, cluster: cluster)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "c" * 40, hadron_kyc_status: "approved")
      tx = wallet.blockchain_transactions.create!(
        amount: 10, token_type: :carbon_coin, status: :pending, to_address: "0x" + "c" * 40
      )
      roots = []
      allow(mock_client).to receive(:transact) do |_c, _m, *args, **_o|
        roots << args.last
        fake_tx_hash
      end

      expect { described_class.call_batch([ tx.id ]) }.not_to change(TelemetryArchiveBatch, :count)
      expect(roots).to eq([ "0x" + "0" * 64 ])
      expect(tx.reload.archive_batch_id).to be_nil
    end

    it "mixed-archive_batch слайс → окремий batchMint з root'ом КОЖНІЙ підгрупі (re-dispatch)" do
      txs_b1 = [ windowed_tx!(create(:tree, cluster: cluster), "1"),
                 windowed_tx!(create(:tree, cluster: cluster), "2") ]
      txs_b2 = [ windowed_tx!(create(:tree, cluster: cluster), "3"),
                 windowed_tx!(create(:tree, cluster: cluster), "4") ]
      b1 = Mrv::TelemetryArchiveBatchService.group(txs_b1, token_type: "carbon_coin").first.batch
      b2 = Mrv::TelemetryArchiveBatchService.group(txs_b2, token_type: "carbon_coin").first.batch
      expect(b1.id).not_to eq(b2.id)

      batch_calls = []
      allow(mock_client).to receive(:transact) do |_c, method, *args, **_o|
        batch_calls << [ method, args.last ]
        fake_tx_hash
      end

      described_class.call_batch((txs_b1 + txs_b2).map(&:id))

      expect(batch_calls).to contain_exactly(
        [ "batchMint", "0x#{b1.archive_root}" ],
        [ "batchMint", "0x#{b2.archive_root}" ]
      )
      (txs_b1 + txs_b2).each { |tx| expect(tx.reload.status).to eq("sent") }
    end

    # Rescue живе ПЕР-ПІДГРУПОЮ: збій пізньої групи не чіпає
    # здорову вже-sent ранню (старий group-wide rescue тягнув її в manual_review,
    # а retry сліпо ре-мінтив = double-mint).
    it "ambiguous-збій пізньої підгрупи НЕ ескалює здорову :sent ранню" do
      txs_b1 = [ windowed_tx!(create(:tree, cluster: cluster), "1"),
                 windowed_tx!(create(:tree, cluster: cluster), "2") ]
      txs_b2 = [ windowed_tx!(create(:tree, cluster: cluster), "3"),
                 windowed_tx!(create(:tree, cluster: cluster), "4") ]
      Mrv::TelemetryArchiveBatchService.group(txs_b1, token_type: "carbon_coin")
      b2 = Mrv::TelemetryArchiveBatchService.group(txs_b2, token_type: "carbon_coin").first.batch

      # Валимо САМЕ підгрупу b2 (по root-аргументу — порядок диспатчу груп
      # недетермінований, лічильник викликів флейкав).
      allow(mock_client).to receive(:transact) do |_c, _m, *args, **_o|
        raise Net::ReadTimeout, "RPC timeout після можливого broadcast" if args.last == "0x#{b2.archive_root}"
        fake_tx_hash
      end

      expect {
        described_class.call_batch((txs_b1 + txs_b2).map(&:id))
      }.not_to raise_error # ambiguous → escalate БЕЗ retry

      txs_b1.each { |tx| expect(tx.reload.status).to eq("sent") }
      txs_b2.each { |tx| expect(tx.reload.status).to eq("manual_review") }
    end

    it "retry після часткової відмови СКІПАЄ sent/manual_review tx підгрупи (double-mint guard)" do
      txs = [ windowed_tx!(create(:tree, cluster: cluster), "5"),
              windowed_tx!(create(:tree, cluster: cluster), "6") ]
      batch = Mrv::TelemetryArchiveBatchService.group(txs, token_type: "carbon_coin").first.batch
      txs.first.update!(status: :sent, tx_hash: "0x" + "e" * 64)

      calls = []
      allow(mock_client).to receive(:transact) do |_c, method, *args, **_o|
        calls << [ method, args.last ]
        fake_tx_hash
      end

      described_class.call_batch(txs.map(&:id))

      expect(calls).to eq([ [ "mint", "0x#{batch.archive_root}" ] ])
      expect(txs.first.reload.status).to eq("sent")
      expect(txs.last.reload.status).to eq("sent")
    end

    it "ambiguous-збій підгрупи з уже-:manual_review сусідом — без ре-ескалації і без краху" do
      txs = [ windowed_tx!(create(:tree, cluster: cluster), "b"),
              windowed_tx!(create(:tree, cluster: cluster), "c") ]
      Mrv::TelemetryArchiveBatchService.group(txs, token_type: "carbon_coin")
      # Перший tx уже в manual_review (минула ескалація) — фільтр його скіпне,
      # а ambiguous-rescue другого НЕ повинен ре-ескалювати чи впасти.
      txs.first.update!(status: :manual_review, tx_hash: "0x" + "9" * 64)
      allow(mock_client).to receive(:transact).and_raise(Net::ReadTimeout, "після можливого broadcast")

      expect { described_class.call_batch(txs.map(&:id)) }.not_to raise_error

      expect(txs.first.reload.status).to eq("manual_review")
      expect(txs.last.reload.status).to eq("manual_review")
    end

    it "повністю sent-група → повний skip, нуль transact" do
      txs = [ windowed_tx!(create(:tree, cluster: cluster), "d"),
              windowed_tx!(create(:tree, cluster: cluster), "e") ]
      Mrv::TelemetryArchiveBatchService.group(txs, token_type: "carbon_coin")
      txs.each { |tx| tx.update!(status: :sent, tx_hash: "0x" + "8" * 64) }

      described_class.call_batch(txs.map(&:id))
      expect(mock_client).not_to have_received(:transact)
      txs.each { |tx| expect(tx.reload.status).to eq("sent") }
    end

    it "LockTimeout НЕ клоберить stale-:sent конкурентного джоба (reload-guard)" do
      txs = [ windowed_tx!(create(:tree, cluster: cluster), "9"),
              windowed_tx!(create(:tree, cluster: cluster), "a") ]
      Mrv::TelemetryArchiveBatchService.group(txs, token_type: "carbon_coin")
      # Конкурент устиг змінтити першу, поки ЦЕЙ джоб чекав лок (in-memory stale).
      BlockchainTransaction.where(id: txs.first.id, created_at: txs.first.created_at)
                           .update_all(status: BlockchainTransaction.statuses[:sent] || "sent",
                                       tx_hash: "0x" + "d" * 64, sent_at: Time.current)
      allow(Kredis).to receive(:lock).and_raise(Kredis::LockTimeout)

      expect { described_class.call_batch(txs.map(&:id)) }.to raise_error(Kredis::LockTimeout)

      expect(txs.first.reload.status).to eq("sent")   # НЕ клобернуто у failed
      expect(txs.last.reload.status).to eq("failed")  # чистий pending → safe fail!
    end

    # Bisect-гілки несуть РЕАЛЬНИЙ root підгрупи (N:1) — не zero32.
    it "bisect/individual-fallback несе root свого батчу" do
      txs = [ windowed_tx!(create(:tree, cluster: cluster), "7"),
              windowed_tx!(create(:tree, cluster: cluster), "8") ]
      batch = Mrv::TelemetryArchiveBatchService.group(txs, token_type: "carbon_coin").first.batch
      allow(mock_client).to receive(:call).with(anything, "batchMint", anything, anything, anything, anything, anything)
        .and_raise(StandardError, "execution reverted: poisoned")
      allow(mock_client).to receive(:call).with(anything, "balanceOf", anything).and_return(0)

      roots = []
      allow(mock_client).to receive(:transact) do |_c, method, *args, **_o|
        expect(method).to eq("mint")
        roots << args.last
        fake_tx_hash
      end

      described_class.call_batch(txs.map(&:id))

      expect(roots).to eq([ "0x#{batch.archive_root}" ] * 2)
      expect(batch.archive_root).not_to eq("0" * 64)
      txs.each { |tx| expect(tx.reload.status).to eq("sent") }
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
