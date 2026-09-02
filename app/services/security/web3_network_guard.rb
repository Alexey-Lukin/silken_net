# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Pure content-judge for unsafe Web3 wiring. Mirrors
# `Security::WeakKeyDetector`: `.violations(env)` returns an array of
# human-readable strings (empty = safe); the companion initializer
# (`config/initializers/web3_network_guard.rb`) decides WHEN to enforce
# (production / WEB3_STRICT_MODE) and raises `SecurityError`.
#
# Chain identity. The realistic misconfiguration — an `*_RPC_URL` left on the wrong
#   chain family — is caught by a host/marker scan, since there is NO chain-id constant
#   in the code. A live `eth_chainId` probe is deliberately NOT done at boot: it would
#   make booting depend on RPC liveness (an availability failure worse than the config
#   bug it guards). A runtime chain-id assertion can layer on later.
#   ⊕ Which direction is "wrong" is declared per slot by `CHAIN_ENV_VAR` (see below) —
#   on mainnet a testnet endpoint mints real value on a throwaway chain; on a testnet
#   slot a mainnet endpoint lets staging sign real transactions. Both refuse to boot.
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
#   fraud-detector masked), and the INS.2 reserve gate fail-CLOSES but mislabels
#   the bug as transient RPC. Boot is the only loud moment this class has.
#   Values are never echoed
#   into the violation text — a mispasted secret must not leak into logs.
#   🔴 And "boot is the only loud moment" is a claim about EVERY container that
#   reads the var, which is why the verdict — presence AND format alike — is scoped
#   per-VARIABLE (`web:` in the map below) and not by `signer_process:` alone.
#   Measured 2026-09-01: the presence
#   branch was signer-scoped while the FORMAT branch was not, so on a web-only
#   slot (canopy — no Sidekiq) an UNSET address booted clean while a placeholder
#   refused. Same var, same consumer, opposite verdicts — and the quiet direction
#   was the dangerous one: `SystemAuditsController#index` → `ChainAuditService`
#   → `ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")` under `rescue StandardError`
#   returns `delta: 0, critical: false`, i.e. the false "all clean" named above,
#   for the life of the deploy. ⚠️ The tempting one-line fix — drop the scoping
#   entirely — breaks a neighbour: `coap_listener` loads every initializer and its
#   `/etc/silkennet/coap.env` carries no contract address. ⛔ That is an OBSERVATION,
#   not a canonized invariant: `06_04 §5.7` is the secrets-at-rest latch (SEC.22) and
#   says nothing about contract addresses — a false citation that stood on FIVE surfaces
#   until 2026-09-01, and whose first correction fixed one and scoped itself "this file",
#   i.e. reproduced the selective-addressing defect it was correcting.
#   🔴 And the file has TWO drift channels, not one, because `terraform/compute.tf` is a
#   one-time SEED, not the definition: its heredoc is guarded by `if [ ! -f …]` and its own
#   comment says "0600 placeholder — the operator fills real values". So (a) a repo sweep
#   that "aligns coap.env with deploy.yml" and (b) an operator editing the live file by hand
#   on the anchor both reach it — and only (a) is visible to anything in this repository.
#   Nor is there a gate: `spec/deploy/anchor_coap_env_spec.rb` denylists PROVISIONING plus
#   the money quintet and judges the HEREDOC, never the live file. An unconditional demand
#   here would refuse the telemetry intake's boot.
#   Hence three process classes, not two. ⛔ Adding a fourth address var? The map
#   makes you answer `web:` — do not default it by copying a neighbour; grep the
#   var and see whether ANY process of that class reads it — a controller, or a rake
#   task that runs inside the web container (`kamal app exec`). ⚖️ [INF.27 Q2/Q3,
#   2026-09-01] The criterion is "read by the class", not "controller-reachable":
#   the narrower wording would hand `web: false` to an address whose only web reader
#   is an MRV rake task, and — now that FORMAT is scoped by the same flag — would
#   silently drop the EIP-55 check from the one surface (ISO 14064/Verra lineage)
#   where a well-formed WRONG address is irreversible.
#   🔴 FORMAT IS SCOPED LIKE PRESENCE since 2026-09-02 [INF.27 Q3]: a class that never
#   reads a var judges neither its presence nor its value. Measured by resolving the
#   Kamal `coap` role through Kamal::Configuration 2.12: it inherits the global
#   env.clear placeholders it never reads, and the unscoped format branch refused its
#   boot on three `[address]` violations no operator could act on — the same
#   presence⊥format asymmetry that bit the web class, from the other side.
#
# Silent-RPC ENVs [INF.27 Q1, ⚖️ 2026-09-01]. The sister of the address set: an RPC
#   var whose read-site swallows its ABSENCE. `chain_violations` skips a blank URL on
#   purpose ("an absent URL normally just raises at use"), and ONE read-site disproves
#   that ground by execution: `ChainAuditService#fetch_chain_total_supply` calls
#   `RpcConnectionPool.client_for` (a bare `ENV.fetch`) under `rescue StandardError`,
#   so an absent var (KeyError), a present-but-empty one (`Eth::Client.create("")` →
#   ArgumentError) and a dead host (Net::*/Timeout) all return the same
#   `delta: 0, critical: false` — the fraud-detector answers "all clean" for the life
#   of the deploy. Presence is judged where the var is READ (job: every mint/rollback
#   site; web: the audit read-site), format is not (a URL carries no checksum), and
#   the dead-host shape is out of scope by design: that is availability, not config.
#   CI classifies the var RUNTIME (warn-only), so before this row canopy deployed
#   GREEN with no Polygon RPC at all.
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
      CELO_RPC_URL
      SOLANA_RPC_URL
    ].freeze

    # Testnet host/path markers, alnum-boundary-anchored so a mainnet URL can't
    # match by coincidence (a random API-key token never trips it).
    TESTNET_MARKER =
      /(?<![a-z0-9])(?:amoy|mumbai|sepolia|goerli|holesky|ropsten|rinkeby|kovan|testnet|devnet)(?![a-z0-9])/i

    # Declared chain family of this deploy slot [OPS.37 — the `production` split].
    # `production` used to carry TWO claims at once — "hardened runtime" and "this is real
    # money" — and a staging slot needs the FIRST WITHOUT THE SECOND. The runtime half stays
    # where it was (`Rails.env.production?` ∨ `WEB3_STRICT_MODE`, both read by the companion
    # initializer, which is why patching only one of them would not work); the money half
    # moves HERE, as a second axis beside `signer_process:`.
    #
    # ⛔ This is NOT a bypass, and the distinction is the whole design. Each value is an
    # ASSERTION the wiring must satisfy, and the two are mirror images: `mainnet` refuses a
    # testnet endpoint (real value minted on a throwaway chain), `testnet` refuses a mainnet
    # one (a staging slot able to sign real transactions — the hazard that keeps canopy
    # web-only today). So a mis-DECLARED slot fails exactly as loudly as a mis-WIRED one, and
    # an absent declaration lands on `mainnet`, i.e. the strict side: a forgotten flag can
    # never downgrade safety, only refuse a boot.
    # ⚠️ What this axis deliberately does NOT cover: the KYC surface. «Hadron stub on testnet ⊥
    # a separate Hadron sandbox» is a verdict about the KYC provider, not about the chain —
    # its home is `00_07` OPS.37 (and the job-role comment in config/deploy.canopy.yml), so
    # do not read `testnet` here as «KYC is stubbed».
    CHAIN_ENV_VAR = "WEB3_CHAIN_ENV"
    CHAIN_ENVS = %w[mainnet testnet].freeze
    DEFAULT_CHAIN_ENV = "mainnet"

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
    # ENV → `cost:` what the silence costs (goes into the violation text) +
    #       `web:`  is there a controller-reachable read-site, i.e. must the WEB
    #               container demand presence too (see the header note).
    # Measured consumers 2026-09-01 (`grep -rn <VAR> app lib`), and the count is the
    # whole point — only one of the three leaves the money path:
    #   · CARBON_COIN  6 sites, ONE of them web-reachable (chain_audit_service.rb)
    #   · DAO_TREASURY 3 sites, all job (blockchain_minting_service, insurance/reserve_gate)
    #   · FOREST_COIN  1 site,  job     (blockchain_minting_service)
    SILENT_ADDRESS_ENVS = {
      "DAO_TREASURY_ADDRESS"         => { web: false,
                                          cost: "the 2% Dynamic Tax silently stays off — the DAO treasury " \
                                                "leaks revenue and the log lies 'RPC degraded' (E.46 umbrella)" },
      "CARBON_COIN_CONTRACT_ADDRESS" => { web: true,
                                          cost: "ChainAuditService reports a false 'all clean' — the db<->chain " \
                                                "fraud-detector is masked" },
      # ⛔ The cost line here USED to say "the SFC half of the chain-audit read-site degrades
      # silently" — and there is no SFC half: `ChainAuditService` reads the SCC address only
      # (`grep -n "FOREST\|SFC" app/services/chain_audit_service.rb` → nothing). Inherited prose,
      # carried unchecked through the very pass that re-measured the consumers, and it reached
      # the operator inside a boot refusal — naming the price of a mechanism that does not exist.
      "FOREST_COIN_CONTRACT_ADDRESS" => { web: false,
                                          cost: "the one branch that reads it is unreachable behind an " \
                                                "earlier return, so nothing evaluates it today — and the " \
                                                "moment SFC minting is armed this stops being silent: the " \
                                                "read is a bare ENV.fetch with no rescue, i.e. a LOUD " \
                                                "KeyError, and this variable's membership in the silent " \
                                                "set expires with it [INF.27]" }
    }.freeze

    # RPC ENVs whose read-site swallows ABSENCE (header: "Silent-RPC ENVs"). Same
    # process-class predicate as the address map, no format branch. [INF.27 Q1]
    SILENT_RPC_ENVS = {
      "ALCHEMY_POLYGON_RPC_URL" => { web: true,
                                     cost: "ChainAuditService reports a false 'all clean' — KeyError and " \
                                           "Eth::Client.create(\"\") land in the same rescue as an RPC outage" }
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
    # (plaintext-ENV exposure of any container's environ), so demanding
    # presence there would force keys BACK onto the widest attack surface.
    # Format and collision checks still run everywhere a key IS present.
    # `web_process:` is the SECOND scoping axis and it is not a duplicate of the
    # first: the three process classes are job (Sidekiq) / web (Puma, and any rake
    # task in that container) / coap (`coap_listener`), and a var can be consumed by
    # the first two while the third must never be asked for it. Both default to the
    # STRICT side for the same reason `chain_env` defaults to `mainnet` — a caller
    # that forgets an axis can only over-refuse a boot, never under-protect one.
    def violations(env = ENV, signer_process: true, web_process: true)
      chain_violations(env) +
        oracle_violations(env, signer_process: signer_process) +
        address_violations(env, signer_process: signer_process, web_process: web_process) +
        rpc_violations(env, signer_process: signer_process, web_process: web_process) +
        solana_violations(env, signer_process: signer_process)
    end

    # The declared chain family, normalised. Absent → the fail-closed default.
    def chain_env(env = ENV)
      env[CHAIN_ENV_VAR].presence&.strip&.downcase || DEFAULT_CHAIN_ENV
    end

    def chain_violations(env)
      declared = chain_env(env)
      unless CHAIN_ENVS.include?(declared)
        # Never silently fall back to the strict value: a typo would then produce a slot
        # that is strict for the wrong reason, and the operator would have no way to see it.
        return [ "[chain] #{CHAIN_ENV_VAR} is #{declared.inspect}, which is not one of " \
                 "#{CHAIN_ENVS.join('/')} — refusing to guess which chain family this slot " \
                 "targets. Leave it unset for #{DEFAULT_CHAIN_ENV}." ]
      end

      testnet = declared == "testnet"

      out = RPC_URL_ENVS.filter_map do |var|
        url = env[var]
        next if url.blank?

        marker = url[TESTNET_MARKER]

        if testnet
          next if marker

          "[chain] #{var} points at a MAINNET endpoint while #{CHAIN_ENV_VAR}=testnet — a " \
            "staging slot must not be able to sign real transactions. Point it at a testnet " \
            "endpoint, or drop the #{CHAIN_ENV_VAR} declaration if this slot IS mainnet."
        else
          next unless marker

          "[chain] #{var} points at a TESTNET (matched #{marker.inspect}) — minting real " \
            "value on a testnet is unrecoverable. Point it at a mainnet endpoint."
        end
      end

      out + hardcoded_fallback_violations(env, testnet: testnet)
    end

    # A blank RPC var is skipped above because an absent URL normally just raises at use.
    # TWO do not — their read-sites carry an explicit hardcoded fallback, so a blank var
    # silently resolves to a fixed endpoint — and those endpoints sit on OPPOSITE sides of
    # the chain axis, which is why each rule below fires on one side only:
    #   · ALCHEMY_POLYGON_RPC_URL → mainnet polygon-rpc.com → judged here, on `testnet`
    #   · SOLANA_RPC_URL          → Devnet TESTNET          → judged at its READ-SITES
    # ⚠️ The Solana one is deliberately absent from this method and that is a bound, not an
    # oversight: `Solana::MintingService#solana_rpc_urls` already raises on a blank var when
    # the slot declares `mainnet` (it reads the same `chain_env`), and `Treasury::MonitorService`
    # #fetch_solana_balance skips+warns on the same conjunction — so a boot rule would be a
    # second home for one decision. ⚠️ COUNT the read-sites, not the constants: Solana has TWO.
    # ⚖️ CELO_RPC_URL WAS the third and is gone [2026-08-31, founder]: its hardcoded fallback
    # was REMOVED rather than repointed, so a blank var no longer resolves anywhere — the Celo
    # path is fail-closed by construction. The rule below survives that, but on a new ground.
    # ⛔ Adding a fallback back? Ask first whether the path is a MONEY path: there, "works
    # without config" is the hazard, not the convenience, and every such fallback buys itself
    # a boot rule to police it. Put it wherever its sibling lives — and COUNT them first: this
    # comment once claimed "two" while a third already existed one file away.
    def hardcoded_fallback_violations(env, testnet:)
      out = []

      # [E.49] Unset CELO_RPC_URL while the Celo path is ARMED.
      # ⚖️ GROUND REWRITTEN 2026-08-31 (founder), and this is the third ground this rule has
      # had — worth naming, because each replacement was a real change of subject:
      #   (1) "real cUSD pays out on a throwaway chain"  → died when Alfajores went NXDOMAIN;
      #   (2) "the payout path resolves to nothing"      → died when the fallback was REMOVED;
      #   (3) TODAY: there is no fallback at all, so a blank var is a `KeyError` at CALL time —
      #       on the payout, the confirmation and the mint-rollback alike. This rule buys
      #       exactly one thing, and it is worth a boot: it moves that failure from the first
      #       Celo event (rare, event-driven, in production) to `kamal deploy` (immediate).
      # 🔑 The trigger is ARMING, not usage: `ORACLE_CELO_PRIVATE_KEY` present means the path
      # is live, and arming a payout path without its RPC must never reach production. Armed
      # conditionally for that reason (the signer key lives only on the job surface, so
      # web/coap boot clean without it).
      # ⛔ Do NOT "fix" this by restoring a default URL — that is the removed hazard, not a
      # convenience; see the note on the deleted constant in `Celo::CommunityRewardService`.
      if !testnet && env["ORACLE_CELO_PRIVATE_KEY"].present? && env["CELO_RPC_URL"].blank?
        out << "[chain] CELO_RPC_URL is not set while ORACLE_CELO_PRIVATE_KEY is present — " \
               "the Celo path is fail-closed (E.49, no hardcoded fallback since 2026-08-31), " \
               "so every reward payout, confirmation and mint-rollback would raise KeyError " \
               "at call time. Set a mainnet Celo RPC."
      end

      # Mirror of the rule above, and it exists because the testnet axis CREATED the hazard:
      # the Polygon branch of `MintingRollbackService` falls back to the hardcoded MAINNET
      # `polygon-rpc.com`, so a testnet slot that forgets the var reads mainnet state in
      # silence — the one direction the marker scan above cannot see, since it only ever
      # inspects a url that IS set. Armed on the minter key for the same reason as Celo.
      if testnet && env["ORACLE_MINTER_PRIVATE_KEY"].present? && env["ALCHEMY_POLYGON_RPC_URL"].blank?
        out << "[chain] ALCHEMY_POLYGON_RPC_URL is not set while #{CHAIN_ENV_VAR}=testnet and " \
               "the minter key is present — MintingRollbackService falls back to the hardcoded " \
               "MAINNET endpoint (polygon-rpc.com), so a staging slot would read mainnet " \
               "state. Set a testnet Polygon RPC."
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
    # HERE. The verdict is asked wherever the var is actually READ — the signer
    # process always, plus the web container for the `web: true` members — and it
    # is ONE verdict at two moments: presence when the value is blank, format when
    # it is not. A class that reads nothing judges nothing [INF.27 Q3]: format used
    # to run wherever a value was merely PRESENT, which refused the dormant Kamal
    # `coap` role on placeholders it inherits and never reads. The value itself is
    # never included in the message. ⛔ The predecessor of this line read "the signer
    # process only (web/coap never mint/audit)" and the parenthesis was HALF false:
    # web does not mint, but it audits — see the header note for the measurement.
    def address_violations(env, signer_process: true, web_process: true)
      SILENT_ADDRESS_ENVS.filter_map do |var, spec|
        next unless signer_process || (web_process && spec.fetch(:web))

        cost  = spec.fetch(:cost)
        value = env[var]
        if value.blank?
          "[address] #{var} is not set — this would NOT crash: #{cost}."
        elsif !value.match?(EthAddressValidatable::ETH_ADDRESS_FORMAT)
          # The message must separate the two operator actions this one predicate covers:
          # a mispaste is fixed in the vault, an unfilled placeholder is fixed by deploying
          # contracts FIRST. Naming the deploy-order (rather than the placeholder literal)
          # keeps the convention's single home in the manifests, not here.
          "[address] #{var} is set but is not a 0x-prefixed 40-hex address (value not " \
            "echoed — it could be a mispasted secret, or still the deploy placeholder: " \
            "these are filled after `forge deploy` ON THE CHAIN THIS SLOT DECLARES via " \
            "#{CHAIN_ENV_VAR}, canon 06_04 §2.1) — #{cost}."
        elsif !EthAddressValidatable.eip55_valid?(value)
          # [ARCH.56] Well-formed but self-inconsistent: a mixed-case address CARRIES its
          # own EIP-55 checksum, so a mismatch is a mistyped/mispasted character, never a
          # style choice. Shape alone cannot see it — 40 hex stay 40 hex.
          "[address] #{var} is a well-formed address whose EIP-55 checksum does not match, " \
            "i.e. a mistyped or truncated-and-repadded value (value not echoed) — #{cost}."
        end
      end
    end

    # Silent-RPC presence [INF.27 Q1] — same predicate as the addresses, no format
    # branch (a URL carries no checksum; a WRONG chain is `chain_violations`' axis).
    # Present-but-empty counts as absent: that is the Kamal empty-inject shape, and
    # `Eth::Client.create("")` lands in the same rescue as a KeyError.
    def rpc_violations(env, signer_process: true, web_process: true)
      SILENT_RPC_ENVS.filter_map do |var, spec|
        next unless signer_process || (web_process && spec.fetch(:web))
        next if env[var].present?

        "[rpc] #{var} is not set — this would NOT crash: #{spec.fetch(:cost)}. Set the " \
          "endpoint for the chain family this slot declares via #{CHAIN_ENV_VAR}."
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
