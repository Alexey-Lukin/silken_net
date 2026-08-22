# SPDX-License-Identifier: AGPL-3.0-or-later
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
# Oracle signer keys. Every signer resolves a DEDICATED key (`ENV.fetch` with
#   no fallback — the legacy shared ORACLE_PRIVATE_KEY is retired, INF.22). A
#   missing key raises KeyError deep inside a Sidekiq worker → the job lands in
#   the DeadSet silently, so the boot-critical pair (minter/slasher) is
#   presence-checked at boot; every present oracle-family key is format-checked.
#   A second failure mode (ARCH.47): minting and slashing resolving to the SAME
#   key — identical MINTER/SLASHER values — collide on one Kredis oracle lock
#   and serialize mint↔slash, so a 120s mint stalls a time-sensitive slash (and
#   a LockTimeout there silently aborts the burn, ARCH.48). E.2 (canon 00_04
#   §B-02) mandates physically separate keys. The retired legacy name is a
#   tripwire: a value under ORACLE_PRIVATE_KEY is a dead plaintext surface no
#   code reads — refuse it so zombie deploy-config can't linger.
#
# Silent-address ENVs. Not secrets — public addresses whose FAILURE MODE is
#   the problem: their read-sites sit under rescue-umbrellas written for RPC
#   degradation, so a missing / placeholder / garbage value never surfaces as
#   a config bug — the E.46 mint-tax check silently disables the tax, the
#   ChainAuditService returns a false "delta 0, all clean" (the db<->chain
#   fraud-detector masked), PriceOracleService silently serves fallback_price,
#   and the INS.2 reserve gate fail-CLOSES but mislabels the bug as transient
#   RPC. Boot is the only loud moment this class has. Values are never echoed
#   into the violation text — a mispasted secret must not leak into logs.
#
# Solana signer set [E.61]. No stub mode exists; absence self-reveals only
#   per-event (a DeadSet job), while the batch-payout loop swallows per-wallet
#   errors with no escalation path — accumulated forester rewards would
#   silently never pay out. The signer process must hold the full set.
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

    # Every dedicated secp256k1 signer key (format-checked when present).
    ORACLE_KEY_ENVS = %w[
      ORACLE_MINTER_PRIVATE_KEY ORACLE_SLASHER_PRIVATE_KEY ORACLE_CELO_PRIVATE_KEY
      ORACLE_ETHERISC_PRIVATE_KEY ORACLE_PURO_PRIVATE_KEY ORACLE_KLIMA_PRIVATE_KEY
      ETHEREUM_ANCHOR_PRIVATE_KEY
    ].freeze

    # Retired shared fallback [INF.22] — no code reads it; presence = zombie config.
    RETIRED_KEY_ENV = "ORACLE_PRIVATE_KEY"

    # Boot-critical signer roles (mint/slash money path) — presence-checked in
    # the signer process. The aux signers (Celo/Etherisc/Puro/Klima) are
    # activation-gated lazy keys: absent until their path goes live (06_04 §2.1).
    SIGNER_KEYS = {
      "minting"  => "ORACLE_MINTER_PRIVATE_KEY",
      "slashing" => "ORACLE_SLASHER_PRIVATE_KEY"
    }.freeze

    # ETH-address ENVs whose read-sites fail SILENT (rescue umbrellas mask the
    # config error as an operational state) → boot is their only loud gate.
    # ENV → what the silence costs (goes into the violation text).
    SILENT_ADDRESS_ENVS = {
      "DAO_TREASURY_ADDRESS"         => "the 2% Dynamic Tax silently stays off — the DAO treasury " \
                                        "leaks revenue and the log lies 'RPC degraded' (E.46 umbrella)",
      "CARBON_COIN_CONTRACT_ADDRESS" => "ChainAuditService reports a false 'all clean' (the db<->chain " \
                                        "fraud-detector is masked) and PriceOracleService silently " \
                                        "serves fallback_price",
      "FOREST_COIN_CONTRACT_ADDRESS" => "the SFC half of the chain-audit read-site degrades silently " \
                                        "(same umbrella as the SCC address)"
    }.freeze

    # Solana money-path credentials [E.61] — presence-checked at signer boot
    # (no stub mode; the batch-payout loop has no escalation path).
    SOLANA_SIGNER_ENVS = %w[
      SOLANA_WALLET_KEYPAIR SOLANA_FEE_PAYER_PUBKEY
      SOLANA_FEE_PAYER_TOKEN_ACCOUNT SOLANA_USDC_MINT_ADDRESS
    ].freeze

    # `env` defaults to ENV but is injectable for tests.
    # `signer_process:` scopes the key-PRESENCE requirement to processes that
    # actually sign (Sidekiq). The web/coap containers never hold money keys
    # (plaintext-ENV exposure on an untrusted Akash provider), so demanding
    # presence there would force keys BACK onto the widest attack surface.
    # Format and collision checks still run everywhere a key IS present.
    def violations(env = ENV, signer_process: true)
      chain_violations(env) +
        oracle_violations(env, signer_process: signer_process) +
        address_violations(env, signer_process: signer_process) +
        solana_violations(env, signer_process: signer_process)
    end

    def chain_violations(env)
      out = RPC_URL_ENVS.filter_map do |var|
        url = env[var]
        next if url.blank?

        marker = url[TESTNET_MARKER]
        next unless marker

        "[chain] #{var} points at a TESTNET (matched #{marker.inspect}) — minting real " \
          "value on a testnet is unrecoverable. Point it at a mainnet endpoint."
      end

      # [E.49] CELO_RPC_URL has a CODE-side testnet fallback (Alfajores): unset does not
      # raise — real cUSD rewards would silently run against a throwaway chain, so the
      # blank-skip above misses it. Presence is gated CONDITIONALLY on the Celo path being
      # armed (its signer key present; the key lives only on the job surface, so web/coap
      # boot clean without either).
      if env["ORACLE_CELO_PRIVATE_KEY"].present? && env["CELO_RPC_URL"].blank?
        out << "[chain] CELO_RPC_URL is not set while ORACLE_CELO_PRIVATE_KEY is present — " \
               "the code falls back to Alfajores TESTNET (E.49): real cUSD would pay out " \
               "on a throwaway chain. Set a mainnet Celo RPC."
      end

      out
    end

    def oracle_violations(env, signer_process: true)
      out = ORACLE_KEY_ENVS.filter_map do |var|
        key = env[var]
        # An empty / whitespace value is NOT skipped: `ENV.fetch` returns "" when the KEY
        # exists-but-blank (a known Kamal empty-inject) → `Eth::Key` raises at signing.
        # `nil` = genuinely absent → fine here (the boot-critical pair is presence-checked
        # below; aux signers are activation-gated lazy keys).
        next if key.nil? || key.match?(HEX64)

        "[oracle-key] #{var} is set but is not a 32-byte hex secp256k1 key " \
          "(expected 64 hex chars, optional 0x) — Eth::Key would raise at signing time."
      end

      # Retired-name tripwire [INF.22]: any value (even a valid key, even "") under the
      # legacy name is config that no code reads — a pure plaintext liability on an
      # untrusted provider, and a sign the deploy env predates the dedicated-key split.
      unless env[RETIRED_KEY_ENV].nil?
        out << "[oracle-key] #{RETIRED_KEY_ENV} is RETIRED (INF.22) — no code reads it; " \
               "remove it from the deploy env (dedicated keys: #{ORACLE_KEY_ENVS.join(', ')})."
      end

      if signer_process
        SIGNER_KEYS.each do |role, var|
          next if env[var].present?

          out << "[oracle-key] No #{role} oracle key: #{var} is not set — " \
                 "#{role} jobs would KeyError into the Sidekiq DeadSet."
        end
      end

      # [ARCH.47] Lock-key collision. If minting and slashing land on the SAME address they
      # share one Kredis lock `lock:web3:oracle:<addr>` → a 120s mint stalls a time-sensitive
      # slash (whose LockTimeout then silently aborts the burn, ARCH.48). Compare key strings —
      # same hex ⇒ same address; distinct hex ⇒ distinct address — so no Eth::Key derivation is
      # needed at boot. Scope = the mint↔slash pair (the time-sensitive collision); an
      # aux-vs-mint collision (e.g. Etherisc key == minter) is a deploy-checklist concern
      # (distinct keys — INF.19/S1.1), not flagged here.
      minter  = env["ORACLE_MINTER_PRIVATE_KEY"]
      slasher = env["ORACLE_SLASHER_PRIVATE_KEY"]
      if minter.present? && slasher.present? && normalized_key(minter) == normalized_key(slasher)
        out << "[oracle-key] minting and slashing resolve to the SAME signer key — identical " \
               "MINTER/SLASHER keys collide on one Kredis lock 'lock:web3:oracle:<addr>', " \
               "stalling a time-sensitive slash. Provision distinct " \
               "ORACLE_MINTER_PRIVATE_KEY ≠ ORACLE_SLASHER_PRIVATE_KEY (E.2; canon 00_04 §B-02)."
      end

      out
    end

    # The silent-address read-sites swallow config errors (their umbrellas mask
    # a misconfig as an operational state), so unset/garbage is only ever loud
    # HERE. Presence is demanded in the signer process only (web/coap never
    # mint/audit); format is checked wherever a value IS present. The value
    # itself is never included in the message.
    def address_violations(env, signer_process: true)
      SILENT_ADDRESS_ENVS.filter_map do |var, cost|
        value = env[var]
        if value.blank?
          next unless signer_process

          "[address] #{var} is not set — this would NOT crash: #{cost}."
        elsif !value.match?(EthAddressValidatable::ETH_ADDRESS_FORMAT)
          "[address] #{var} is set but is not a 0x-prefixed 40-hex address (value not " \
            "echoed — it could be a mispasted secret; the REQUIRED_SECRET_NOT_SET deploy " \
            "placeholder trips this too) — #{cost}."
        elsif !EthAddressValidatable.eip55_valid?(value)
          # [ARCH.56] Well-formed but self-inconsistent: a mixed-case address CARRIES its
          # own EIP-55 checksum, so a mismatch is a mistyped/mispasted character, never a
          # style choice. Shape alone cannot see it — 40 hex stay 40 hex.
          "[address] #{var} is a well-formed address whose EIP-55 checksum does not match, " \
            "i.e. a mistyped or truncated-and-repadded value (value not echoed) — #{cost}."
        end
      end
    end

    # Solana presence: absence self-reveals only per-event (DeadSet); the batch
    # path loses the payment entirely — so demand the full set at signer boot.
    def solana_violations(env, signer_process: true)
      return [] unless signer_process

      SOLANA_SIGNER_ENVS.filter_map do |var|
        next if env[var].present?

        "[solana] #{var} is not set — per-event rewards would DeadSet and batch " \
          "payouts would silently skip every wallet (no escalation path, E.61)."
      end
    end

    # Normalize a hex private key for equality: drop an optional 0x prefix, downcase.
    # A shared hex secret ⇒ a shared on-chain address ⇒ a shared oracle lock key.
    def normalized_key(key)
      key.sub(/\A0x/i, "").downcase
    end
  end
end
