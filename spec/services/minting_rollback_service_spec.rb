# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MintingRollbackService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) { tree.wallet }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe ".call with telemetry_log_id (oracle-driven flow)" do
    let!(:telemetry_log) { create(:telemetry_log, :verified_telemetry, tree: tree) }

    it "releases locked points on permanent failure" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000, tx_hash: nil)

      described_class.call(
        telemetry_log_id: telemetry_log.id_value,
        created_at_iso: telemetry_log.created_at.iso8601(6)
      )

      tx.reload
      wallet.reload
      expect(tx.status).to eq("failed")
      expect(tx.notes).to include("Rollback")
      expect(wallet.locked_balance).to eq(0)
    end

    it "skips transactions that are already confirmed" do
      tx = create(:blockchain_transaction, wallet: wallet, status: :confirmed, tx_hash: "0x#{SecureRandom.hex(32)}")
      original_balance = wallet.balance
      original_locked = wallet.locked_balance

      described_class.call(
        telemetry_log_id: telemetry_log.id_value,
        created_at_iso: telemetry_log.created_at.iso8601(6)
      )

      wallet.reload
      expect(wallet.balance).to eq(original_balance)
      expect(wallet.locked_balance).to eq(original_locked)
    end

    it "skips transactions that are already failed" do
      tx = create(:blockchain_transaction, wallet: wallet, status: :failed, notes: "Previously failed")
      original_balance = wallet.balance
      original_locked = wallet.locked_balance

      described_class.call(
        telemetry_log_id: telemetry_log.id_value,
        created_at_iso: telemetry_log.created_at.iso8601(6)
      )

      wallet.reload
      tx.reload
      expect(wallet.balance).to eq(original_balance)
      expect(wallet.locked_balance).to eq(original_locked)
      expect(tx.notes).to eq("Previously failed")
    end

    it "handles partial locked_balance gracefully" do
      wallet.update!(balance: 20_000, locked_balance: 3_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000, tx_hash: nil)

      described_class.call(
        telemetry_log_id: telemetry_log.id_value,
        created_at_iso: telemetry_log.created_at.iso8601(6)
      )

      tx.reload
      wallet.reload
      expect(tx.status).to eq("failed")
      expect(wallet.locked_balance).to eq(0)
    end

    it "does nothing when telemetry_log not found" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000)

      described_class.call(telemetry_log_id: -1, created_at_iso: Time.current.iso8601(6))

      wallet.reload
      expect(wallet.locked_balance).to eq(10_000)
    end

    it "does nothing when wallet is nil" do
      orphan_tree = create(:tree, cluster: cluster)
      orphan_tree.wallet.destroy!
      orphan_tree.reload

      log = create(:telemetry_log, :verified_telemetry, tree: orphan_tree)

      expect {
        described_class.call(telemetry_log_id: log.id_value, created_at_iso: log.created_at.iso8601(6))
      }.not_to raise_error
    end
  end

  describe ".call with transactions (auto-discovery flow)" do
    it "rolls back all provided pending/processing transactions" do
      wallet.update!(balance: 5_000, locked_balance: 5_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 5_000, tx_hash: nil)

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      expect(tx.status).to eq("failed")
      expect(tx.notes).to include("Rollback")
    end

    it "does nothing when transactions are empty" do
      expect {
        described_class.call(transactions: BlockchainTransaction.none)
      }.not_to raise_error
    end

    # 🔴 [ARCH.101] Пін стереже БАЛАНС, не текст. Спалення нічого не блокувало, тож
    # рефанду не має — а без гарда воно падало у legacy-мінт-гілку, бо `locked_points`
    # у слеш-інтенті `nil` ЗА КОНСТРУКЦІЄЮ (`create_slash_intent!` його не ставить),
    # тобто той самий `nil` означає тут ДВІ різні речі. Далі гілка множила МОНЕТИ на
    # курс (`amount × EMISSION_THRESHOLD`) і «повертала» результат як бали.
    # ⚠️ Числа підібрані так, щоб мутація була ГУЧНОЮ: 2 × 10 000 = 20 000 балів проти
    # 5 000 наявних, тож без гарда спрацював би навіть `elsif`-злив усього залишку в нуль.
    it "does not touch balances when the row is a burn" do
      wallet.update!(balance: 5_000, locked_balance: 5_000)
      contract = create(:naas_contract, organization: organization, cluster: cluster)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                  locked_points: nil, tx_hash: nil, amount: 2, sourceable: contract, direction: :burn)

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      expect(wallet.reload.locked_balance).to eq(5_000)
      expect(tx.reload.status).to eq("failed")
      expect(tx.notes).to include("Спалення НЕ виконано")
    end
  end

  describe ".call with no arguments" do
    it "does nothing gracefully" do
      expect {
        described_class.call
      }.not_to raise_error
    end
  end

  describe "balance broadcast after rollback" do
    it "leaves the balance broadcast to the AR callback — never double-broadcasts" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000, tx_hash: nil)

      broadcasts = 0
      allow_any_instance_of(Wallet).to receive(:broadcast_balance_update) { broadcasts += 1 }

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      # Рівно одна — `after_update_commit :broadcast_status_change` на :failed (файрить і на
      # сирий `update!`). Власного виклику в сервісі немає: інакше було б дві.
      expect(broadcasts).to eq(1)
    end

    it "rolls back EVERY transaction in the batch — no locked_balance left frozen" do
      wallet.update!(balance: 40_000, locked_balance: 20_000)
      tx1 = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000, tx_hash: nil)
      tx2 = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000, tx_hash: nil)

      described_class.call(transactions: BlockchainTransaction.where(id: [ tx1.id, tx2.id ]))

      # Regression: raise на першій tx обривав `txs.each` → tx2 лишалась :pending із
      # замороженими балами, і Sidekiq глушив виняток retries_exhausted-блоку — тихо.
      expect([ tx1.reload.status, tx2.reload.status ]).to eq(%w[failed failed])
      expect(wallet.reload.locked_balance).to be_zero
    end
  end

  # =========================================================================
  # DOUBLE-SPEND GUARD (tx_hash present → manual_review)
  # =========================================================================
  describe "double-spend protection" do
    let!(:telemetry_log) { create(:telemetry_log, :verified_telemetry, tree: tree) }

    context "when transaction has tx_hash (was sent to mempool)" do
      it "escalates to manual_review when receipt is pending (null)" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        # Mock RPC to return nil receipt (transaction pending in mempool)
        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(nil)

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("manual_review")
        expect(wallet.locked_balance).to eq(10_000) # Funds remain locked!
      end

      it "does NOT rollback when receipt shows confirmed on-chain" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        # Mock RPC to return confirmed receipt
        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt)
          .and_return({ "status" => "0x1", "blockNumber" => "0x123" })

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("confirmed")
        expect(wallet.locked_balance).to eq(10_000) # Not released — confirmed on-chain
      end

      it "performs rollback when receipt shows reverted" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        # Mock RPC to return reverted receipt
        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt)
          .and_return({ "status" => "0x0" })

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("failed")
        expect(wallet.locked_balance).to eq(0) # Safely released
      end

      it "escalates to manual_review when RPC throws error" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        # Mock RPC to raise timeout
        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt).and_raise(Net::ReadTimeout)

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("manual_review")
        expect(wallet.locked_balance).to eq(10_000) # Funds remain locked!
      end
    end

    context "when transaction has NO tx_hash (never sent to mempool)" do
      it "safely rolls back and releases funds" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                    tx_hash: nil, locked_points: 10_000)

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("failed")
        expect(wallet.locked_balance).to eq(0)
      end
    end

    it "skips transactions already in manual_review" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :manual_review,
                  tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

      original_locked = wallet.locked_balance

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      wallet.reload
      expect(wallet.locked_balance).to eq(original_locked)
    end
  end

  describe "Solana transaction handling" do
    let!(:telemetry_log) { create(:telemetry_log, :verified_telemetry, tree: tree) }
    let(:solana_address) { "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM" }

    before { ENV["SOLANA_RPC_URL"] ||= "https://api.devnet.solana.com" }

    # Helper: wraps a Hash into Web3::HttpClient::Response (as real HttpClient.post returns)
    def solana_response(hash)
      Web3::HttpClient::Response.new(JSON.generate(hash))
    end

    it "checks Solana RPC for transaction status when network is solana" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "5abc" + SecureRandom.hex(30), locked_points: 10_000,
                  blockchain_network: "solana", to_address: solana_address)

      # Mock Solana getTransaction response — confirmed (no error)
      allow(Web3::HttpClient).to receive(:post).and_return(
        solana_response("result" => { "meta" => { "err" => nil }, "slot" => 12345 })
      )

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      expect(tx.status).to eq("confirmed")
    end

    it "escalates Solana transaction to manual_review when result is nil (pending)" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "5def" + SecureRandom.hex(30), locked_points: 10_000,
                  blockchain_network: "solana", to_address: solana_address)

      allow(Web3::HttpClient).to receive(:post).and_return(
        solana_response("result" => nil)
      )

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      expect(tx.status).to eq("manual_review")
    end

    it "rolls back Solana transaction when meta.err is present (reverted)" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "5ghi" + SecureRandom.hex(30), locked_points: 10_000,
                  blockchain_network: "solana", to_address: solana_address)

      allow(Web3::HttpClient).to receive(:post).and_return(
        solana_response("result" => { "meta" => { "err" => { "InstructionError" => [ 0, "Custom" ] } } })
      )

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      wallet.reload
      expect(tx.status).to eq("failed")
      expect(wallet.locked_balance).to eq(0)
    end

    it "returns :unknown when SOLANA_RPC_URL is not set" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "5jkl" + SecureRandom.hex(30), locked_points: 10_000,
                  blockchain_network: "solana", to_address: solana_address)

      stub_const("ENV", ENV.to_h.except("SOLANA_RPC_URL"))

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      expect(tx.status).to eq("manual_review")
    end
  end

  describe "receipt edge cases" do
    it "treats empty hash receipt as pending" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

      mock_client = instance_double(Eth::Client)
      allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return({})

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      expect(tx.status).to eq("manual_review")
    end

    it "treats receipt with integer status 1 as confirmed" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

      mock_client = instance_double(Eth::Client)
      allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
      allow(mock_client).to receive(:eth_get_transaction_receipt)
        .and_return({ "status" => 1 })

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      expect(tx.status).to eq("confirmed")
    end

    it "treats receipt with status 0x0 as reverted" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

      mock_client = instance_double(Eth::Client)
      allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
      allow(mock_client).to receive(:eth_get_transaction_receipt)
        .and_return({ "status" => "0x0" })

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      wallet.reload
      expect(tx.status).to eq("failed")
      expect(wallet.locked_balance).to eq(0)
    end

    # [BUGFIX] Eth gem 0.5.x returns the full JSON-RPC envelope
    # `{"id":…, "jsonrpc":"2.0", "result": {...}}` from `eth_get_transaction_receipt`.
    # Previously `MintingRollbackService` accessed `receipt["status"]` directly,
    # which is always nil on the envelope shape → every confirmed/pending TX
    # was misclassified as :reverted, opening a double-spend window. These
    # examples lock the wrapped-envelope path so the gem upgrade can't regress.
    describe "JSON-RPC envelope shape (real eth gem 0.5.x)" do
      it "confirms TX when wrapped envelope reports status 0x1" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt)
          .and_return({ "id" => 1, "jsonrpc" => "2.0",
                        "result" => { "status" => "0x1", "blockNumber" => "0x123" } })

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("confirmed")
        expect(wallet.locked_balance).to eq(10_000)
      end

      it "rolls back when wrapped envelope reports status 0x0 (reverted)" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt)
          .and_return({ "id" => 1, "jsonrpc" => "2.0",
                        "result" => { "status" => "0x0" } })

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("failed")
        expect(wallet.locked_balance).to eq(0)
      end

      it "escalates to manual_review when wrapped envelope has null result (mempool)" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt)
          .and_return({ "id" => 1, "jsonrpc" => "2.0", "result" => nil })

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("manual_review")
        expect(wallet.locked_balance).to eq(10_000)
      end

      it "confirms TX when wrapped envelope reports integer status 1" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt)
          .and_return({ "id" => 1, "jsonrpc" => "2.0",
                        "result" => { "status" => 1 } })

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        expect(tx.status).to eq("confirmed")
      end
    end
  end

  describe "locked_points fallback" do
    let!(:telemetry_log) { create(:telemetry_log, :verified_telemetry, tree: tree) }

    it "calculates refund from amount when locked_points is nil" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                  tx_hash: nil, amount: 1)
      tx.update_column(:locked_points, nil)

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      expect(tx.status).to eq("failed")
      expect(tx.notes).to include("Rollback")
    end
  end

  describe "zero locked_balance" do
    it "handles wallet with zero locked_balance gracefully" do
      wallet.update!(balance: 20_000, locked_balance: 0)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                  tx_hash: nil, locked_points: 10_000)

      expect {
        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))
      }.not_to raise_error

      tx.reload
      expect(tx.status).to eq("failed")
    end
  end

  describe "find_telemetry_log with invalid ISO8601" do
    it "falls back to search without partition pruning for malformed date" do
      log = create(:telemetry_log, :verified_telemetry, tree: tree)
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000, tx_hash: nil)

      # Should not raise, even with invalid date
      expect {
        described_class.call(telemetry_log_id: log.id_value, created_at_iso: "not-a-date")
      }.not_to raise_error
    end
  end

  describe "Celo network routing" do
    it "uses CELO_RPC_URL for Celo network transactions" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000,
                  blockchain_network: "celo")

      mock_client = instance_double(Eth::Client)
      allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(nil)

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      expect(Web3::RpcConnectionPool).to have_received(:client_for).with("CELO_RPC_URL", anything)
    end
  end

  describe "Polygon network routing [ARCH.118 ⚖️ 2026-09-03]" do
    # No hardcoded fallback: a blank ALCHEMY_POLYGON_RPC_URL must reach `ENV.fetch` without a
    # default (KeyError on the money path), and the cascade is the KEYLESS registry pair only.
    it "uses ALCHEMY_POLYGON_RPC_URL with the keyless cascade and no `fallback:` literal" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

      mock_client = instance_double(Eth::Client)
      allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(nil)

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      expect(Web3::RpcConnectionPool).to have_received(:client_for)
        .with("ALCHEMY_POLYGON_RPC_URL", fallback_env_keys: %w[POLYGON_RPC_URL_FALLBACK_1 POLYGON_RPC_URL_FALLBACK_2])
    end
  end

  describe "resolve_transactions guards" do
    it "returns nil when telemetry_log's tree has no wallet" do
      orphan_tree = create(:tree)
      orphan_tree.wallet.destroy!
      orphan_log = create(:telemetry_log, :verified_telemetry, tree: orphan_tree)

      expect {
        described_class.call(telemetry_log_id: orphan_log.id, created_at_iso: orphan_log.created_at.iso8601)
      }.not_to(change(BlockchainTransaction, :count))
    end
  end

  describe "receipt without status key (non-empty hash)" do
    it "treats a non-empty receipt that lacks 'status' as pending → manual_review" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

      mock_client = instance_double(Eth::Client)
      allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
      # Receipt is present (not nil, not empty) but the "status" key is absent —
      # exercises the elsif status.nil? branch deliberately.
      allow(mock_client).to receive(:eth_get_transaction_receipt)
        .and_return({ "blockNumber" => "0x123", "transactionHash" => tx.tx_hash })

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      expect(tx.reload.status).to eq("manual_review")
    end
  end

  describe "Solana parsed_body nil safe-navigation" do
    let!(:telemetry_log) { create(:telemetry_log, :verified_telemetry, tree: tree) }
    let(:solana_address) { "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM" }

    before { ENV["SOLANA_RPC_URL"] ||= "https://api.devnet.solana.com" }

    it "treats Solana RPC nil parsed_body as pending → manual_review" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                  tx_hash: "5xyz" + SecureRandom.hex(30), locked_points: 10_000,
                  blockchain_network: "solana", to_address: solana_address)

      # Response whose parsed_body is nil (e.g. blank body / non-JSON) — safe-nav
      # on .dig must skip and return :pending.
      nil_body_response = instance_double(Web3::HttpClient::Response, parsed_body: nil)
      allow(Web3::HttpClient).to receive(:post).and_return(nil_body_response)

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      expect(tx.reload.status).to eq("manual_review")
    end
  end

  describe "perform_safe_rollback with detached tree" do
    it "falls back to 'N/A' tree DID when wallet.tree is nil" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                  tx_hash: nil, locked_points: 10_000)

      # Simulate a wallet whose underlying tree has gone (soft-deleted / missing).
      allow_any_instance_of(Wallet).to receive(:tree).and_return(nil)

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      expect(tx.status).to eq("failed")
      expect(tx.notes).to include("DID: N/A")
    end
  end
end
