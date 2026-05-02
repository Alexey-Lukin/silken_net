# frozen_string_literal: true

module Web3
  # Registry of supported Chainlink Functions Router ABI versions.
  #
  # [S6.15]: Locks the ABI Chainlink::OracleDispatchService submits requests
  # against to a known versioned shape so that:
  #
  #   1. Any future Router upgrade (v2, v3, ...) requires an explicit
  #      registry entry and a code review — no silent ABI drift.
  #   2. Boot-time health check can compare the *expected* `sendRequest`
  #      keccak256 selector against the deployed Router contract's bytecode
  #      and refuse to dispatch when they diverge.
  #   3. The dispatcher can gracefully fall back to a previous registered
  #      version if the active one cannot be confirmed against the
  #      on-chain contract (e.g. during a Router upgrade window).
  #
  # Each entry holds:
  #   - `:abi`         — JSON-serialisable Array of ABI items.
  #   - `:selector`    — first 4 bytes of `keccak256("sendRequest(...)")`
  #                     hex-encoded with the `0x` prefix. Used by the
  #                     bytecode health check to confirm the contract
  #                     exposes the expected entrypoint.
  #   - `:signature`   — canonical Solidity signature, kept for diagnostics
  #                     and for emitting clear errors during version
  #                     mismatch.
  #
  # The active version is selected via `CHAINLINK_ROUTER_VERSION` ENV
  # (defaults to `:v1`). `Web3::ChainlinkRouterVersion.fallback_for(version)`
  # returns the previous registered version (or `nil` if none) so that
  # the dispatcher can attempt a graceful retry.
  module ChainlinkRouterVersion
    class UnsupportedVersionError < StandardError; end
    class MissingAbiError < StandardError; end

    # Ordered chronologically — earliest version first. Used to compute
    # the fallback chain (current → previous → ... → oldest).
    VERSION_ORDER = %i[v1].freeze

    # `sendRequest` selector for Chainlink Functions Router v1
    # (Polygon mainnet). Verified against
    # https://docs.chain.link/chainlink-functions/api-reference/functions-router
    # canonical signature:
    #   sendRequest(uint64,bytes,uint16,uint32,bytes32) → bytes32
    #
    # Selector = first 4 bytes of keccak256(canonical_signature).
    # Pre-computed at registry definition so we never depend on a digest
    # library at boot — the registry is a static constant truth.
    REGISTRY = {
      v1: {
        signature: "sendRequest(uint64,bytes,uint16,uint32,bytes32)",
        selector: "0x461d2762",
        abi: [
          {
            "inputs" => [
              { "internalType" => "uint64",  "name" => "subscriptionId",   "type" => "uint64" },
              { "internalType" => "bytes",   "name" => "data",             "type" => "bytes" },
              { "internalType" => "uint16",  "name" => "dataVersion",      "type" => "uint16" },
              { "internalType" => "uint32",  "name" => "callbackGasLimit", "type" => "uint32" },
              { "internalType" => "bytes32", "name" => "donId",            "type" => "bytes32" }
            ],
            "name" => "sendRequest",
            "outputs" => [ { "internalType" => "bytes32", "name" => "requestId", "type" => "bytes32" } ],
            "stateMutability" => "nonpayable",
            "type" => "function"
          }
        ].freeze
      }
    }.freeze

    DEFAULT_VERSION = :v1

    module_function

    # Returns the symbol of the configured router version, or DEFAULT_VERSION.
    # Raises UnsupportedVersionError if the ENV value is not in REGISTRY.
    def active_version
      raw = ENV["CHAINLINK_ROUTER_VERSION"].to_s.strip
      return DEFAULT_VERSION if raw.empty?

      sym = raw.downcase.to_sym
      unless REGISTRY.key?(sym)
        raise UnsupportedVersionError,
              "CHAINLINK_ROUTER_VERSION=#{raw.inspect} не підтримується. Зареєстровані: #{REGISTRY.keys.inspect}"
      end
      sym
    end

    def supported?(version)
      REGISTRY.key?(version)
    end

    def entry_for(version)
      REGISTRY[version] or raise UnsupportedVersionError,
                                "Невідома Chainlink Router версія #{version.inspect}"
    end

    # Returns the ABI array for the requested version (defaults to active).
    # Raises MissingAbiError if registry entry exists but ABI is blank.
    def abi_for(version = active_version)
      entry = entry_for(version)
      abi = entry[:abi]
      raise MissingAbiError, "ABI для Chainlink Router версії #{version.inspect} відсутній" if abi.blank?

      abi
    end

    def selector_for(version = active_version)
      entry_for(version).fetch(:selector)
    end

    def signature_for(version = active_version)
      entry_for(version).fetch(:signature)
    end

    # Returns the previous registered version (one step older), or nil
    # if `version` is already the oldest. Used by the dispatcher to
    # attempt a graceful retry when the active version selector cannot
    # be confirmed against the on-chain Router bytecode.
    def fallback_for(version)
      idx = VERSION_ORDER.index(version)
      return nil if idx.nil? || idx.zero?

      VERSION_ORDER[idx - 1]
    end

    # Boot-time health check: parse Router contract bytecode (via
    # `eth_getCode`) and verify the selector for `version` is present.
    #
    # Returns `true` if the selector is found in the bytecode, `false`
    # otherwise. A `nil` / blank `code_hex` (contract not deployed)
    # always returns `false` — caller decides whether that is fatal.
    #
    # Selector matching is hex-substring (case-insensitive) — selectors
    # appear as immediate operands of PUSH4 in the dispatch table.
    def selector_present_in_code?(code_hex, version = active_version)
      return false if code_hex.blank?

      hex = code_hex.to_s.downcase.delete_prefix("0x")
      needle = selector_for(version).to_s.downcase.delete_prefix("0x")
      return false if hex.empty? || needle.empty?

      hex.include?(needle)
    end
  end
end
