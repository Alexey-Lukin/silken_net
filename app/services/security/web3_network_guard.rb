# frozen_string_literal: true

# Pure content-judge for unsafe Web3 wiring. Mirrors
# `Security::WeakKeyDetector`: `.violations(env)` returns an array of
# human-readable strings (empty = safe); the companion initializer
# (`config/initializers/web3_network_guard.rb`) decides WHEN to enforce
# (production / WEB3_STRICT_MODE) and raises `SecurityError`.
#
# Chain identity. A mainnet/canopy deploy pointed at a TESTNET RPC
#   (Polygon Amoy, Solana devnet, Sepolia…) mints real economic value on a
#   throwaway chain. There is NO chain-id constant in the code, so the realistic
#   misconfiguration — an `*_RPC_URL` left on a testnet host — is caught by a
#   host/marker scan. A live `eth_chainId` probe is deliberately NOT done at boot:
#   it would make booting depend on RPC liveness (an availability failure worse
#   than the config bug it guards). A runtime chain-id assertion can layer on later.
#
# Oracle signer keys. BlockchainMintingService / BlockchainBurningService
#   resolve their signer via `ENV.fetch("ORACLE_MINTER_PRIVATE_KEY") {
#   ENV.fetch("ORACLE_PRIVATE_KEY") }` (+ the SLASHER variant). A missing key
#   raises KeyError deep inside a Sidekiq worker → the job lands in the DeadSet
#   silently. Resolve + format-check at boot instead. A second failure mode
#   (ARCH.47): minting and slashing resolving to the SAME key — a shared
#   ORACLE_PRIVATE_KEY fallback or identical MINTER/SLASHER keys — collide on one
#   Kredis oracle lock and serialize mint↔slash, so a 120s mint stalls a
#   time-sensitive slash (and a LockTimeout there silently aborts the burn,
#   ARCH.48). E.2 (canon 07_01 §B-02) mandates physically separate keys; the
#   fallback is legacy-only, so a strict boot also refuses an address collision.
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
    # `signer_process:` scopes the key-PRESENCE requirement to processes that
    # actually sign (Sidekiq). The web/coap containers never hold money keys
    # (plaintext-ENV exposure on an untrusted Akash provider), so demanding
    # presence there would force keys BACK onto the widest attack surface.
    # Format and collision checks still run everywhere a key IS present.
    def violations(env = ENV, signer_process: true)
      chain_violations(env) + oracle_violations(env, signer_process: signer_process)
    end

    def chain_violations(env)
      RPC_URL_ENVS.filter_map do |var|
        url = env[var]
        next if url.blank?

        marker = url[TESTNET_MARKER]
        next unless marker

        "[chain] #{var} points at a TESTNET (matched #{marker.inspect}) — minting real " \
          "value on a testnet is unrecoverable. Point it at a mainnet endpoint."
      end
    end

    def oracle_violations(env, signer_process: true)
      out = ORACLE_KEY_ENVS.filter_map do |var|
        key = env[var]
        # An empty / whitespace value is NOT skipped: the services resolve via `ENV.fetch(var) { … }`,
        # which returns "" when the KEY exists-but-blank (a known Kamal empty-inject) → `Eth::Key`
        # raises at signing. `nil` = the key is genuinely absent → fine (the fallback handles it).
        next if key.nil? || key.match?(HEX64)

        "[oracle-key] #{var} is set but is not a 32-byte hex secp256k1 key " \
          "(expected 64 hex chars, optional 0x) — Eth::Key would raise at signing time."
      end

      if signer_process
        base = env["ORACLE_PRIVATE_KEY"]
        SIGNER_FALLBACKS.each do |role, specific_var|
          next if env[specific_var].present? || base.present?

          out << "[oracle-key] No #{role} oracle key: neither #{specific_var} nor the " \
                 "ORACLE_PRIVATE_KEY fallback is set — #{role} jobs would KeyError into the Sidekiq DeadSet."
        end
      end

      # [ARCH.47] Lock-key collision. Minting and slashing resolve a signer the same way the
      # services do; if both land on the SAME address they share one Kredis lock
      # `lock:web3:oracle:<addr>` → a 120s mint stalls a time-sensitive slash (whose LockTimeout
      # then silently aborts the burn, ARCH.48). Compare resolved-key strings — same hex ⇒ same
      # address; distinct hex ⇒ distinct address — so no Eth::Key derivation is needed at boot.
      # Scope = the mint↔slash pair (the time-sensitive collision). A bare ORACLE_PRIVATE_KEY present
      # *alongside* distinct MINTER/SLASHER does NOT collide the mint↔slash locks (legacy/Chainlink/Celo
      # still use base). A lower-severity base-vs-specific collision (e.g. Celo's base lock == minter) is
      # a deploy-checklist concern (distinct keys — INF.19/S1.1), not flagged here.
      minter  = env["ORACLE_MINTER_PRIVATE_KEY"].presence  || base
      slasher = env["ORACLE_SLASHER_PRIVATE_KEY"].presence || base
      if minter.present? && slasher.present? && normalized_key(minter) == normalized_key(slasher)
        out << "[oracle-key] minting and slashing resolve to the SAME signer key — a shared " \
               "ORACLE_PRIVATE_KEY fallback or identical MINTER/SLASHER keys collide on one Kredis " \
               "lock 'lock:web3:oracle:<addr>', stalling a time-sensitive slash. Provision distinct " \
               "ORACLE_MINTER_PRIVATE_KEY ≠ ORACLE_SLASHER_PRIVATE_KEY (E.2; canon 07_01 §B-02)."
      end

      out
    end

    # Normalize a hex private key for equality: drop an optional 0x prefix, downcase.
    # A shared hex secret ⇒ a shared on-chain address ⇒ a shared oracle lock key.
    def normalized_key(key)
      key.sub(/\A0x/i, "").downcase
    end
  end
end
