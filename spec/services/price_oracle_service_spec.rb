# SPDX-License-Identifier: AGPL-3.0-or-later
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

    # Стаб таргетований на key "scc_market_price" — глобальний стаб на
    # `Rails.cache.fetch` ловив би й `SystemParameter.current` (який сам
    # використовує `Rails.cache.fetch`), що зруйнувало б fallback chain.
    it "returns fallback price of 25.5 on error" do
      allow(Rails.cache).to receive(:fetch).and_call_original
      allow(Rails.cache).to receive(:fetch).with("scc_market_price", anything).and_raise(StandardError, "RPC connection failed")

      price = described_class.current_scc_price

      expect(price).to eq(25.5)
    end

    it "returns fallback price on Timeout::Error" do
      allow(Rails.cache).to receive(:fetch).and_call_original
      allow(Rails.cache).to receive(:fetch).with("scc_market_price", anything).and_raise(Timeout::Error, "execution expired")

      price = described_class.current_scc_price

      expect(price).to eq(25.5)
    end

    it "logs an error when falling back" do
      allow(Rails.cache).to receive(:fetch).and_call_original
      allow(Rails.cache).to receive(:fetch).with("scc_market_price", anything).and_raise(StandardError, "RPC connection failed")

      allow(Rails.logger).to receive(:error).with(/ORACLE ERROR.*RPC connection failed/)

      described_class.current_scc_price

      expect(Rails.logger).to have_received(:error).with(/ORACLE ERROR.*RPC connection failed/)
    end

    context "when in production environment" do
      let(:mock_client) { instance_double(Eth::Client) }
      let(:mock_contract) { instance_double(Eth::Contract) }
      let(:raw_amount_out) { 26_000_000 } # 26.0 USDC (6 decimals)

      before do
        Web3::RpcConnectionPool.reset!
        allow(Rails.env).to receive_messages(development?: false, test?: false)
        allow(Eth::Client).to receive(:create).and_return(mock_client)
        allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
        allow(mock_client).to receive(:call).and_return(raw_amount_out)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
        allow(ENV).to receive(:fetch).with("CARBON_COIN_CONTRACT_ADDRESS").and_return("0x#{'c' * 40}")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      end

      it "uses Uniswap quoter to fetch price" do
        price = described_class.current_scc_price

        expect(Eth::Client).to have_received(:create)
        expect(mock_client).to have_received(:call).with(
          mock_contract,
          "quoteExactInputSingle",
          "0x#{'c' * 40}",
          PriceOracleService::USDC_TOKEN,
          PriceOracleService::POOL_FEE,
          10**18,
          0
        )
        expect(price).to eq(26.0)
      end

      it "converts USDC decimals (6) to float correctly" do
        allow(mock_client).to receive(:call).and_return(25_500_000) # 25.5 USDC
        price = described_class.current_scc_price
        expect(price).to eq(25.5)
      end

      it "handles zero price from quoter" do
        allow(mock_client).to receive(:call).and_return(0)
        price = described_class.current_scc_price
        expect(price).to eq(0.0)
      end

      it "falls back to 25.5 on RPC timeout" do
        allow(mock_client).to receive(:call).and_raise(Timeout::Error, "execution expired")
        price = described_class.current_scc_price
        expect(price).to eq(25.5)
      end
    end
  end

  describe "constants" do
    it "defines QUOTER_ADDRESS as Ethereum address" do
      expect(PriceOracleService::QUOTER_ADDRESS).to start_with("0x")
      expect(PriceOracleService::QUOTER_ADDRESS.length).to eq(42)
    end

    it "defines USDC_TOKEN as Polygon address" do
      expect(PriceOracleService::USDC_TOKEN).to start_with("0x")
      expect(PriceOracleService::USDC_TOKEN.length).to eq(42)
    end

    it "defines POOL_FEE as 3000 (0.3%)" do
      expect(PriceOracleService::POOL_FEE).to eq(3000)
    end

    it "reads scc_token_address from ENV at runtime (S1 — was a broken '0x...' placeholder)" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("CARBON_COIN_CONTRACT_ADDRESS").and_return("0x#{'a' * 40}")
      expect(described_class.scc_token_address).to eq("0x#{'a' * 40}")
    end

    it "defines RPC_TIMEOUT_SECONDS" do
      expect(PriceOracleService::RPC_TIMEOUT_SECONDS).to eq(15)
    end
  end
end
