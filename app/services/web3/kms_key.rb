# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "openssl"
require "base64"
require "eth"

module Web3
  # =========================================================================
  # 🔐 KMS KEY (SEC.17 — an Eth::Key-shaped handle on a Cloud KMS HSM key)
  # =========================================================================
  # Duck-types exactly the two methods the eth gem touches on the transact
  # path (`#address`, `#sign(blob, chain_id)` — measured against eth 0.5.17,
  # 06_04 §5.5): the private key never leaves the HSM; this object sends a
  # 32-byte digest and turns the DER answer into the `r‖s‖v` hex that
  # `Eth::Tx::Eip1559#sign` dissects. Algorithm `EC_SIGN_SECP256K1_SHA256`,
  # addressed per key VERSION.
  #
  # 🔑 `blob` IS the hash. `Eth::Tx#sign` passes `unsigned_hash` — keccak-256
  # of the RLP — and `Eth::Key#sign` feeds those 32 bytes straight to
  # secp256k1. KMS signs the 32 bytes it is handed and never re-hashes: the
  # request field is called `digest.sha256` because the algorithm NAME says
  # SHA-256, but the value is our keccak hash. ⛔ Do not hash it again here.
  #
  # ⚠️ Two things the HSM does NOT do, both done here: it does not normalise
  # `s` (EIP-2 demands the low half, else `ecrecover` rejects the tx) and it
  # returns no recovery id (found by recovering both parities against OUR
  # public key — after the normalisation, which may flip the parity).
  #
  # Transport is injected: the REST default talks to `cloudkms.googleapis.com`
  # under a `googleauth` ADC token (no grpc — the gem is already in the lock);
  # specs inject a fake HSM built on a local OpenSSL secp256k1 key, which
  # yields real DER and real high-s signatures — the shapes the HSM returns.
  # =========================================================================
  class KmsKey
    class SignatureError < StandardError; end

    # secp256k1 group order; EIP-2 low-s ⇔ s <= N/2.
    N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
    HALF_N = N / 2

    attr_reader :key_version_name

    # @param key_version_name [String] `projects/…/cryptoKeys/…/cryptoKeyVersions/N`
    # @param transport [#public_key_pem, #asymmetric_sign]
    def initialize(key_version_name, transport: RestTransport.new)
      raise ArgumentError, "KMS key version name is blank" if key_version_name.blank?

      @key_version_name = key_version_name
      @transport = transport
    end

    # Memoised — the SAME `Eth::Address` object every call, for the reason
    # `KeySigner#address` names (the ARCH.47 lock key interpolates it).
    def address
      @address ||= Eth::Util.public_key_to_address(public_key_bytes)
    end

    # Uncompressed point, 65 bytes (0x04‖X‖Y) — the form `Eth::Signature.recover` returns.
    def public_key_bytes
      @public_key_bytes ||= begin
        ec = OpenSSL::PKey.read(@transport.public_key_pem(@key_version_name))
        curve = ec.respond_to?(:group) ? ec.group.curve_name : nil
        raise SignatureError, "KMS key #{@key_version_name} is not secp256k1 (#{curve.inspect})" unless curve == "secp256k1"

        ec.public_key.to_bn(:uncompressed).to_s(2)
      end
    end

    # Same contract as `Eth::Key#sign`: hex of r(32)‖s(32)‖v with
    # v = `Chain.to_v(recovery_id, chain_id)` encoded big-endian without leading
    # zero bytes — byte-identical to the gem's own encoding, which `Eth::Tx`
    # dissects positionally.
    # @param blob [String] the 32-byte binary digest (the keccak hash — see the header)
    def sign(blob, chain_id = nil)
      size = blob.to_s.bytesize
      raise SignatureError, "expected a 32-byte digest, got #{size} bytes" unless size == 32

      r, s = decode_der(@transport.asymmetric_sign(@key_version_name, blob))
      s = N - s if s > HALF_N
      rs_hex = format("%064x%064x", r, s)
      recovery_id = recovery_id_for(blob, rs_hex, chain_id)
      rs_hex + Eth::Util.bin_to_hex(v_bytes(Eth::Chain.to_v(recovery_id, chain_id)))
    end

    private

    # ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER }. OpenSSL's decoder
    # owns the DER edges (short/long length forms, the leading 0x00 of a
    # positive INTEGER); only the shape and the range are judged here.
    def decode_der(der)
      seq = OpenSSL::ASN1.decode(der)
      ints = seq.is_a?(OpenSSL::ASN1::Sequence) ? seq.value : []
      unless ints.size == 2 && ints.all?(OpenSSL::ASN1::Integer)
        raise SignatureError, "KMS returned a signature that is not an ECDSA SEQUENCE { r, s }"
      end

      r, s = ints.map { |i| i.value.to_i }
      raise SignatureError, "KMS signature r/s out of range" unless (1...N).cover?(r) && (1...N).cover?(s)

      [ r, s ]
    rescue OpenSSL::ASN1::ASN1Error => e
      raise SignatureError, "KMS returned undecodable DER: #{e.message}"
    end

    # The HSM returns no recovery id: try both parities and keep the one that
    # recovers OUR key. Searching AFTER the low-s normalisation is what makes
    # the parity flip that normalisation may cause harmless.
    def recovery_id_for(blob, rs_hex, chain_id)
      expected = Eth::Util.bin_to_hex(public_key_bytes)
      found = [ 0, 1 ].find do |rid|
        v_hex = Eth::Util.bin_to_hex(v_bytes(Eth::Chain.to_v(rid, chain_id)))
        Eth::Signature.recover(blob, rs_hex + v_hex, chain_id || Eth::Chain::ETHEREUM) == expected
      rescue Secp256k1::Error, Eth::Signature::SignatureError
        false
      end
      found || raise(SignatureError, "KMS signature does not recover to #{address}")
    end

    def v_bytes(v)
      [ v ].pack("Q>").sub(/\A\0+/n, "")
    end

    # REST transport — `cloudkms.googleapis.com/v1/{name}` under an ADC bearer
    # token (`googleauth`, already in the lock: no grpc extension). On the VM
    # the token comes from the metadata server as the deploy SA, which is
    # exactly why the VM needs the `cloud-platform` OAuth scope (00_07 SEC.17
    # 👤): with `logging-write`/`monitoring-write` only, the token carries no
    # KMS scope and every call is 403 regardless of IAM. Goes through
    # `Web3::HttpClient` for its pool + circuit breaker — an open circuit
    # raises, the job retries, nothing signs blind.
    class RestTransport
      BASE_URL = "https://cloudkms.googleapis.com/v1/"
      SCOPE = "https://www.googleapis.com/auth/cloudkms"
      SERVICE_NAME = "KMS"

      def public_key_pem(name)
        Web3::HttpClient.get("#{BASE_URL}#{name}/publicKey", headers: auth_headers, service_name: SERVICE_NAME)
                        .parsed_body.fetch("pem")
      end

      # @param digest [String] 32 binary bytes — the keccak hash (see the KmsKey header)
      def asymmetric_sign(name, digest)
        response = Web3::HttpClient.post("#{BASE_URL}#{name}:asymmetricSign",
                                         body: { digest: { sha256: Base64.strict_encode64(digest) } },
                                         headers: auth_headers, service_name: SERVICE_NAME)
        Base64.strict_decode64(response.parsed_body.fetch("signature"))
      end

      private

      # `apply` refreshes the cached token only when it is missing or about to
      # expire (googleauth `BaseClient#apply!`), so one transport = one token.
      def auth_headers
        require "googleauth"
        @credentials ||= Google::Auth.get_application_default([ SCOPE ])
        { "Authorization" => @credentials.apply({}).fetch(Google::Auth::BaseClient::AUTH_METADATA_KEY) }
      end
    end
  end
end
