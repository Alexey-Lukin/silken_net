# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "eth"

RSpec.describe Web3::LocalEnvSigner do
  let(:private_key) { "0x#{'a' * 64}" }
  let(:address)     { Eth::Address.new("0x#{'d' * 40}") }
  let(:key_double)  { instance_double(Eth::Key, address: address) }
  let(:client)      { instance_double(Eth::Client) }
  let(:contract)    { instance_double(Eth::Contract) }

  before { allow(Eth::Key).to receive(:new).and_return(key_double) }

  describe "#initialize" do
    it "derives the key from the supplied hex private key" do
      described_class.new(private_key)

      expect(Eth::Key).to have_received(:new).with(priv: private_key)
    end

    # ⛔ Eth::Key.new(priv: nil) does NOT raise — it silently generates a RANDOM pair,
    # i.e. a blank/forgotten ENV would yield a valid signer on a foreign, zero-balance
    # address (and move the ARCH.47 lock key on every restart).
    it "raises ArgumentError on a blank key instead of letting Eth::Key generate a random pair" do
      aggregate_failures do
        expect { described_class.new(nil) }.to raise_error(ArgumentError, /ВИПАДКОВУ/)
        expect { described_class.new("") }.to raise_error(ArgumentError, /ВИПАДКОВУ/)
        expect { described_class.new("   ") }.to raise_error(ArgumentError, /ВИПАДКОВУ/)
        expect(Eth::Key).not_to have_received(:new)
      end
    end
  end

  describe "#address" do
    # 🔴 Verbatim, not normalised: the value is interpolated into `lock:web3:oracle:<addr>`,
    # the ARCH.47 nonce-serialisation point. A `.to_s`/`.downcase` would MOVE that lock key
    # and let two workers take different locks on the same signer.
    it "returns Eth::Key#address as the very same object" do
      expect(described_class.new(private_key).address).to equal(address)
    end
  end

  describe "#transact" do
    it "forwards to client.transact with sender_key plus every kwarg untouched" do
      allow(client).to receive(:transact).and_return("0x#{'f' * 64}")

      result = described_class.new(private_key).transact(
        client, contract, "storeStateRoot", "0x#{'1' * 64}",
        nonce: 7, legacy: false, gas_limit: 90_000,
        max_fee_per_gas: 30_000_000_000, max_priority_fee_per_gas: 2_000_000_000
      )

      aggregate_failures do
        expect(client).to have_received(:transact).with(
          contract, "storeStateRoot", "0x#{'1' * 64}",
          sender_key: key_double, nonce: 7, legacy: false, gas_limit: 90_000,
          max_fee_per_gas: 30_000_000_000, max_priority_fee_per_gas: 2_000_000_000
        )
        expect(result).to eq("0x#{'f' * 64}")
      end
    end
  end

  describe "#static_call" do
    # `Eth::Client#call` never reads sender_key — it is inert here and forwarded anyway:
    # dropping it would be a real behaviour change smuggled inside a seam commit.
    it "forwards to client.call with the inert sender_key preserved" do
      allow(client).to receive(:call).and_return(0)

      result = described_class.new(private_key)
        .static_call(client, contract, "batchMint", [ "0x#{'b' * 40}" ], [ 1 ])

      aggregate_failures do
        expect(client).to have_received(:call)
          .with(contract, "batchMint", [ "0x#{'b' * 40}" ], [ 1 ], sender_key: key_double)
        expect(result).to eq(0)
      end
    end
  end

  # RpcConnectionPool.client_for is a per-thread cache — a signer holding a client would
  # duplicate that cache and survive `reset!`. The client is a per-call parameter.
  it "takes the client per call rather than holding one" do
    other_client = instance_double(Eth::Client)
    allow(client).to receive(:transact).and_return("0x#{'f' * 64}")
    allow(other_client).to receive(:call).and_return(1)

    signer = described_class.new(private_key)
    signer.transact(client, contract, "mint")
    signer.static_call(other_client, contract, "balanceOf")

    aggregate_failures do
      expect(client).to have_received(:transact).with(contract, "mint", sender_key: key_double)
      expect(other_client).to have_received(:call).with(contract, "balanceOf", sender_key: key_double)
    end
  end
end
