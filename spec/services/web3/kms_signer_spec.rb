# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "eth"
require "openssl"

RSpec.describe Web3::KmsSigner do
  let(:ec)   { OpenSSL::PKey::EC.generate("secp256k1") }
  let(:name) { "projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1" }
  let(:transport) do
    key = ec
    Class.new do
      define_method(:public_key_pem) { |_n| key.public_to_pem }
      define_method(:asymmetric_sign) { |_n, digest| key.dsa_sign_asn1(digest) }
    end.new
  end
  let(:signer)   { described_class.new(name, transport: transport) }
  let(:client)   { instance_double(Eth::Client) }
  let(:contract) { instance_double(Eth::Contract) }
  let(:expected_address) { Eth::Util.public_key_to_address(ec.public_key.to_bn(:uncompressed).to_s(2)).to_s }

  it "is a KeySigner — the same surface every money service already talks to" do
    expect(signer).to be_a(Web3::KeySigner)
  end

  # 🔴 Verbatim and stable: the value is interpolated into `lock:web3:oracle:<addr>` (ARCH.47).
  it "exposes the HSM address as the very same Eth::Address object every call" do
    aggregate_failures do
      expect(signer.address.to_s).to eq(expected_address)
      expect(signer.address).to equal(signer.address)
    end
  end

  it "hands the KmsKey to client.transact as sender_key with every kwarg untouched" do
    allow(client).to receive(:transact).and_return("0x#{'f' * 64}")

    signer.transact(client, contract, "batchMint", [ "0x#{'b' * 40}" ], [ 1 ], nonce: 7, legacy: false)

    expect(client).to have_received(:transact)
      .with(contract, "batchMint", [ "0x#{'b' * 40}" ], [ 1 ],
            sender_key: an_instance_of(Web3::KmsKey), nonce: 7, legacy: false)
  end

  it "simulates with from: = the HSM address, checksummed (the dry-run is onlyRole-gated)" do
    allow(client).to receive(:call).and_return(0)

    signer.static_call(client, contract, "batchMint", [ "0x#{'b' * 40}" ], [ 1 ])

    expect(client).to have_received(:call)
      .with(contract, "batchMint", [ "0x#{'b' * 40}" ], [ 1 ], from: expected_address)
  end
end
