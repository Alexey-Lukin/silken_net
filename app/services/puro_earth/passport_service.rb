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
    rescue StandardError => e
      raise AnchoringError, "Puro.earth passport anchoring failed: #{e.message}"
    end

    private

    # Serializes payload to canonical JSON (deterministic key ordering)
    # and computes its SHA-256 digest. This ensures the same payload
    # always produces the same hash, regardless of Hash insertion order.
    def compute_payload_hash
      canonical = JSON.generate(deep_sort_keys(@payload))
      Digest::SHA256.hexdigest(canonical)
    end

    def submit_anchor_transaction(payload_hash)
      client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
      signing_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

      contract = Eth::Contract.from_abi(
        name: "PuroEarthRegistry",
        address: ENV.fetch("PURO_EARTH_REGISTRY_CONTRACT_ADDRESS"),
        abi: REGISTRY_ABI
      )

      tree_did = @payload[:tree_did].to_s
      hash_bytes32 = "0x#{payload_hash}"

      client.transact(
        contract, "anchorPassport", tree_did, hash_bytes32,
        sender_key: signing_key, legacy: false
      )
    end

    # Recursively sorts hash keys for canonical JSON serialization.
    # Ensures deterministic output regardless of Ruby Hash insertion order.
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
