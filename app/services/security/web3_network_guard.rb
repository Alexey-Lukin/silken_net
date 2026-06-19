# frozen_string_literal: true

# [A1/A2] Pure content-judge for unsafe Web3 wiring. Mirrors
# `Security::WeakKeyDetector`: `.violations(env)` returns an array of
# human-readable strings (empty = safe); the companion initializer
# (`config/initializers/web3_network_guard.rb`) decides WHEN to enforce
# (production / WEB3_STRICT_MODE) and raises `SecurityError`.
#
# A1 — chain identity. A mainnet/canopy deploy pointed at a TESTNET RPC
#   (Polygon Amoy, Solana devnet, Sepolia…) mints real economic value on a
#   throwaway chain. There is NO chain-id constant in the code, so the realistic
#   misconfiguration — an `*_RPC_URL` left on a testnet host — is caught by a
#   host/marker scan. A live `eth_chainId` probe is deliberately NOT done at boot:
#   it would make booting depend on RPC liveness (an availability failure worse
#   than the config bug it guards). A runtime chain-id assertion can layer on later.
#
# A2 — oracle signer keys. BlockchainMintingService / BlockchainBurningService
#   resolve their signer via `ENV.fetch("ORACLE_MINTER_PRIVATE_KEY") {
#   ENV.fetch("ORACLE_PRIVATE_KEY") }` (+ the SLASHER variant). A missing key
#   raises KeyError deep inside a Sidekiq worker → the job lands in the DeadSet
#   silently. Resolve + format-check at boot instead.
module Security
  module Web3NetworkGuard
    module_function

    # EVM + Solana RPC vars whose URL must be a mainnet endpoint in a strict deploy.
    RPC_URL_ENVS = %w[
      ALCHEMY_ETHEREUM_RPC_URL
      ALCHEMY_POLYGON_RPC_URL
      POLYGON_RPC_URL
      CELO_RPC_URL
      SOLANA_RPC_URL
    ].freeze

    # Testnet host/path markers, alnum-boundary-anchored so a mainnet URL can't
    # match by coincidence (a random API-key token never trips it).
    TESTNET_MARKER =
      /(?<![a-z0-9])(?:amoy|mumbai|sepolia|goerli|holesky|ropsten|rinkeby|kovan|testnet|devnet)(?![a-z0-9])/i

    # secp256k1 private key: 32 bytes hex, optional 0x prefix.
    HEX64 = /\A(?:0x)?[0-9a-fA-F]{64}\z/

    ORACLE_KEY_ENVS = %w[ORACLE_PRIVATE_KEY ORACLE_MINTER_PRIVATE_KEY ORACLE_SLASHER_PRIVATE_KEY].freeze

    # Minting/slashing signer fallback chains (specific → ORACLE_PRIVATE_KEY).
    SIGNER_FALLBACKS = {
      "minting"  => "ORACLE_MINTER_PRIVATE_KEY",
      "slashing" => "ORACLE_SLASHER_PRIVATE_KEY"
    }.freeze

    # `env` defaults to ENV but is injectable for tests.
    def violations(env = ENV)
      chain_violations(env) + oracle_violations(env)
    end

    def chain_violations(env)
      RPC_URL_ENVS.filter_map do |var|
        url = env[var]
        next if url.blank?

        marker = url[TESTNET_MARKER]
        next unless marker

        "[A1] #{var} points at a TESTNET (matched #{marker.inspect}) — minting real " \
          "value on a testnet is unrecoverable. Point it at a mainnet endpoint."
      end
    end

    def oracle_violations(env)
      out = ORACLE_KEY_ENVS.filter_map do |var|
        key = env[var]
        next if key.blank? || key.match?(HEX64)

        "[A2] #{var} is set but is not a 32-byte hex secp256k1 key " \
          "(expected 64 hex chars, optional 0x) — Eth::Key would raise at signing time."
      end

      base = env["ORACLE_PRIVATE_KEY"]
      SIGNER_FALLBACKS.each do |role, specific_var|
        next if env[specific_var].present? || base.present?

        out << "[A2] No #{role} oracle key: neither #{specific_var} nor the " \
               "ORACLE_PRIVATE_KEY fallback is set — #{role} jobs would KeyError into the Sidekiq DeadSet."
      end

      out
    end
  end
end
