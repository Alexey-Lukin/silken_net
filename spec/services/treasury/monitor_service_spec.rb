# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Treasury::MonitorService do
  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_MINTER_PRIVATE_KEY"] ||= "0x" + "a" * 64
    ENV["ORACLE_SLASHER_PRIVATE_KEY"] ||= "0x" + "e" * 64
    ENV["ORACLE_CELO_PRIVATE_KEY"] ||= "0x" + "c" * 64
    ENV["SOLANA_RPC_URL"] ||= "https://api.devnet.solana.com"
    ENV["SOLANA_FEE_PAYER_PUBKEY"] = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
    ENV["CELO_RPC_URL"] ||= "https://alfajores-forno.celo-testnet.org"
    ENV["ALCHEMY_ETHEREUM_RPC_URL"] ||= "https://eth-mainnet.example.com"
    ENV["ETHEREUM_ANCHOR_PRIVATE_KEY"] ||= "0x" + "b" * 64
    # aux activation-gated (etherisc/puro/klima) СВІДОМО не сетяться — дормантний default

    # Стаб Eth::Key для EVM мереж
    allow(Eth::Key).to receive(:new).and_return(mock_key)

    # Стаб RpcConnectionPool для EVM
    allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_evm_client)

    # Стаб Solana HTTP RPC
    allow(Web3::HttpClient).to receive(:post).and_return(mock_solana_response)

    # Не створювати реальні EWS алерти з побічними ефектами
    silence_broadcasts!(:alert_notify)
    allow_any_instance_of(EwsAlert).to receive(:schedule_satellite_verification!)
    silence_broadcasts!(:alert_new, :alert_update)

    Web3::RpcConnectionPool.reset!
  end

  let(:mock_key) { instance_double(Eth::Key, address: "0x" + "d" * 40) }
  let(:mock_evm_client) { instance_double(Eth::Client) }

  let(:healthy_balance) { (1.0 * 10**18).to_i } # 1.0 нативної валюти
  let(:critical_balance) { (0.01 * 10**18).to_i } # 0.01 нативної валюти

  # Solana RPC response: healthy balance (1 SOL = 1_000_000_000 lamports)
  let(:mock_solana_response) do
    double("response", parsed_body: { "result" => { "value" => 1_000_000_000 } })
  end

  describe ".call" do
    context "when all wallets have healthy balances" do
      before do
        allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance)
      end

      it "returns results for all 5 required wallets (per-signer, INF.22)" do
        results = described_class.call
        expect(results.size).to eq(5)
        expect(results.map { |r| [ r[:network], r[:signer] ] }).to contain_exactly(
          [ "polygon", "minter" ], [ "polygon", "slasher" ],
          [ "solana", "fee_payer" ], [ "celo", "rewards" ], [ "ethereum", "anchor" ]
        )
      end

      it "skips dormant activation-gated aux signers (no result, no gauge, no alert)" do
        results = described_class.call
        expect(results.map { |r| r[:signer] }).not_to include("etherisc", "puro", "klima")
      end

      it "marks all wallets as healthy" do
        results = described_class.call
        expect(results).to all(include(status: :healthy))
      end

      it "reports ratio > 1.0 for all wallets" do
        results = described_class.call
        results.each do |result|
          expect(result[:ratio]).to be > 1.0
        end
      end

      it "does not create any EwsAlert" do
        expect { described_class.call }.not_to change(EwsAlert, :count)
      end

      it "updates Prometheus ORACLE_BALANCE gauges per network+signer" do
        described_class.call

        [ %w[polygon minter], %w[polygon slasher], %w[solana fee_payer],
          %w[celo rewards], %w[ethereum anchor] ].each do |network, signer|
          expect(
            SilkenNet::Metrics::ORACLE_BALANCE.get(labels: { network: network, signer: signer })
          ).to be_positive
        end
      end

      it "monitors an aux signer once its activation-gated key is injected" do
        ENV["ORACLE_ETHERISC_PRIVATE_KEY"] = "0x" + "f" * 64

        results = described_class.call

        etherisc = results.find { |r| r[:signer] == "etherisc" }
        expect(etherisc).to include(network: "polygon", status: :healthy)
        expect(
          SilkenNet::Metrics::ORACLE_BALANCE.get(labels: { network: "polygon", signer: "etherisc" })
        ).to be_positive
      ensure
        ENV.delete("ORACLE_ETHERISC_PRIVATE_KEY")
      end

      # [G1/G2] money-path limbo + drift видимість (той самий 15-хв прохід).
      it "sets manual_review depth, limbo-locked, chain-audit delta, filecoin-unarchived, and anchor confirmation gauges" do
        allow(ChainAuditService).to receive(:call).and_return(
          ChainAuditService::Result.new(db_total: 100.0, chain_total: 97.5, delta: 2.5, critical: true, checked_at: Time.current)
        )
        wallet = create(:wallet)
        create(:blockchain_transaction, wallet: wallet, status: :manual_review, locked_points: 500, created_at: 2.hours.ago)
        create(:blockchain_transaction, wallet: wallet, status: :sent, locked_points: 300, created_at: 2.hours.ago)
        create(:blockchain_transaction, wallet: wallet, status: :confirmed, locked_points: 999, created_at: 2.hours.ago) # excluded
        create(:blockchain_transaction, wallet: wallet, status: :sent, locked_points: 111, created_at: 5.minutes.ago)  # too fresh → excluded
        # [INF.22] archive-outbox backlog — весь pending_archive, не reconcile-вікно
        create(:audit_log, archive_requested_at: 1.hour.ago, ipfs_cid: nil)
        create(:audit_log, archive_requested_at: 40.days.ago, ipfs_cid: nil) # поза reconcile LOOKBACK, але у depth-плато
        create(:audit_log, archive_requested_at: 1.hour.ago, ipfs_cid: "bafyarch") # archived → excluded
        create(:audit_log, archive_requested_at: nil, ipfs_cid: nil) # no outbox marker (factory/console) → excluded
        # [ARCH.66] anchor confirmation-lifecycle backlog
        create(:ethereum_anchor, :sent).update_column(:updated_at, 7.hours.ago) # stuck >6h → stuck_sent_depth
        create(:ethereum_anchor, :sent).update_column(:status, EthereumAnchor.statuses[:manual_review]) # → manual_review_depth
        create(:ethereum_anchor, :sent) # fresh :sent → NOT stuck (excluded)

        described_class.call

        expect(SilkenNet::Metrics::BLOCKCHAIN_MANUAL_REVIEW_DEPTH.get).to eq(1)
        expect(SilkenNet::Metrics::BLOCKCHAIN_LIMBO_LOCKED_TOTAL.get).to eq(800) # 500 + 300 (aged sent/review only)
        expect(SilkenNet::Metrics::CHAIN_AUDIT_DELTA.get).to eq(2.5)
        expect(SilkenNet::Metrics::FILECOIN_UNARCHIVED_DEPTH.get).to eq(2) # marker+no-cid, incl. beyond-LOOKBACK хвіст
        expect(SilkenNet::Metrics::ETHEREUM_ANCHOR_STUCK_SENT_DEPTH.get).to eq(1) # stuck :sent only (fresh excluded)
        expect(SilkenNet::Metrics::ETHEREUM_ANCHOR_MANUAL_REVIEW_DEPTH.get).to eq(1)
      end

      it "does not let a money-path metrics failure break the monitor cycle (rescue)" do
        allow(ChainAuditService).to receive(:call).and_raise(StandardError, "RPC down")
        allow(Rails.logger).to receive(:error)
        expect { described_class.call }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/update_money_path_metrics/)
      end
    end

    context "when Polygon balance is critical" do
      before do
        # Polygon: critical, інші: healthy
        allow(mock_evm_client).to receive(:get_balance) do |_address|
          healthy_balance
        end

        # Override для Polygon — через RpcConnectionPool
        polygon_client = instance_double(Eth::Client)
        allow(polygon_client).to receive(:get_balance).and_return(critical_balance)

        allow(Web3::RpcConnectionPool).to receive(:client_for).and_call_original
        allow(Web3::RpcConnectionPool).to receive(:client_for)
          .with("ALCHEMY_POLYGON_RPC_URL").and_return(polygon_client)
        allow(Web3::RpcConnectionPool).to receive(:client_for)
          .with("CELO_RPC_URL", anything).and_return(mock_evm_client)
        allow(Web3::RpcConnectionPool).to receive(:client_for)
          .with("ALCHEMY_ETHEREUM_RPC_URL").and_return(mock_evm_client)
      end

      it "marks both Polygon signers as critical (shared RPC, both wallets checked)" do
        results = described_class.call
        polygon_results = results.select { |r| r[:network] == "polygon" }
        expect(polygon_results.map { |r| r[:signer] }).to contain_exactly("minter", "slasher")
        polygon_results.each do |result|
          expect(result[:status]).to eq(:critical)
          expect(result[:ratio]).to be < 1.0
        end
      end

      it "creates an EwsAlert per critical signer (minter + slasher)" do
        expect { described_class.call }.to change(EwsAlert, :count).by(2)
      end

      it "creates EwsAlert with system_fault type naming the signer" do
        described_class.call
        alert = EwsAlert.last
        expect(alert.alert_type).to eq("system_fault")
        expect(alert.severity).to eq("critical")
        expect(alert.message).to include("polygon")
        expect(alert.message).to match(/minter|slasher/)
        expect(alert.message_key).to eq("oracle_balance_low")
      end
    end

    # [ARCH.82] ⚖️ founder 2026-08-14: безкластерний алерт закривається АВТОМАТИЧНО.
    # Людського шляху до нього не існує — `Organization has_many :ews_alerts, through:
    # :clusters` це INNER JOIN, тож рядок без кластера не видно на жодній орг-поверхні,
    # і без резолвера він висить вічно.
    describe "авто-резолв алертів, чия причина зникла" do
      def hanging_oracle_alert(network:, signer:)
        EwsAlert.create!(
          alert_type: :system_fault, severity: :critical, status: :active,
          message_key: "oracle_balance_low",
          message_params: { network: network, signer: signer, balance: "0.01",
                            currency: "MATIC", min_threshold: "0.5", ratio: 0.02 }
        )
      end

      context "when balances have recovered" do
        before { allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance) }

        it "закриває висячий алерт пари, яка більше не критична" do
          alert = hanging_oracle_alert(network: "polygon", signer: "minter")

          described_class.call

          expect(alert.reload.status).to eq("resolved")
          expect(alert.resolved_at).to be_present
          expect(alert.resolution_log.last["key"]).to eq("oracle_balance_recovered")
          expect(alert.resolution_texts.join).to include("polygon/minter")
        end

        it "не чіпає алертів ІНШОГО роду — ключ одужання не ширший за ключ дедупу" do
          # Ліхтар проти over-broad резолвера. Ціль навмисно НЕ `mint_volume_anomaly`:
          # той самий прохід має ВЛАСНИЙ резолвер для нього, тож він закрився б законно —
          # і приклад пройшов би, нічого не довівши. Беремо ключ, якого не володіє жоден
          # із двох (HOLD страхового резерву — його канал — Grafana, не резолвер).
          other = EwsAlert.create!(
            alert_type: :system_fault, severity: :critical, status: :active,
            message_key: "insurance_reserve_hold_aggregate_cap",
            message_params: { id: 1, window_scc: "500.0", cap_scc: "100.0" }
          )

          described_class.call

          expect(other.reload.status).to eq("active")
        end
      end

      context "when one pair is still critical" do
        before do
          allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance)
          polygon_client = instance_double(Eth::Client)
          allow(polygon_client).to receive(:get_balance).and_return(critical_balance)
          allow(Web3::RpcConnectionPool).to receive(:client_for).and_call_original
          allow(Web3::RpcConnectionPool).to receive(:client_for)
            .with("ALCHEMY_POLYGON_RPC_URL").and_return(polygon_client)
          allow(Web3::RpcConnectionPool).to receive(:client_for)
            .with("CELO_RPC_URL", anything).and_return(mock_evm_client)
          allow(Web3::RpcConnectionPool).to receive(:client_for)
            .with("ALCHEMY_ETHEREUM_RPC_URL").and_return(mock_evm_client)
        end

        # 🔴 Найважливіший напрямок: резолвер, що закриває ВСЕ, гірший за його відсутність —
        # він гасить живу тривогу. Ключ одужання = ПАРА (мережа, підписник), як і ключ дедупу.
        it "лишає її алерт активним, закриваючи лише одужалу сусідню мережу" do
          still_critical = hanging_oracle_alert(network: "polygon", signer: "minter")
          recovered = hanging_oracle_alert(network: "celo", signer: "rewards")

          described_class.call

          expect(still_critical.reload.status).to eq("active")
          expect(recovered.reload.status).to eq("resolved")
        end
      end

      context "with the mint-volume detector" do
        before { allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance) }

        def hanging_mint_alert(token_type)
          EwsAlert.create!(
            alert_type: :system_fault, severity: :critical, status: :active,
            message_key: "mint_volume_anomaly",
            message_params: { token_type: token_type, volume: 9.0, window: "1 hour", ceiling: 1.0 }
          )
        end

        # Асиметрія, яку це прибирає: Kredis-запобіжник має TTL і сам відпускається,
        # а алерт про той самий сплеск не відпускався НІКОЛИ.
        it "закриває алерт, коли обсяг повернувся під увімкнену стелю" do
          SystemParameter.set(:mint_volume_hourly_max_scc, 1_000_000)
          alert = hanging_mint_alert("carbon_coin")

          described_class.call

          expect(alert.reload.status).to eq("resolved")
          expect(alert.resolution_log.last["key"]).to eq("mint_volume_recovered")
        end

        it "закриває алерт вимкненого детектора, але нотатка каже ІНШЕ" do
          # Поріг 0 = детектор off. Причина не усунута — вона стала безпредметною,
          # і нотатка мусить це розрізняти, інакше запис бреше про одужання.
          SystemParameter.set(:mint_volume_hourly_max_scc, 0)
          alert = hanging_mint_alert("carbon_coin")

          described_class.call

          expect(alert.reload.status).to eq("resolved")
          expect(alert.resolution_log.last["key"]).to eq("mint_volume_detector_disabled")
          expect(alert.resolution_log.last["key"]).not_to eq("mint_volume_recovered")
          I18n.with_locale(:uk) do
            expect(alert.resolution_texts.join).to include("безпредметний")
          end
        end
      end
    end

    context "when Solana RPC fails" do
      before do
        allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance)
        allow(Web3::HttpClient).to receive(:post).and_raise(Timeout::Error, "Solana RPC timeout")
      end

      it "marks Solana as error" do
        results = described_class.call
        solana_result = results.find { |r| r[:network] == "solana" }
        expect(solana_result[:status]).to eq(:error)
        expect(solana_result[:error]).to include("timeout")
      end

      it "increments TREASURY_CHECK_ERRORS_TOTAL metric" do
        described_class.call
        expect(
          SilkenNet::Metrics::TREASURY_CHECK_ERRORS_TOTAL.get(
            labels: { network: "solana", signer: "fee_payer", error_type: "Timeout::Error" }
          )
        ).to be_positive
      end

      it "does not fail the entire service" do
        results = described_class.call
        expect(results.size).to eq(5)
        healthy_results = results.select { |r| r[:status] == :healthy }
        expect(healthy_results.size).to eq(4)
      end
    end

    context "when credentials are missing" do
      before do
        allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance)
        ENV.delete("SOLANA_FEE_PAYER_PUBKEY")
      end

      after do
        ENV["SOLANA_FEE_PAYER_PUBKEY"] = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
      end

      it "returns zero balance when pubkey is missing" do
        results = described_class.call
        solana_result = results.find { |r| r[:network] == "solana" }
        expect(solana_result[:balance_raw]).to eq(0)
        expect(solana_result[:status]).to eq(:critical)
      end
    end
  end

  describe "ARCH.62 mint-volume anomaly detector" do
    before do
      allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance)
      allow(ChainAuditService).to receive(:call).and_return(
        ChainAuditService::Result.new(db_total: 0, chain_total: 0, delta: 0, critical: false, checked_at: Time.current)
      )
      allow(SystemParameter).to receive(:current).and_call_original
    end

    def arm(max_scc: 0, breaker: false)
      allow(SystemParameter).to receive(:current)
        .with(:mint_volume_hourly_max_scc, default: 0).and_return(max_scc)
      allow(SystemParameter).to receive(:current)
        .with(:mint_circuit_breaker_enabled, default: false).and_return(breaker)
    end

    it "sets the rolling-1h mint-volume gauge per token_type (partition-prune window)" do
      wallet = create(:wallet)
      create(:blockchain_transaction, wallet: wallet, token_type: :carbon_coin, status: :confirmed, amount: 40.0, created_at: 10.minutes.ago)
      create(:blockchain_transaction, wallet: wallet, token_type: :carbon_coin, status: :sent, amount: 25.0, created_at: 90.minutes.ago) # too old → excluded
      arm(max_scc: 0)

      described_class.call

      expect(SilkenNet::Metrics::MINT_VOLUME_WINDOW_SCC.get(labels: { token_type: "carbon_coin" })).to eq(40.0)
    end

    it "is inert when the ceiling is off (0) — gauge still live, no alert" do
      wallet = create(:wallet)
      create(:blockchain_transaction, wallet: wallet, token_type: :carbon_coin, status: :confirmed, amount: 5_000.0, created_at: 5.minutes.ago)
      arm(max_scc: 0)

      expect { described_class.call }.not_to change(EwsAlert, :count)
    end

    it "raises a system_fault alert when volume breaches the configured ceiling" do
      wallet = create(:wallet)
      create(:blockchain_transaction, wallet: wallet, token_type: :carbon_coin, status: :confirmed, amount: 5_000.0, created_at: 5.minutes.ago)
      arm(max_scc: 1_000)

      expect { described_class.call }.to change { EwsAlert.where(alert_type: :system_fault).count }.by(1)
    end

    it "dedups the volume alert across cycles (no 15-min storm on a sustained breach)" do
      wallet = create(:wallet)
      create(:blockchain_transaction, wallet: wallet, token_type: :carbon_coin, status: :confirmed, amount: 5_000.0, created_at: 5.minutes.ago)
      arm(max_scc: 1_000)

      described_class.call # 1st cycle → creates the alert
      expect { described_class.call }.not_to change { EwsAlert.where(alert_type: :system_fault).count }
    end

    it "trips a PER-TOKEN Kredis circuit flag ONLY when the breaker kill-switch is on" do
      wallet = create(:wallet)
      create(:blockchain_transaction, wallet: wallet, token_type: :carbon_coin, status: :confirmed, amount: 5_000.0, created_at: 5.minutes.ago)
      arm(max_scc: 1_000, breaker: true)
      flag = instance_double(Kredis::Types::Flag)
      allow(Kredis).to receive(:flag).and_return(flag)
      allow(flag).to receive(:mark)

      described_class.call

      expect(Kredis).to have_received(:flag).with("#{BlockchainMintingService::MINT_CIRCUIT_FLAG_PREFIX}carbon_coin")
      # [ARCH.62] TTL-pin: circuit auto-releases за MINT_CIRCUIT_TTL (re-runnable). Рефактор, що
      # впустить expires_in → permanent flag → mint wedge назавжди до ручного .remove.
      expect(flag).to have_received(:mark).with(expires_in: described_class::MINT_CIRCUIT_TTL)
    end

    it "trips INDEPENDENT per-token flags + alerts when both tokens breach (isolation)" do
      wallet = create(:wallet)
      create(:blockchain_transaction, wallet: wallet, token_type: :carbon_coin, status: :confirmed, amount: 5_000.0, created_at: 5.minutes.ago)
      create(:blockchain_transaction, wallet: wallet, token_type: :forest_coin, status: :confirmed, amount: 5_000.0, created_at: 5.minutes.ago)
      arm(max_scc: 1_000, breaker: true)
      flag = instance_double(Kredis::Types::Flag)
      allow(Kredis).to receive(:flag).and_return(flag)
      allow(flag).to receive(:mark)

      # Two distinct alerts (per-token dedup does NOT collapse them) + both per-token flags.
      expect { described_class.call }.to change { EwsAlert.where(alert_type: :system_fault).count }.by(2)
      expect(Kredis).to have_received(:flag).with("#{BlockchainMintingService::MINT_CIRCUIT_FLAG_PREFIX}carbon_coin")
      expect(Kredis).to have_received(:flag).with("#{BlockchainMintingService::MINT_CIRCUIT_FLAG_PREFIX}forest_coin")
    end

    it "does NOT trip the circuit flag when the breaker is off (breach alerts only)" do
      wallet = create(:wallet)
      create(:blockchain_transaction, wallet: wallet, token_type: :carbon_coin, status: :confirmed, amount: 5_000.0, created_at: 5.minutes.ago)
      arm(max_scc: 1_000, breaker: false)

      expect(Kredis).not_to receive(:flag)
      described_class.call
    end
  end

  describe "humanize_balance" do
    it "converts wei to MATIC correctly" do
      service = described_class.new
      result = service.send(:humanize_balance, 50_000_000_000_000_000, 18)
      expect(result).to eq("0.050000")
    end

    it "converts lamports to SOL correctly" do
      service = described_class.new
      result = service.send(:humanize_balance, 50_000_000, 9)
      expect(result).to eq("0.050000")
    end

    it "handles zero balance" do
      service = described_class.new
      result = service.send(:humanize_balance, 0, 18)
      expect(result).to eq("0.000000")
    end

    it "handles very large balance" do
      service = described_class.new
      result = service.send(:humanize_balance, 10**18 * 1_000_000, 18)
      expect(result).to eq("1000000.000000")
    end

    it "handles 1 wei precision" do
      service = described_class.new
      result = service.send(:humanize_balance, 1, 18)
      expect(result).to eq("0.000000") # Below 6-decimal precision
    end
  end

  describe "build_config" do
    it "resolves the wallet entry with the default min_balance" do
      service = described_class.new
      config = service.send(:build_config, described_class::WALLETS[:polygon_minter])

      expect(config[:currency]).to eq("MATIC")
      expect(config[:signer]).to eq("minter")
      expect(config[:decimals]).to eq(18)
      expect(config[:min_balance_wei]).to be_a(Integer)
      expect(config[:min_balance_wei]).to be > 0
      expect(config[:env_rpc_key]).to eq("ALCHEMY_POLYGON_RPC_URL")
    end

    it "uses SystemParameter value when available" do
      allow(SystemParameter).to receive(:current).with("oracle_min_balance_matic", default: 0.05).and_return("0.1")
      service = described_class.new
      config = service.send(:build_config, described_class::WALLETS[:polygon_minter])

      # 0.1 MATIC = 100_000_000_000_000_000 wei
      expect(config[:min_balance_wei]).to eq(100_000_000_000_000_000)
    end

    it "gives the slasher wallet its OWN threshold param (slash-gas ≠ mint-gas profile)" do
      allow(SystemParameter).to receive(:current).and_call_original
      allow(SystemParameter).to receive(:current)
        .with("oracle_min_balance_matic_slasher", default: 0.05).and_return("0.2")
      service = described_class.new
      config = service.send(:build_config, described_class::WALLETS[:polygon_slasher])

      expect(config[:min_balance_wei]).to eq(200_000_000_000_000_000)
    end

    it "falls back to default when SystemParameter returns nil" do
      allow(SystemParameter).to receive(:current).and_return(nil)
      service = described_class.new
      config = service.send(:build_config, described_class::WALLETS[:polygon_minter])

      # 0.05 MATIC
      expect(config[:min_balance_wei]).to eq(50_000_000_000_000_000)
    end
  end

  describe "fetch_evm_balance" do
    it "returns 0 when private_key is blank" do
      stub_const("ENV", ENV.to_h.except("ORACLE_MINTER_PRIVATE_KEY"))
      service = described_class.new
      config = described_class::WALLETS[:polygon_minter].merge(min_balance_wei: 50_000_000_000_000_000)

      result = service.send(:fetch_evm_balance, config)
      expect(result).to eq(0)
    end

    it "uses fallback RPC for Celo" do
      allow(Web3::RpcConnectionPool).to receive(:client_for)
        .with("CELO_RPC_URL", fallback: "https://alfajores-forno.celo-testnet.org")
        .and_return(mock_evm_client)
      allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance)

      service = described_class.new
      config = described_class::WALLETS[:celo_rewards].merge(min_balance_wei: 50_000_000_000_000_000)

      result = service.send(:fetch_evm_balance, config)
      expect(result).to eq(healthy_balance)
    end
  end

  describe "fetch_solana_balance" do
    let(:solana_config) { described_class::WALLETS[:solana_fee_payer].merge(min_balance_wei: 50_000_000) }

    it "returns 0 when fee_payer pubkey is blank" do
      stub_const("ENV", ENV.to_h.except("SOLANA_FEE_PAYER_PUBKEY"))

      result = described_class.new.send(:fetch_solana_balance, solana_config)
      expect(result).to eq(0)
    end

    it "handles nil parsed_body gracefully" do
      allow(Web3::HttpClient).to receive(:post).and_return(
        double("response", parsed_body: nil)
      )

      result = described_class.new.send(:fetch_solana_balance, solana_config)
      expect(result).to eq(0)
    end

    it "returns 0 and logs a warning in production when RPC URL ENV is not set [E.47]" do
      stub_const("ENV", ENV.to_h.except(solana_config[:env_rpc_key].to_s))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect(Rails.logger).to receive(:warn).with(/not set in production/)

      result = described_class.new.send(:fetch_solana_balance, solana_config)
      expect(result).to eq(0)
    end

    it "handles malformed response (missing result key)" do
      allow(Web3::HttpClient).to receive(:post).and_return(
        double("response", parsed_body: { "error" => { "message" => "bad request" } })
      )

      result = described_class.new.send(:fetch_solana_balance, solana_config)
      expect(result).to eq(0)
    end
  end

  describe "generate_alerts" do
    before do
      allow(mock_evm_client).to receive(:get_balance).and_return(critical_balance)
    end

    it "creates EwsAlerts for multiple critical networks" do
      # Make Solana critical too
      allow(Web3::HttpClient).to receive(:post).and_return(
        double("response", parsed_body: { "result" => { "value" => 100 } })
      )

      expect { described_class.call }.to change(EwsAlert, :count).by_at_least(2)
    end

    it "does not create alerts when no networks are critical" do
      allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance)

      expect { described_class.call }.not_to change(EwsAlert, :count)
    end

    # 🔴 Асиметрія в ОДНОМУ файлі: сусідній `mint_volume`-детектор мав дедуп із
    # порахованою ціною («~4/год/токен → флуд ops-черги»), а oracle-balance за 170
    # рядків нижче не мав жодного. Порожній гаманець тримається годинами, крон ходить
    # `*/15`, підписантів вісім — до 32 нових `active` critical-рядків на годину.
    # ⚠️ Другу половину властивості — що дедуп ключується на ПАРУ (мережа, підписант) і
    # не злипає різних підписантів — уже стереже `creates an EwsAlert per critical signer`
    # вище (точний `.by(2)`); мутація «зняти пару з ключа» червонить саме його, тож
    # третій копії тут свідомо немає.
    it "dedups the oracle-balance alert across cycles (no 15-min storm on a drained wallet)" do
      described_class.call

      expect { described_class.call }
        .not_to change { EwsAlert.where(message_key: "oracle_balance_low").count }
    end
  end

  describe "check_balance with a zero min-threshold (no-minimum config)" do
    it "reports ratio 0.0 and healthy status when min_balance_wei is 0 (div-by-zero guard)" do
      service = described_class.new
      allow(service).to receive(:fetch_balance).and_return(healthy_balance)
      config = { network: "polygon", signer: "minter", currency: "MATIC", decimals: 18, min_balance_wei: 0 }

      result = service.send(:check_balance, config)

      expect(result[:ratio]).to eq(0.0)
      expect(result[:status]).to eq(:healthy) # balance >= 0
    end
  end

  describe "check_balance error handling" do
    it "returns error status with truncated message on failure" do
      allow(mock_evm_client).to receive(:get_balance).and_raise(
        StandardError, "A" * 300
      )

      results = described_class.call
      polygon_result = results.find { |r| r[:network] == "polygon" }

      expect(polygon_result[:status]).to eq(:error)
      expect(polygon_result[:error].length).to be <= 200
      expect(polygon_result[:balance_human]).to eq("ERROR")
    end
  end

  describe "update_metrics" do
    before do
      allow(mock_evm_client).to receive(:get_balance).and_return(healthy_balance)
    end

    it "does not set ORACLE_BALANCE when balance_raw is nil" do
      allow(mock_evm_client).to receive(:get_balance).and_raise(StandardError, "fail")

      # Even with errors, the service should not crash
      expect { described_class.call }.not_to raise_error
    end
  end
end
