# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "eth"
require "openssl"
require "googleauth"

# [SEC.17] The crypto layer of the Cloud-KMS signer, offline. The fake HSM is a LOCAL OpenSSL
# secp256k1 key: its DER is real DER and its `s` is NOT normalised — exactly what Cloud KMS
# returns — so every branch of `#sign` runs against genuine shapes (INTEGERs with and without
# the leading 0x00, high-s needing negation, both recovery parities) instead of a canned hex.
# Live round-trip against the HSM = deploy-verify (06_04 §5.5).
RSpec.describe Web3::KmsKey do
  let(:ec)   { OpenSSL::PKey::EC.generate("secp256k1") }
  let(:name) { "projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1" }
  let(:fake_hsm_class) do
    Class.new do
      attr_reader :last_der

      def initialize(ec)
        @ec = ec
      end

      def public_key_pem(_name) = @ec.public_to_pem

      def asymmetric_sign(_name, digest) = (@last_der = @ec.dsa_sign_asn1(digest))
    end
  end
  let(:transport)  { fake_hsm_class.new(ec) }
  let(:kms)        { described_class.new(name, transport: transport) }
  let(:public_hex) { Eth::Util.bin_to_hex(ec.public_key.to_bn(:uncompressed).to_s(2)) }

  def raw_s(der)
    OpenSSL::ASN1.decode(der).value.last.value.to_i
  end

  describe "#address" do
    it "derives the address from the HSM public key and memoises the very same object (ARCH.47 lock key)" do
      expected = Eth::Util.public_key_to_address(ec.public_key.to_bn(:uncompressed).to_s(2))

      aggregate_failures do
        expect(kms.address.to_s).to eq(expected.to_s)
        expect(kms.address).to equal(kms.address)
      end
    end

    it "refuses a key that is not secp256k1 (a P-256 version would sign, and nothing on-chain would verify)" do
      p256 = OpenSSL::PKey::EC.generate("prime256v1")
      wrong = described_class.new(name, transport: fake_hsm_class.new(p256))

      expect { wrong.address }.to raise_error(described_class::SignatureError, /not secp256k1/)
    end

    it "refuses a blank key-version name" do
      expect { described_class.new("", transport: transport) }.to raise_error(ArgumentError, /blank/)
    end

    it "refuses a key that is not an EC key at all (an RSA version has no curve to name)" do
      rsa = OpenSSL::PKey::RSA.new(1024)
      pem_only = Class.new do
        define_method(:public_key_pem) { |_n| rsa.public_to_pem }
        define_method(:asymmetric_sign) { |_n, _d| raise "unreachable" }
      end.new

      expect { described_class.new(name, transport: pem_only).address }
        .to raise_error(described_class::SignatureError, /not secp256k1 \(nil\)/)
    end
  end

  describe "#sign" do
    # 32 digests × 3 chain forms — enough that the un-normalised HSM has produced BOTH a high-s
    # signature (needs negation) and BOTH recovery parities; each is asserted, not assumed.
    it "yields r‖s‖v that recovers to the HSM key, always low-s, on legacy and EIP-155 chains" do
      high_s_seen = false
      parities = Set.new

      [ nil, 137, 80_002 ].each do |chain_id|
        32.times do
          digest = OpenSSL::Random.random_bytes(32)
          signature = kms.sign(digest, chain_id)
          high_s_seen ||= raw_s(transport.last_der) > described_class::HALF_N
          r, s, v = Eth::Signature.dissect(signature)

          aggregate_failures do
            expect(signature.size).to be >= 130
            expect(r.size).to eq(64)
            expect(s.to_i(16)).to be <= described_class::HALF_N
            expect(Eth::Signature.recover(digest, signature, chain_id || Eth::Chain::ETHEREUM)).to eq(public_hex)
          end
          parities << Eth::Chain.to_recovery_id(v.to_i(16), chain_id || Eth::Chain::ETHEREUM)
        end
      end

      aggregate_failures do
        expect(high_s_seen).to be(true), "no high-s signature in 96 draws — the negation branch never ran"
        expect(parities).to eq(Set[0, 1])
      end
    end

    # The eth gem's own key on the SAME scalar: addresses must agree, and the v ENCODING (the part
    # `Eth::Tx` dissects positionally) must be byte-identical in width — r/s differ by design, the
    # HSM draws a random nonce while libsecp256k1 uses RFC 6979.
    it "matches Eth::Key on the same scalar: same address, same v encoding width on a wide chain id" do
      eth_key = Eth::Key.new(priv: ec.private_key.to_s(16).rjust(64, "0"))
      digest = OpenSSL::Random.random_bytes(32)

      aggregate_failures do
        expect(kms.address.to_s).to eq(eth_key.address.to_s)
        expect(kms.sign(digest, 137)[128..].size).to eq(eth_key.sign(digest, 137)[128..].size)
        expect(kms.sign(digest)[128..].size).to eq(eth_key.sign(digest)[128..].size)
      end
    end

    # The integration that matters: the eth gem builds, signs and re-decodes an EIP-1559 tx with
    # this object in the key seat — the exact path `Eth::Client#transact` takes on a mint.
    it "signs an Eth::Tx::Eip1559 that decodes back to the HSM address as sender" do
      tx = Eth::Tx.new(
        chain_id: 137, nonce: 0, priority_fee: 1_000_000_000, max_gas_fee: 30_000_000_000,
        gas_limit: 21_000, to: "0x#{'b' * 40}", value: 0
      )

      tx.sign(kms)
      decoded = Eth::Tx.decode(tx.hex)

      expect(Eth::Util.remove_hex_prefix(decoded.sender).downcase)
        .to eq(Eth::Util.remove_hex_prefix(kms.address.to_s).downcase)
    end

    it "refuses a digest that is not 32 bytes (the tx hash is the ONLY thing this signs)" do
      expect { kms.sign("x" * 31, 137) }.to raise_error(described_class::SignatureError, /32-byte/)
    end

    it "refuses an HSM answer that is not an ECDSA SEQUENCE { r, s }" do
      allow(transport).to receive(:asymmetric_sign).and_return("\x02\x01\x01".b)

      expect { kms.sign("d" * 32, 137) }.to raise_error(described_class::SignatureError, /SEQUENCE/)
    end

    it "refuses r/s outside the group order (a zero r is a well-formed SEQUENCE and a dead signature)" do
      der = OpenSSL::ASN1::Sequence.new([ OpenSSL::ASN1::Integer.new(0), OpenSSL::ASN1::Integer.new(1) ]).to_der
      allow(transport).to receive(:asymmetric_sign).and_return(der)

      expect { kms.sign("d" * 32, 137) }.to raise_error(described_class::SignatureError, /out of range/)
    end

    # The recovery search must survive a parity that does not even parse: secp256k1 raises on
    # an invalid recoverable signature instead of returning a foreign key, and the other parity
    # still has to be tried.
    it "keeps searching when the WRONG parity raises inside recovery instead of returning a foreign key" do
      raised = 0
      allow(Eth::Signature).to receive(:recover).and_wrap_original do |original, *args|
        result = original.call(*args)
        if result != public_hex
          raised += 1
          raise Eth::Signature::SignatureError, "synthetic: invalid recoverable signature"
        end
        result
      end

      # The parity order is fixed (0 then 1) and the HSM nonce is random, so the wrong parity
      # comes FIRST in about half the draws — 32 draws make that certain, and every draw must
      # still yield a signature that recovers to the key.
      32.times do
        digest = OpenSSL::Random.random_bytes(32)
        expect(Eth::Signature.recover(digest, kms.sign(digest, 137), 137)).to eq(public_hex)
        break if raised >= 1
      end

      expect(raised).to be >= 1
    end

    it "refuses undecodable DER" do
      allow(transport).to receive(:asymmetric_sign).and_return("\xff\xff".b)

      expect { kms.sign("d" * 32, 137) }.to raise_error(described_class::SignatureError, /undecodable/)
    end

    it "refuses a signature that recovers to a foreign key (an HSM answering for another version)" do
      other = OpenSSL::PKey::EC.generate("secp256k1")
      allow(transport).to receive(:asymmetric_sign) { |_n, digest| other.dsa_sign_asn1(digest) }

      expect { kms.sign("d" * 32, 137) }.to raise_error(described_class::SignatureError, /does not recover/)
    end
  end

  # The wire half: URL shape, the base64 digest field, the bearer header, the DER back.
  # Nothing here reaches the network — HttpClient and ADC are doubles.
  describe Web3::KmsKey::RestTransport do
    let(:name) { "projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1" }
    let(:credentials) { instance_double(Google::Auth::GCECredentials) }
    let(:transport) { described_class.new }

    before do
      allow(Google::Auth).to receive(:get_application_default).with([ described_class::SCOPE ]).and_return(credentials)
      allow(credentials).to receive(:apply).with({}).and_return({ authorization: "Bearer tok" })
    end

    it "reads the PEM from {name}/publicKey with a bearer token" do
      response = Web3::HttpClient::Response.new({ pem: "-----BEGIN PUBLIC KEY-----\nabc\n" }.to_json)
      allow(Web3::HttpClient).to receive(:get).and_return(response)

      pem = transport.public_key_pem(name)

      aggregate_failures do
        expect(pem).to start_with("-----BEGIN PUBLIC KEY-----")
        expect(Web3::HttpClient).to have_received(:get)
          .with("#{described_class::BASE_URL}#{name}/publicKey",
                headers: { "Authorization" => "Bearer tok" }, service_name: "KMS")
      end
    end

    it "POSTs the digest base64 under digest.sha256 to {name}:asymmetricSign and returns the DER" do
      der = "\x30\x06\x02\x01\x01\x02\x01\x01".b
      response = Web3::HttpClient::Response.new({ signature: Base64.strict_encode64(der) }.to_json)
      allow(Web3::HttpClient).to receive(:post).and_return(response)
      digest = "d" * 32

      aggregate_failures do
        expect(transport.asymmetric_sign(name, digest)).to eq(der)
        expect(Web3::HttpClient).to have_received(:post)
          .with("#{described_class::BASE_URL}#{name}:asymmetricSign",
                body: { digest: { sha256: Base64.strict_encode64(digest) } },
                headers: { "Authorization" => "Bearer tok" }, service_name: "KMS")
      end
    end

    it "resolves ADC once per transport (the token cache lives in googleauth, not here)" do
      allow(Web3::HttpClient).to receive(:get).and_return(Web3::HttpClient::Response.new({ pem: "x" }.to_json))

      2.times { transport.public_key_pem(name) }

      expect(Google::Auth).to have_received(:get_application_default).once
    end
  end
end
