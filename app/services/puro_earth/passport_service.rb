# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"
require "digest"
require "json"

module PuroEarth
  # =========================================================================
  # 🌿 BIOMASS PASSPORT ANCHORING SERVICE (D-MRV Registry on Polygon)
  # =========================================================================
  # Anchors a cryptographic proof of a Biomass Passport onto Polygon.
  # This is the final link in the D-MRV (Digital Measurement, Reporting
  # and Verification) chain for Puro.earth CORC (CO2 Removal Certificate)
  # generation from Biochar.
  #
  # The service:
  # 1. Serializes the passport payload into canonical JSON (sorted keys)
  # 2. Computes a SHA-256 hash as a tamper-proof fingerprint
  # 3. Sends anchorPassport(treeDid, payloadHash) to the D-MRV Registry
  #    smart contract on Polygon
  # 4. Returns the real tx_hash for immutable on-chain provenance
  #
  # Pattern: follows Ethereum::StateAnchorService (bytes32 anchoring)
  # and Etherisc::ClaimService (Polygon transact fire-and-forget).
  #
  # Usage:
  #   tx_hash = PuroEarth::PassportService.new(payload).anchor!
  # =========================================================================
  class PassportService
    class AnchoringError < StandardError; end

    # Wei-style multiplier (10^18) for scaling decimal values to deterministic integers.
    # Matches the encoding convention used across the SilkenNet protocol.
    ABI_DECIMAL_SCALE = BigDecimal("1000000000000000000")

    # D-MRV Registry ABI — stores the cryptographic proof of each Biomass Passport.
    # anchorPassport(string treeDid, bytes32 payloadHash):
    #   - treeDid: the device identity string (e.g., "did:peaq:0x...")
    #   - payloadHash: SHA-256 digest of the canonical JSON payload (bytes32)
    REGISTRY_ABI = [
      {
        "inputs" => [
          { "internalType" => "string", "name" => "treeDid", "type" => "string" },
          { "internalType" => "bytes32", "name" => "payloadHash", "type" => "bytes32" }
        ],
        "name" => "anchorPassport",
        "outputs" => [],
        "stateMutability" => "nonpayable",
        "type" => "function"
      }
    ].to_json

    def initialize(payload)
      @payload = payload
    end

    # Anchors the Biomass Passport on-chain and returns the transaction hash.
    #
    # @return [String] tx_hash (format "0x...")
    # @raise [AnchoringError] on RPC failure, insufficient gas, or contract revert
    def anchor!
      payload_hash = compute_payload_hash

      # [ON-CHAIN ANCHORING]
      tx_hash = submit_anchor_transaction(payload_hash)

      Rails.logger.info "🌿 [Puro.earth] Passport anchored on-chain. " \
                        "Tree: #{@payload[:tree_did]}, hash: #{payload_hash}, TX: #{tx_hash}"

      tx_hash
    rescue Kredis::LockTimeout
      raise # lock не взято → transact не виконувався → чистий Sidekiq-retry, НЕ AnchoringError
    rescue StandardError => e
      raise AnchoringError, "Puro.earth passport anchoring failed: #{e.message}"
    end

    private

    # Computes a deterministic payload hash using ABI encoding for cross-platform reproducibility.
    # ABI encoding produces a canonical binary representation defined by the EVM specification,
    # eliminating Ruby-specific JSON serialization quirks (float formatting, unicode escaping,
    # key ordering). The hash is reproducible across any language with an ABI encoder.
    #
    # Canonical fields are extracted in a fixed order (alphabetical by key name) and typed
    # explicitly to match the Solidity-level verification signature. This ensures the same
    # payload always produces the same bytes32 hash regardless of Hash insertion order.
    def compute_payload_hash
      types, values = extract_canonical_fields(@payload)
      encoded = Eth::Abi.encode(types, values)
      Digest::SHA256.hexdigest(encoded)
    end

    def submit_anchor_transaction(payload_hash)
      client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
      # [INF.22] Dedicated Puro-підписант (легасі спільний ORACLE_PRIVATE_KEY retired) —
      # E.2-ізоляція blast-radius. Ключ інжектиться при активації passport-шляху (06_04 §2.1).
      # [SEC.17] Деривація — через seam `Web3::OracleSigner` (ENV-дефолт незмінний).
      signer = Web3::OracleSigner.for(:puro)

      contract = Eth::Contract.from_abi(
        name: "PuroEarthRegistry",
        address: ENV.fetch("PURO_EARTH_REGISTRY_CONTRACT_ADDRESS"),
        abi: REGISTRY_ABI
      )

      tree_did = @payload[:tree_did].to_s
      hash_bytes32 = "0x#{payload_hash}"

      # [ARCH.49] Per-address nonce-serialization: eth-gem бере nonce per-call → конкурентні
      # підписи на одній адресі колізять nonce. Після dedicated-спліту [INF.22] адреса своя,
      # тож lock серіалізує лише конкурентні Puro-anchors. LockTimeout пробрасується
      # крізь anchor! (re-raise перед StandardError) для чистого Sidekiq-retry.
      tx_hash = nil
      lock_key = "lock:web3:oracle:#{signer.address}"
      Kredis.lock(lock_key, expires_in: 30.seconds, after_timeout: :raise) do
        tx_hash = signer.transact(
          client, contract, "anchorPassport", tree_did, hash_bytes32,
          legacy: false
        )
      end
      tx_hash
    end

    # Extracts payload fields in alphabetical key order with explicit ABI types.
    # Flattens nested hashes using dot-notation keys (e.g., gps_coordinates.latitude).
    # All values are coerced to ABI-compatible types:
    #   - Strings → "string"
    #   - Numerics with decimals → scaled to uint256 (×10^18 for precision)
    #   - Integers → "uint256"
    def extract_canonical_fields(hash, prefix: nil)
      types = []
      values = []

      hash.sort_by { |k, _| k.to_s }.each do |key, value|
        full_key = prefix ? "#{prefix}.#{key}" : key.to_s

        case value
        when Hash
          nested_types, nested_values = extract_canonical_fields(value, prefix: full_key)
          types.concat(nested_types)
          values.concat(nested_values)
        when Integer
          types << "uint256"
          values << value
        when Float, BigDecimal
          types << "uint256"
          values << (BigDecimal(value.to_s) * ABI_DECIMAL_SCALE).to_i
        else
          types << "string"
          values << value.to_s
        end
      end

      [ types, values ]
    end

    # Recursively sorts hash keys for canonical JSON serialization.
    # Retained for backward compatibility — used by external callers if needed.
    def deep_sort_keys(obj)
      case obj
      when Hash
        obj.sort_by { |k, _| k.to_s }.to_h.transform_values { |v| deep_sort_keys(v) }
      when Array
        obj.map { |v| deep_sort_keys(v) }
      else
        obj
      end
    end
  end
end
