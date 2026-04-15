# frozen_string_literal: true

require "rails_helper"

RSpec.describe Treasury::MonitorService do
  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_PRIVATE_KEY"] ||= "0x" + "a" * 64
    ENV["SOLANA_RPC_URL"] ||= "https://api.devnet.solana.com"
    ENV["SOLANA_FEE_PAYER_PUBKEY"] ||= "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
    ENV["CELO_RPC_URL"] ||= "https://alfajores-forno.celo-testnet.org"
    ENV["ALCHEMY_ETHEREUM_RPC_URL"] ||= "https://eth-mainnet.example.com"
    ENV["ETHEREUM_ANCHOR_PRIVATE_KEY"] ||= "0x" + "b" * 64

    # Стаб Eth::Key для EVM мереж
    allow(Eth::Key).to receive(:new).and_return(mock_key)

    # Стаб RpcConnectionPool для EVM
    allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_evm_client)

    # Стаб Solana HTTP RPC
    allow(Web3::HttpClient).to receive(:post).and_return(mock_solana_response)

    # Не створювати реальні EWS алерти з побічними ефектами
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
    allow_any_instance_of(EwsAlert).to receive(:schedule_satellite_verification!)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_new_alert)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)

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

      it "returns results for all 4 networks" do
        results = described_class.call
        expect(results.size).to eq(4)
        expect(results.map { |r| r[:network] }).to contain_exactly("polygon", "solana", "celo", "ethereum")
      end

      it "marks all networks as healthy" do
        results = described_class.call
        expect(results).to all(include(status: :healthy))
      end

      it "reports ratio > 1.0 for all networks" do
        results = described_class.call
        results.each do |result|
          expect(result[:ratio]).to be > 1.0
        end
      end

      it "does not create any EwsAlert" do
        expect { described_class.call }.not_to change(EwsAlert, :count)
      end

      it "updates Prometheus ORACLE_BALANCE gauges" do
        described_class.call

        %w[polygon solana celo ethereum].each do |network|
          expect(SilkenNet::Metrics::ORACLE_BALANCE.get(labels: { network: network })).to be_positive
        end
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

      it "marks Polygon as critical" do
        results = described_class.call
        polygon_result = results.find { |r| r[:network] == "polygon" }
        expect(polygon_result[:status]).to eq(:critical)
        expect(polygon_result[:ratio]).to be < 1.0
      end

      it "creates an EwsAlert for critical balance" do
        expect { described_class.call }.to change(EwsAlert, :count).by(1)
      end

      it "creates EwsAlert with system_fault type" do
        described_class.call
        alert = EwsAlert.last
        expect(alert.alert_type).to eq("system_fault")
        expect(alert.severity).to eq("critical")
        expect(alert.message).to include("polygon")
        expect(alert.message).to include("below minimum threshold")
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
            labels: { network: "solana", error_type: "Timeout::Error" }
          )
        ).to be_positive
      end

      it "does not fail the entire service" do
        results = described_class.call
        expect(results.size).to eq(4)
        healthy_results = results.select { |r| r[:status] == :healthy }
        expect(healthy_results.size).to eq(3)
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
  end
end
