# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [INF.27] The read-path half of the chain axis. Two things are judged here and they are
# NOT the same thing: that the renderer picks the row its slot declares (behaviour), and
# that the two rows are actually on opposite sides of the axis (content). The second is the
# one a naive spec skips — and without it, collapsing both maps to identical templates would
# pass every behavioural example.
RSpec.describe Web3::Explorer do
  def with_chain_env(value)
    previous = ENV.fetch("WEB3_CHAIN_ENV", nil)
    value.nil? ? ENV.delete("WEB3_CHAIN_ENV") : ENV["WEB3_CHAIN_ENV"] = value
    yield
  ensure
    previous.nil? ? ENV.delete("WEB3_CHAIN_ENV") : ENV["WEB3_CHAIN_ENV"] = previous
  end

  let(:hash) { "0xabc123" }

  describe ".tx_url" do
    it "renders mainnet links when the slot declares mainnet" do
      with_chain_env("mainnet") do
        expect(described_class.tx_url(:evm, hash)).to eq("https://polygonscan.com/tx/0xabc123")
        expect(described_class.tx_url(:ethereum, hash)).to eq("https://etherscan.io/tx/0xabc123")
        expect(described_class.tx_url(:solana, hash)).to eq("https://explorer.solana.com/tx/0xabc123")
        expect(described_class.tx_url(:celo, hash)).to eq("https://celo.blockscout.com/tx/0xabc123")
      end
    end

    it "renders testnet links when the slot declares testnet" do
      with_chain_env("testnet") do
        expect(described_class.tx_url(:evm, hash)).to eq("https://amoy.polygonscan.com/tx/0xabc123")
        expect(described_class.tx_url(:ethereum, hash)).to eq("https://sepolia.etherscan.io/tx/0xabc123")
        expect(described_class.tx_url(:solana, hash))
          .to eq("https://explorer.solana.com/tx/0xabc123?cluster=devnet")
        expect(described_class.tx_url(:celo, hash)).to eq("https://celo-sepolia.blockscout.com/tx/0xabc123")
      end
    end

    # Absent → mainnet is the guard's own fail-closed default; keeping the SAME default here
    # means the link and the boot assertion can never disagree about which chain we are on.
    it "falls back to mainnet when the slot declares nothing" do
      with_chain_env(nil) do
        expect(described_class.tx_url(:evm, hash)).to eq("https://polygonscan.com/tx/0xabc123")
      end
    end

    # Unreachable through a normal boot (the guard refuses an unrecognised value) but reachable
    # through SILKENNET_SKIP_WEB3_NETWORK_GUARD=1 — and a KeyError while rendering a dashboard
    # row would be a worse failure than a wrong link.
    it "falls back to mainnet on an unrecognised declaration instead of raising" do
      with_chain_env("staging") do
        expect(described_class.tx_url(:ethereum, hash)).to eq("https://etherscan.io/tx/0xabc123")
      end
    end

    it "returns nil for a missing or blank hash" do
      with_chain_env("mainnet") do
        expect(described_class.tx_url(:evm, nil)).to be_nil
        expect(described_class.tx_url(:evm, "")).to be_nil
      end
    end
  end

  describe "the two rows are genuinely on opposite sides of the axis" do
    let(:marker) { Security::Web3NetworkGuard::TESTNET_MARKER }

    # 🔑 The discriminator is borrowed, not re-invented: this is the SAME regex the boot guard
    # uses to judge RPC URLs. One home for "what a testnet address looks like", now applied to
    # the read path as well — so a family added to only one side, or a mainnet template that
    # quietly names a testnet, reds here without anyone maintaining a second list.
    it "never names a testnet in the mainnet row" do
      offenders = described_class::TX_URL.fetch("mainnet").select { |_family, url| url.match?(marker) }
      expect(offenders).to be_empty, "mainnet templates matching TESTNET_MARKER: #{offenders.inspect}"
    end

    it "always names a testnet in the testnet row" do
      offenders = described_class::TX_URL.fetch("testnet").reject { |_family, url| url.match?(marker) }
      expect(offenders).to be_empty, "testnet templates NOT matching TESTNET_MARKER: #{offenders.inspect}"
    end

    it "covers the same families on both sides" do
      keys = described_class::TX_URL.values.map { |row| row.keys.sort }
      expect(keys.uniq.size).to eq(1), "family sets diverge: #{described_class::TX_URL.transform_values(&:keys)}"
      expect(keys.first).to eq(%i[celo ethereum evm solana])
    end

    # ⚠️ Size pin, not decoration: every example above is vacuous on an empty or half-filled
    # map, and "no offenders" is the shape that goes green loudest when the set is empty.
    it "judges a non-empty map on both sides" do
      expect(described_class::TX_URL.keys).to contain_exactly("mainnet", "testnet")
      described_class::TX_URL.each_value { |row| expect(row.size).to eq(4) }
    end
  end
end
