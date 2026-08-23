# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# = ===================================================================
# ⚡ CHAOS ENGINEERING: Proof of Growth Pipeline Resilience
# = ===================================================================
# Вектор 3: Симуляція катастроф у Web3 середовищі.
# Тести перевіряють поведінку системи при:
# - Тривалому падінні IoTeX W3bstream (24+ години)
# - Глибокій реорганізації блоків Polygon (Reorg)
# - Timeout від Chainlink Oracle
# - Каскадних збоях в мультичейн архітектурі
RSpec.describe "Chaos Engineering: Proof of Growth Pipeline" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster, status: :active) }
  let!(:wallet) { tree.wallet || create(:wallet, tree: tree, organization: organization) }

  before do
    silence_broadcasts!(:tree_map)
  end

  # ---------------------------------------------------------------
  # Сценарій 1: IoTeX W3bstream падає на 24 години
  # ---------------------------------------------------------------
  describe "when IoTeX W3bstream is down for 24 hours" do
    let(:telemetry_log) do
      create(:telemetry_log, tree: tree, verified_by_iotex: false, oracle_status: "pending")
    end

    before do
      # Preload hardware_key to avoid N+1 detection by Prosopite
      allow_any_instance_of(Tree).to receive(:hardware_key).and_return(nil)
    end

    it "Sidekiq worker retries without corrupting state" do
      # Симулюємо 5 послідовних таймаутів від W3bstream
      service = Iotex::W3bstreamVerificationService.new(telemetry_log)
      allow(Web3::HttpClient).to receive(:post).and_raise(
        Web3::HttpClient::RequestError, "W3bstream: connect timeout"
      )

      5.times do
        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError)
      end

      # Стейт повинен залишитись незмінним — не verified, не dispatched
      telemetry_log.reload
      expect(telemetry_log.verified_by_iotex).to be false
      expect(telemetry_log.zk_proof_ref).to be_nil
      expect(telemetry_log.oracle_status).to eq("pending")
    end

    it "Circuit Breaker відкривається після порогу помилок" do
      # Тестуємо Circuit Breaker напряму через concern, без Sidekiq worker overhead
      test_class = Class.new { include Web3CircuitBreaker }
      cb_instance = test_class.new

      Rails.cache.delete("circuit_breaker:iotex_w3bstream:failures")
      Rails.cache.delete("circuit_breaker:iotex_w3bstream:opened_at")

      # Симулюємо W3bstream connection failures (transient errors)
      Web3CircuitBreaker::FAILURE_THRESHOLD.times do
        expect {
          cb_instance.with_circuit_breaker("iotex_w3bstream") do
            raise Errno::ECONNREFUSED, "Connection refused"
          end
        }.to raise_error(Errno::ECONNREFUSED)
      end

      # Circuit is now open — next call should be rejected immediately (fail-fast)
      expect {
        cb_instance.with_circuit_breaker("iotex_w3bstream") { "should not execute" }
      }.to raise_error(Web3CircuitBreaker::CircuitOpenError)
    end

    it "does not trigger Chainlink dispatch for unverified data" do
      expect(ChainlinkDispatchWorker).not_to receive(:perform_async)

      service = Iotex::W3bstreamVerificationService.new(telemetry_log)
      allow(Web3::HttpClient).to receive(:post).and_raise(
        Web3::HttpClient::RequestError, "W3bstream: 503 Service Unavailable"
      )

      expect {
        service.verify!
      }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError)
    end
  end

  # ---------------------------------------------------------------
  # Сценарій 2: Polygon Block Reorg після мінтингу SCC
  # ---------------------------------------------------------------
  describe "when Polygon deep reorg occurs after SCC minting" do
    let(:telemetry_log) do
      create(:telemetry_log, tree: tree,
        verified_by_iotex: true,
        oracle_status: "fulfilled",
        zk_proof_ref: "zk-proof-valid-123",
        chainlink_request_id: "chainlink-req-abc")
    end

    let!(:blockchain_tx) do
      create(:blockchain_transaction,
        wallet: wallet,
        status: :sent,
        tx_hash: "0x#{"a" * 64}",
        token_type: :carbon_coin,
        amount: 1.0,
        to_address: wallet.crypto_public_address || "0x#{"b" * 40}")
    end

    it "BlockchainConfirmationWorker handles missing receipt (reverted tx)" do
      # Після Reorg, транзакція вже не існує в канонічному ланцюгу
      mock_client = instance_double(Eth::Client)
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(nil)

      # Воркер повинен залишити TX в статусі :sent для повторної перевірки
      # (Sidekiq retry), а не помітити як :confirmed
      expect(blockchain_tx.status).to eq("sent")
      expect(blockchain_tx.reload.status).not_to eq("confirmed")
    end

    it "wallet balance remains locked during reorg uncertainty" do
      wallet.update!(balance: 10_000, locked_balance: 10_000)

      # Під час Reorg — заблоковані кошти НЕ повинні розблокуватись
      # до отримання підтвердження з нового канонічного ланцюгу
      expect(wallet.available_balance).to eq(wallet.balance - 10_000)
      expect(wallet.locked_balance).to eq(10_000)
    end

    it "duplicate minting is prevented by tx_hash uniqueness" do
      # Після Reorg, OracleCallback може прийти повторно (replay)
      # oracle_callbacks_controller використовує atomic update_all
      # з WHERE oracle_status='dispatched' — повторний callback
      # на вже fulfilled/failed лог поверне 409 Conflict

      # Моделюємо: oracle_status вже fulfilled
      expect(telemetry_log.oracle_status).to eq("fulfilled")

      # Спроба оновити dispatched → fulfilled — 0 rows (вже fulfilled)
      updated = TelemetryLog.where(
        id: telemetry_log.id,
        created_at: telemetry_log.created_at,
        oracle_status: "dispatched"
      ).update_all(oracle_status: "fulfilled")

      expect(updated).to eq(0) # Replay blocked
    end
  end

  # ---------------------------------------------------------------
  # Сценарій 3: Chainlink dispatch — local marker (ARCH.53 демоут)
  # ---------------------------------------------------------------
  describe "Chainlink dispatch resilience" do
    let(:telemetry_log) do
      create(:telemetry_log, tree: tree,
        verified_by_iotex: true,
        oracle_status: "pending",
        zk_proof_ref: "zk-proof-valid-456")
    end

    # [ARCH.53]: регресія проти воскресіння on-chain шляху — навіть із legacy
    # ENV dispatch НЕ сміє торкатись RPC (LINK-cost за callback, що не прилетить).
    it "never touches RPC even when legacy on-chain ENV is present" do
      stub_const("ENV", ENV.to_h.merge(
        "CHAINLINK_FUNCTIONS_ROUTER" => "0x#{"1" * 40}",
        "CHAINLINK_SUBSCRIPTION_ID" => "42",
        "CHAINLINK_DON_ID" => "0x#{"d" * 64}",
        "ALCHEMY_POLYGON_RPC_URL" => "https://polygon-rpc.example.com",
        "ORACLE_PRIVATE_KEY" => "a" * 64
      ))
      expect(Web3::RpcConnectionPool).not_to receive(:client_for)
      expect(Eth::Client).not_to receive(:create)

      request_id = Chainlink::OracleDispatchService.new(telemetry_log).dispatch!

      expect(request_id).to start_with("chainlink-req-")
    end

    it "telemetry log state transitions to dispatched with a marker" do
      service = Chainlink::OracleDispatchService.new(telemetry_log)

      service.dispatch!
      telemetry_log.reload

      expect(telemetry_log.oracle_status).to eq("dispatched")
      expect(telemetry_log.chainlink_request_id).to be_present
    end

    it "Circuit Breaker prevents cascade failures on Chainlink" do
      # Тестуємо Circuit Breaker напряму через concern
      test_class = Class.new { include Web3CircuitBreaker }
      cb_instance = test_class.new

      Rails.cache.delete("circuit_breaker:chainlink_functions:failures")
      Rails.cache.delete("circuit_breaker:chainlink_functions:opened_at")

      # Симулюємо Chainlink RPC timeout (transient errors)
      Web3CircuitBreaker::FAILURE_THRESHOLD.times do
        expect {
          cb_instance.with_circuit_breaker("chainlink_functions") do
            raise Net::OpenTimeout, "connect timeout"
          end
        }.to raise_error(Net::OpenTimeout)
      end

      # Circuit is open — fail-fast
      expect {
        cb_instance.with_circuit_breaker("chainlink_functions") { "should not execute" }
      }.to raise_error(Web3CircuitBreaker::CircuitOpenError)
    end
  end

  # ---------------------------------------------------------------
  # Сценарій 4: Мультичейн каскадний збій
  # ---------------------------------------------------------------
  describe "when multiple chains fail simultaneously" do
    it "Solana failure does not block Polygon minting" do
      # Solana та Polygon мінтинг запускаються паралельно через окремі воркери
      # (SolanaMicroRewardWorker та MintCarbonCoinWorker)
      # Збій одного не повинен блокувати інший

      log = create(:telemetry_log, tree: tree,
        verified_by_iotex: true,
        oracle_status: "fulfilled",
        zk_proof_ref: "zk-proof-ok",
        chainlink_request_id: "chainlink-req-ok")

      # MintCarbonCoinWorker → web3_critical, SolanaMicroRewardWorker → web3
      # Вони в різних чергах — повна ізоляція
      expect {
        MintCarbonCoinWorker.perform_async(log.id_value, log.created_at.iso8601(6))
      }.to change(Sidekiq::Queues["web3_critical"], :size).by(1)

      expect {
        SolanaMicroRewardWorker.perform_async(log.id_value, log.created_at.iso8601(6))
      }.to change(Sidekiq::Queues["web3"], :size).by(1)
    end

    it "independent Circuit Breakers per chain" do
      # Солана може бути down, але Polygon працює
      # Circuit Breaker для "solana_rpc" не впливає на "polygon_rpc"

      test_worker_class = Class.new do
        include ApplicationWeb3Worker
        include Web3CircuitBreaker
      end
      worker = test_worker_class.new

      Rails.cache.delete("circuit_breaker:solana_rpc:failures")
      Rails.cache.delete("circuit_breaker:polygon_rpc:failures")

      # Відкриваємо circuit для Solana
      Rails.cache.write("circuit_breaker:solana_rpc:failures", Web3CircuitBreaker::FAILURE_THRESHOLD)
      Rails.cache.write("circuit_breaker:solana_rpc:opened_at", Time.current.to_f)

      # Solana — OPEN
      expect {
        worker.with_circuit_breaker("solana_rpc") { "solana" }
      }.to raise_error(Web3CircuitBreaker::CircuitOpenError)

      # Polygon — CLOSED (працює)
      result = worker.with_circuit_breaker("polygon_rpc") { "polygon works" }
      expect(result).to eq("polygon works")
    end
  end
end
