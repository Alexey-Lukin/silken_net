# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceOracleService do
  describe ".current_scc_price" do
    before do
      Rails.cache.clear
    end

    it "returns a numeric price" do
      price = described_class.current_scc_price

      expect(price).to be_a(Numeric)
    end

    it "returns price within expected range for test environment" do
      price = described_class.current_scc_price

      expect(price).to be_between(25.0, 26.0)
    end

    it "caches the price for 5 minutes" do
      first_price = described_class.current_scc_price

      # Second call should return the same cached value, not a new random price
      allow(described_class).to receive(:fetch_price_from_uniswap).and_raise("should not be called")

      second_price = described_class.current_scc_price

      expect(second_price).to eq(first_price)
    end

    it "returns fallback price of 25.5 on error" do
      allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "RPC connection failed")

      price = described_class.current_scc_price

      expect(price).to eq(25.5)
    end

    context "when in production environment" do
      let(:mock_client) { instance_double(Eth::Client) }
      let(:mock_contract) { double("contract") }
      let(:raw_amount_out) { 26_000_000 } # 26.0 USDC (6 decimals)

      before do
        Web3::RpcConnectionPool.reset!
        allow(Rails.env).to receive_messages(development?: false, test?: false)
        allow(Eth::Client).to receive(:create).and_return(mock_client)
        allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
        allow(mock_client).to receive(:call).and_return(raw_amount_out)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      end

      it "uses Uniswap quoter to fetch price" do
        price = described_class.current_scc_price

        expect(Eth::Client).to have_received(:create)
        expect(mock_client).to have_received(:call).with(
          mock_contract,
          "quoteExactInputSingle",
          PriceOracleService::SCC_TOKEN,
          PriceOracleService::USDC_TOKEN,
          PriceOracleService::POOL_FEE,
          10**18,
          0
        )
        expect(price).to eq(26.0)
      end
    end
  end
end
