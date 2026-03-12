# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web3::WeiConverter do
  describe ".to_wei" do
    it "converts integer amounts to wei" do
      expect(described_class.to_wei(1)).to eq(10**18)
      expect(described_class.to_wei(100)).to eq(100 * 10**18)
    end

    it "converts string amounts to wei with BigDecimal precision" do
      expect(described_class.to_wei("0.5")).to eq(5 * 10**17)
      expect(described_class.to_wei("0.000000000000000001")).to eq(1)
    end

    it "converts float amounts without precision loss" do
      # Float.to_f * 10**18 would give drift — BigDecimal prevents this
      result = described_class.to_wei(1_000_000)
      expect(result).to eq(1_000_000 * 10**18)
    end

    it "handles zero" do
      expect(described_class.to_wei(0)).to eq(0)
      expect(described_class.to_wei("0")).to eq(0)
    end

    it "supports custom decimals (e.g., USDC = 6)" do
      expect(described_class.to_wei(1, 6)).to eq(1_000_000)
      expect(described_class.to_wei("0.5", 6)).to eq(500_000)
    end

    it "returns Integer" do
      expect(described_class.to_wei(1)).to be_a(Integer)
    end
  end
end
