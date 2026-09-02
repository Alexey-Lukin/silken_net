# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Security::Web3NetworkGuard do
  describe ".violations" do
    # Mainnet RPC endpoints, no oracle keys — the chain half of a clean env.
    let(:mainnet_rpcs) do
      {
        "ALCHEMY_POLYGON_RPC_URL"  => "https://polygon-mainnet.g.alchemy.com/v2/key",
        "ALCHEMY_ETHEREUM_RPC_URL" => "https://eth-mainnet.g.alchemy.com/v2/key",
        "SOLANA_RPC_URL"           => "https://api.mainnet-beta.solana.com"
      }
    end

    # [E.2 / ARCH.47] A clean strict env uses PHYSICALLY SEPARATE minter + slasher keys.
    # A bare-ORACLE_PRIVATE_KEY-only env is NOT clean — both roles would resolve to one
    # address and collide on a single oracle lock (the canon 00_04 §B-02 rule, now boot-enforced).
    # The silent-address set (treasury + SCC/SFC + the L1 anchor) and the Solana signer set are part of a
    # clean signer env: their read-sites fail SILENT (rescue umbrellas / no-escalation batch
    # loop), so boot presence is the only loud gate they have.
    let(:clean_env) do
      mainnet_rpcs.merge(
        "ORACLE_MINTER_PRIVATE_KEY"      => "b" * 64,
        "ORACLE_SLASHER_PRIVATE_KEY"     => "c" * 64,
        "DAO_TREASURY_ADDRESS"           => "0x#{'a' * 40}",
        "CARBON_COIN_CONTRACT_ADDRESS"   => "0x#{'b' * 40}",
        "FOREST_COIN_CONTRACT_ADDRESS"   => "0x#{'c' * 40}",
        "ETHEREUM_ANCHOR_CONTRACT"       => "0x#{'d' * 40}",
        "SOLANA_WALLET_KEYPAIR"          => "keypair",
        "SOLANA_FEE_PAYER_PUBKEY"        => "pubkey",
        "SOLANA_FEE_PAYER_TOKEN_ACCOUNT" => "token-account",
        "SOLANA_USDC_MINT_ADDRESS"       => "usdc-mint"
      )
    end

    it "passes a clean mainnet env (separate minter + slasher)" do
      expect(described_class.violations(clean_env)).to be_empty
    end

    # --- chain identity ---------------------------------------------------

    it "flags a Polygon Amoy testnet RPC" do
      env = clean_env.merge("ALCHEMY_POLYGON_RPC_URL" => "https://polygon-amoy.g.alchemy.com/v2/key")
      expect(described_class.violations(env)).to include(a_string_matching(/\[chain\].*TESTNET/))
    end

    it "flags a Solana devnet RPC" do
      env = clean_env.merge("SOLANA_RPC_URL" => "https://api.devnet.solana.com")
      expect(described_class.violations(env)).to include(a_string_matching(/\[chain\].*TESTNET/))
    end

    it "does not false-positive when a marker is glued inside an API-key token" do
      # 'amoy' here is bounded by alnum (…9amoyz…) → the lookaround must not match.
      env = clean_env.merge("ALCHEMY_POLYGON_RPC_URL" => "https://polygon-mainnet.g.alchemy.com/v2/x9amoyz2abc")
      expect(described_class.violations(env)).to be_empty
    end

    # [E.49] ⚖️ 2026-08-31: hardcoded-фолбек знято, тож unset більше не «тихо сідає на
    # Alfajores» — він RAISE'ить на кожному Celo-виклику. Правило вижило, ПІДСТАВА змінилась:
    # воно переносить той `KeyError` із першої (рідкісної, продової) події на `kamal deploy`.
    # Пін цілиться в fail-closed, а не в імʼя мертвого хоста — саме тому він і почервонів,
    # коли підстава змінилась, і це правильна поведінка піна.
    it "flags a blank CELO_RPC_URL when the Celo signer key is present (path is fail-closed)" do
      env = clean_env.merge("ORACLE_CELO_PRIVATE_KEY" => "d" * 64)
      expect(described_class.violations(env))
        .to include(a_string_matching(/\[chain\].*CELO_RPC_URL.*fail-closed.*KeyError/))
    end

    it "does not demand CELO_RPC_URL while the Celo path is unarmed (no signer key)" do
      expect(described_class.violations(clean_env)).not_to include(a_string_matching(/CELO_RPC_URL/))
    end

    it "accepts an armed Celo path with a mainnet RPC" do
      env = clean_env.merge("ORACLE_CELO_PRIVATE_KEY" => "d" * 64, "CELO_RPC_URL" => "https://forno.celo.org")
      expect(described_class.violations(env)).to be_empty
    end

    # --- declared chain family [OPS.37 — the `production` split] ----------
    #
    # The axis is an ASSERTION, never a bypass: both directions refuse to boot, so a
    # mis-declared slot is as loud as a mis-wired one. These examples pin BOTH edges,
    # because pinning only the newly-allowed one would let the old rule rot silently.
    context "when the slot declares a chain family (WEB3_CHAIN_ENV)" do
      let(:testnet_rpcs) do
        {
          "ALCHEMY_POLYGON_RPC_URL"  => "https://polygon-amoy.g.alchemy.com/v2/key",
          "ALCHEMY_ETHEREUM_RPC_URL" => "https://eth-sepolia.g.alchemy.com/v2/key",
          "SOLANA_RPC_URL"           => "https://api.devnet.solana.com"
        }
      end

      # The whole point of the split: this env was STRUCTURALLY un-bootable before it.
      it "passes a testnet slot wired to testnet endpoints" do
        env = clean_env.merge(testnet_rpcs).merge("WEB3_CHAIN_ENV" => "testnet")
        expect(described_class.violations(env)).to be_empty
      end

      it "passes a mainnet slot that declares itself explicitly" do
        expect(described_class.violations(clean_env.merge("WEB3_CHAIN_ENV" => "mainnet"))).to be_empty
      end

      it "flags a MAINNET endpoint on a slot declared testnet (staging must not sign real value)" do
        env = clean_env.merge(testnet_rpcs)
                       .merge("WEB3_CHAIN_ENV" => "testnet",
                              "ALCHEMY_POLYGON_RPC_URL" => "https://polygon-mainnet.g.alchemy.com/v2/key")
        expect(described_class.violations(env))
          .to include(a_string_matching(/\[chain\].*ALCHEMY_POLYGON_RPC_URL.*MAINNET endpoint/))
      end

      # Regression edge: the pre-split rule must survive the rewrite unchanged.
      # [ARCH.114] The keyless fallbacks are judged on the SAME axis as the primaries: a
      # fallback is where the cascade lands when the primary dies, so a mainnet fallback on a
      # testnet slot is «staging able to sign real value» one outage later. Mutation-verified:
      # dropping RPC_FALLBACK_URL_ENVS from `chain_violations` reddens the first two examples.
      it "flags a MAINNET fallback on a slot declared testnet (the cascade would land on real value)" do
        env = clean_env.merge(testnet_rpcs)
                       .merge("WEB3_CHAIN_ENV" => "testnet",
                              "POLYGON_RPC_URL_FALLBACK_1" => "https://polygon-bor-rpc.publicnode.com")
        expect(described_class.violations(env))
          .to include(a_string_matching(/\[chain\].*POLYGON_RPC_URL_FALLBACK_1.*MAINNET endpoint/))
      end

      it "flags a TESTNET fallback on a mainnet slot" do
        expect(described_class.violations(clean_env.merge("CELO_RPC_URL_FALLBACK_2" => "https://celo-sepolia.drpc.org")))
          .to include(a_string_matching(/\[chain\].*CELO_RPC_URL_FALLBACK_2.*TESTNET/))
      end

      # The blank-skip is load-bearing only on a TESTNET slot: a mainnet slot skips a blank
      # value whether or not the branch exists ("" carries no marker either way), whereas on
      # testnet a blank judged as an endpoint reads as MAINNET. Dropping `next if url.blank?`
      # reddens THIS example, not its mainnet twin — canopy deliberately leaves
      # SOLANA_RPC_URL_FALLBACK_2 absent (PublicNode/dRPC answer 403 for Solana).
      it "skips a blank fallback slot on a testnet slot (presence is optional, the canopy shape)" do
        env = clean_env.merge(testnet_rpcs).merge("WEB3_CHAIN_ENV" => "testnet",
                                                 "SOLANA_RPC_URL_FALLBACK_1" => "https://api.devnet.solana.com",
                                                 "SOLANA_RPC_URL_FALLBACK_2" => "")
        expect(described_class.violations(env).grep(/SOLANA_RPC_URL_FALLBACK_2/)).to be_empty
      end

      it "passes a testnet slot whose fallbacks are testnet twins (the canopy shape)" do
        env = clean_env.merge(testnet_rpcs).merge(
          "WEB3_CHAIN_ENV" => "testnet",
          "POLYGON_RPC_URL_FALLBACK_1" => "https://polygon-amoy-bor-rpc.publicnode.com",
          "CELO_RPC_URL_FALLBACK_1" => "https://forno.celo-sepolia.celo-testnet.org",
          "SOLANA_RPC_URL_FALLBACK_1" => "https://api.devnet.solana.com"
        )
        expect(described_class.violations(env)).to be_empty
      end

      # Registry parity: every cascade key EITHER reader can land on is chain-judged here —
      # a fallback registered in one file and not the other would be judged by nobody. Two
      # readers, not one: the EVM pool registry and Solana's own list (its cascade is read by
      # `Solana::MintingService#execute_rpc_call`, not by the pool).
      it "chain-judges every fallback key the RPC pool registry and the Solana cascade can land on" do
        pool_keys   = Web3::RpcConnectionPool::NETWORK_FALLBACK_ENV_KEYS.values.flatten.uniq
        solana_keys = Solana::MintingService::RPC_FALLBACK_ENV_KEYS
        expect(described_class::RPC_FALLBACK_URL_ENVS).to include(*(pool_keys + solana_keys).uniq)
      end

      it "still flags a testnet endpoint when no chain family is declared (fail-closed default)" do
        env = clean_env.merge("ALCHEMY_POLYGON_RPC_URL" => "https://polygon-amoy.g.alchemy.com/v2/key")
        expect(described_class.violations(env)).to include(a_string_matching(/\[chain\].*TESTNET/))
      end

      it "normalises case and surrounding whitespace" do
        env = clean_env.merge(testnet_rpcs).merge("WEB3_CHAIN_ENV" => "  TestNet ")
        expect(described_class.violations(env)).to be_empty
      end

      # An unrecognised value must never resolve to the strict default in silence: the slot
      # would then be strict for a reason the operator cannot see.
      it "refuses an unrecognised value instead of guessing" do
        env = clean_env.merge("WEB3_CHAIN_ENV" => "staging")
        expect(described_class.violations(env))
          .to include(a_string_matching(/\[chain\].*WEB3_CHAIN_ENV is "staging".*not one of/))
      end

      # [E.49] ⚖️ 2026-08-31: the rule is one-sided, and its GROUND changed while the verdict
      # stood. It used to read "on a testnet slot the Alfajores fallback is the CORRECT
      # landing" — that premise died twice over: the host went NXDOMAIN, then the fallback was
      # REMOVED entirely. What survives is narrower and still right: the boot rule is armed on
      # the MAINNET side only, so a testnet slot is not asked for the var here. ⚠️ It is asked
      # at CALL time now (`ENV.fetch` → KeyError), which is a different surface, not an
      # exemption — see the mainnet sibling above for the rule's live ground.
      it "does not demand CELO_RPC_URL on a testnet slot (the boot rule is mainnet-only)" do
        env = clean_env.merge(testnet_rpcs).merge("WEB3_CHAIN_ENV" => "testnet",
                                                  "ORACLE_CELO_PRIVATE_KEY" => "d" * 64)
        expect(described_class.violations(env)).not_to include(a_string_matching(/CELO_RPC_URL/))
      end

      # The mirror hazard this axis CREATED: the Polygon fallback is hardcoded MAINNET, and
      # a marker scan cannot see it because the var is blank.
      it "flags a blank ALCHEMY_POLYGON_RPC_URL on an armed testnet slot (hardcoded mainnet fallback)" do
        env = clean_env.merge(testnet_rpcs).merge("WEB3_CHAIN_ENV" => "testnet")
                       .except("ALCHEMY_POLYGON_RPC_URL")
        expect(described_class.violations(env))
          .to include(a_string_matching(/\[chain\].*ALCHEMY_POLYGON_RPC_URL.*polygon-rpc\.com/))
      end

      # The fallback rule is armed on the MINTER key, so it stays silent without one. Asked
      # from the coap class on purpose: the `[rpc]` PRESENCE rule [INF.27 Q1] is a different
      # axis with its own examples below, and it WOULD fire here from web or job.
      it "does not arm the hardcoded-fallback rule on a testnet slot with no minter key" do
        env = clean_env.merge(testnet_rpcs).merge("WEB3_CHAIN_ENV" => "testnet")
                       .except("ALCHEMY_POLYGON_RPC_URL", "ORACLE_MINTER_PRIVATE_KEY")
        expect(described_class.violations(env, signer_process: false, web_process: false))
          .not_to include(a_string_matching(/\[chain\].*ALCHEMY_POLYGON_RPC_URL/))
      end

      # The axis must not soften the OTHER axes: a testnet contract address is still an
      # address, and an unfilled one is still the silent-failure class boot exists to catch.
      it "still flags a malformed contract address on a testnet slot" do
        env = clean_env.merge(testnet_rpcs).merge("WEB3_CHAIN_ENV" => "testnet",
                                                  "CARBON_COIN_CONTRACT_ADDRESS" => "REQUIRED_SECRET_NOT_SET")
        expect(described_class.violations(env)).to include(a_string_matching(/\[address\].*40-hex/))
      end
    end

    # --- oracle signer keys: presence + format ----------------------------

    it "flags a missing minting oracle key (no dedicated key — the legacy fallback is retired)" do
      env = clean_env.except("ORACLE_MINTER_PRIVATE_KEY")
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*minting/))
    end

    it "flags a retired ORACLE_PRIVATE_KEY even when it holds a valid key [INF.22]" do
      # No code reads the legacy name anymore — a value here is zombie deploy-config
      # and a pure plaintext liability on an untrusted provider.
      env = clean_env.merge("ORACLE_PRIVATE_KEY" => "a" * 64)
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*RETIRED/))
    end

    it "flags a retired ORACLE_PRIVATE_KEY that is present-but-empty" do
      env = clean_env.merge("ORACLE_PRIVATE_KEY" => "")
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*RETIRED/))
    end

    it "flags a malformed aux signer key (present but not hex)" do
      env = clean_env.merge("ORACLE_ETHERISC_PRIVATE_KEY" => "not-a-hex-key")
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*hex/))
    end

    it "accepts a 0x-prefixed key" do
      env = clean_env.merge("ORACLE_MINTER_PRIVATE_KEY" => "0x#{'b' * 64}")
      expect(described_class.violations(env)).to be_empty
    end

    it "flags an empty-string specific key (Kamal empty-inject would KeyError at signing)" do
      # ENV.fetch returns "" when the key exists-but-blank → Eth::Key raises. The guard must catch it.
      env = clean_env.merge("ORACLE_MINTER_PRIVATE_KEY" => "")
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*ORACLE_MINTER_PRIVATE_KEY.*hex/))
    end

    # --- oracle lock-key collision (ARCH.47) ------------------------------

    it "flags a legacy-only env as retired + both signer keys missing (no silent fallback)" do
      # Pre-split deploy config: only the shared base key set. The guard must refuse it
      # loudly on all three counts rather than let the roles silently resolve anywhere.
      violations = described_class.violations(mainnet_rpcs.merge("ORACLE_PRIVATE_KEY" => "a" * 64))
      expect(violations).to include(a_string_matching(/RETIRED/))
      expect(violations).to include(a_string_matching(/minting/))
      expect(violations).to include(a_string_matching(/slashing/))
    end

    it "flags identical specific minter + slasher keys" do
      env = mainnet_rpcs.merge(
        "ORACLE_MINTER_PRIVATE_KEY"  => "e" * 64,
        "ORACLE_SLASHER_PRIVATE_KEY" => "e" * 64
      )
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*SAME signer key/))
    end

    it "flags a 0x-vs-bare collision (same secret, different prefix)" do
      env = mainnet_rpcs.merge(
        "ORACLE_MINTER_PRIVATE_KEY"  => "0x#{'e' * 64}",
        "ORACLE_SLASHER_PRIVATE_KEY" => "e" * 64
      )
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*SAME signer key/))
    end

    it "does NOT flag a collision when minter and slasher differ" do
      expect(described_class.violations(clean_env)).not_to include(a_string_matching(/SAME signer key/))
    end

    # --- silent-address set: presence + format (the silent-failure class) ----

    it "flags a missing DAO_TREASURY_ADDRESS in the signer process" do
      env = clean_env.except("DAO_TREASURY_ADDRESS")
      expect(described_class.violations(env)).to include(a_string_matching(/\[address\].*DAO_TREASURY_ADDRESS.*not set/))
    end

    it "flags a missing SCC contract address (chain-audit would report a false 'all clean')" do
      env = clean_env.except("CARBON_COIN_CONTRACT_ADDRESS")
      expect(described_class.violations(env))
        .to include(a_string_matching(/\[address\].*CARBON_COIN_CONTRACT_ADDRESS.*not set/))
    end

    it "flags the Kamal deploy placeholder (present-but-garbage, the likeliest real misconfig)" do
      env = clean_env.merge("DAO_TREASURY_ADDRESS" => "REQUIRED_SECRET_NOT_SET")
      expect(described_class.violations(env)).to include(a_string_matching(/\[address\].*40-hex/))
    end

    # [ARCH.56] The shape check cannot see this one: 40 hex stay 40 hex after a typo.
    it "flags a well-formed address whose EIP-55 checksum does not match (mistyped char)" do
      env = clean_env.merge("DAO_TREASURY_ADDRESS" => "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9A")
      expect(described_class.violations(env))
        .to include(a_string_matching(/\[address\].*DAO_TREASURY_ADDRESS.*EIP-55/))
    end

    it "accepts an all-lowercase address (unchecksummed by design, not a misconfig)" do
      env = clean_env.merge("DAO_TREASURY_ADDRESS" => "0xab5801a7d398351b8be11c439e05c5b3259aec9b")
      expect(described_class.violations(env)).not_to include(a_string_matching(/DAO_TREASURY_ADDRESS/))
    end

    it "never echoes the malformed value into the violation (could be a mispasted secret)" do
      env = clean_env.merge("DAO_TREASURY_ADDRESS" => "deadbeef-mispasted-value")
      expect(described_class.violations(env).join).not_to include("deadbeef")
    end

    # --- Solana signer set: presence (no stub mode; batch loop has no escalation) ---

    it "flags a missing Solana credential in the signer process" do
      env = clean_env.except("SOLANA_WALLET_KEYPAIR")
      expect(described_class.violations(env))
        .to include(a_string_matching(/\[solana\].*SOLANA_WALLET_KEYPAIR.*not set/))
    end

    # --- process scoping: THREE classes, not two ---------------------------
    #
    # 🔴 This block used to be one context named "(web / coap containers)" asserting
    # that neither demands an address, "because web/coap never mint/audit". Half of
    # that parenthesis was false and the spec PINNED it: web does not mint, but it
    # audits — `SystemAuditsController#index` → `ChainAuditService` →
    # `ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")` under a `rescue StandardError`
    # that returns `delta: 0, critical: false`. So on a web-only slot an UNSET SCC
    # address booted clean and reported a permanent false "all clean", while a mere
    # placeholder refused the boot — opposite verdicts on the same consumer, and the
    # quiet one was the dangerous one. Splitting the context is the fix: coap and web
    # are different processes and were never interchangeable.

    context "when the process is coap (neither signs nor serves)" do
      let(:kwargs) { { signer_process: false, web_process: false } }

      it "does not demand key presence — a keyless env is clean" do
        expect(described_class.violations(mainnet_rpcs, **kwargs)).to be_empty
      end

      it "still flags a malformed key that IS present" do
        env = mainnet_rpcs.merge("ORACLE_MINTER_PRIVATE_KEY" => "not-a-hex-key")
        expect(described_class.violations(env, **kwargs))
          .to include(a_string_matching(/\[oracle-key\].*hex/))
      end

      it "still flags a lock-key collision when both keys are present" do
        env = mainnet_rpcs.merge(
          "ORACLE_MINTER_PRIVATE_KEY"  => "e" * 64,
          "ORACLE_SLASHER_PRIVATE_KEY" => "e" * 64
        )
        expect(described_class.violations(env, **kwargs))
          .to include(a_string_matching(/SAME signer key/))
      end

      it "still flags a testnet RPC" do
        env = mainnet_rpcs.merge("SOLANA_RPC_URL" => "https://api.devnet.solana.com")
        expect(described_class.violations(env, **kwargs))
          .to include(a_string_matching(/\[chain\].*TESTNET/))
      end

      it "demands NO address — coap.env carries none (observation, not a gated invariant)" do
        violations = described_class.violations(mainnet_rpcs, **kwargs)
        expect(violations).not_to include(a_string_matching(/\[address\]/))
        expect(violations).not_to include(a_string_matching(/\[solana\]/))
      end

      # [INF.27 Q3 ⚖️ 2026-09-01] Format is scoped like presence: a class that reads no
      # address judges none. The Kamal `coap` role inherits the base env.clear placeholders
      # and used to refuse its boot on three `[address]` violations it could never act on —
      # measured by resolving the role through Kamal::Configuration (see the manifest
      # examples in spec/deploy/web3_env_loudness_spec.rb).
      it "ignores a malformed address that IS present — coap reads none, so it judges none" do
        env = mainnet_rpcs.merge("DAO_TREASURY_ADDRESS" => "REQUIRED_SECRET_NOT_SET",
                                 "CARBON_COIN_CONTRACT_ADDRESS" => "not-an-address")
        expect(described_class.violations(env, **kwargs)).not_to include(a_string_matching(/\[address\]/))
      end

      it "does not demand the Polygon RPC — there is no audit read-site in this process" do
        env = mainnet_rpcs.except("ALCHEMY_POLYGON_RPC_URL")
        expect(described_class.violations(env, **kwargs)).not_to include(a_string_matching(/\[rpc\]/))
      end
    end

    context "when the process is web (serves requests, holds no signer key)" do
      let(:kwargs) { { signer_process: false, web_process: true } }

      it "demands the SCC address — its read-site is controller-reachable" do
        expect(described_class.violations(mainnet_rpcs, **kwargs))
          .to include(a_string_matching(/\[address\].*CARBON_COIN_CONTRACT_ADDRESS.*not set/))
      end

      it "does NOT demand the job-only addresses (they have no web read-site)" do
        violations = described_class.violations(mainnet_rpcs, **kwargs)
        expect(violations).not_to include(a_string_matching(/DAO_TREASURY_ADDRESS.*not set/))
        expect(violations).not_to include(a_string_matching(/FOREST_COIN_CONTRACT_ADDRESS.*not set/))
      end

      # [INF.27] Since 2026-09-02 the web class reads TWO addresses: SCC (ChainAuditService) and the
      # StateRootAnchor (Mrv::LineageReportService via a rake in the web container).
      it "demands the anchor address — its read-site is an MRV rake inside the web container" do
        expect(described_class.violations(mainnet_rpcs, **kwargs))
          .to include(a_string_matching(/\[address\].*ETHEREUM_ANCHOR_CONTRACT.*not set/))
      end

      it "is clean once the two web-read addresses (SCC + anchor) are present — the demand is narrow" do
        env = mainnet_rpcs.merge("CARBON_COIN_CONTRACT_ADDRESS" => "0x" + ("a" * 40), "ETHEREUM_ANCHOR_CONTRACT" => "0x" + ("d" * 40))
        expect(described_class.violations(env, **kwargs)).to be_empty
      end

      it "does not demand signer keys or the Solana set" do
        violations = described_class.violations(mainnet_rpcs, **kwargs)
        expect(violations).not_to include(a_string_matching(/\[oracle-key\]/))
        expect(violations).not_to include(a_string_matching(/\[solana\]/))
      end

      # [INF.27 Q3] Format follows the same per-variable scope as presence, so on a web-only
      # slot the two job-only placeholders are not this container's problem — only the one
      # address web actually reads is judged, whatever value it carries.
      it "judges the format only of the address it reads — placeholder treasury passes, placeholder SCC refuses" do
        env = mainnet_rpcs.merge("DAO_TREASURY_ADDRESS"         => "REQUIRED_SECRET_NOT_SET",
                                 "FOREST_COIN_CONTRACT_ADDRESS" => "REQUIRED_SECRET_NOT_SET",
                                 "CARBON_COIN_CONTRACT_ADDRESS" => "REQUIRED_SECRET_NOT_SET",
                                 "ETHEREUM_ANCHOR_CONTRACT" => "0x" + ("d" * 40))
        violations = described_class.violations(env, **kwargs).grep(/\[address\]/)
        expect(violations.size).to eq(1)
        expect(violations.first).to match(/CARBON_COIN_CONTRACT_ADDRESS.*40-hex/)
      end

      # [INF.27 Q1] ChainAuditService swallows a MISSING RPC exactly as it swallows a missing
      # address — KeyError and `Eth::Client.create("")` land in the same `rescue StandardError`
      # and return `delta: 0, critical: false`, so boot is this var's only loud moment on web.
      it "demands the Polygon RPC — its absence is swallowed into a false 'all clean'" do
        env = mainnet_rpcs.merge("CARBON_COIN_CONTRACT_ADDRESS" => "0x#{'a' * 40}")
                          .except("ALCHEMY_POLYGON_RPC_URL")
        expect(described_class.violations(env, **kwargs))
          .to include(a_string_matching(/\[rpc\].*ALCHEMY_POLYGON_RPC_URL.*not set/))
      end

      it "treats a present-but-empty Polygon RPC as absent (the Kamal empty-inject shape)" do
        env = mainnet_rpcs.merge("CARBON_COIN_CONTRACT_ADDRESS" => "0x#{'a' * 40}",
                                 "ALCHEMY_POLYGON_RPC_URL"      => "")
        expect(described_class.violations(env, **kwargs))
          .to include(a_string_matching(/\[rpc\].*ALCHEMY_POLYGON_RPC_URL/))
      end
    end

    # The JOB combination, and it is here because an adversarial pass found it MISSING:
    # the initializer hands Sidekiq `{signer_process: true, web_process: false}`, and that
    # exact pair appeared in no example — every other production class had its own context,
    # and the one holding the money keys did not. The default `(true, true)` does NOT stand
    # in for it: no real process is ever both.
    context "when the process is job (signs, serves nothing)" do
      let(:kwargs) { { signer_process: true, web_process: false } }

      it "demands ALL FOUR addresses — the signer reads every one of them" do
        violations = described_class.violations(mainnet_rpcs, **kwargs)
        %w[DAO_TREASURY_ADDRESS CARBON_COIN_CONTRACT_ADDRESS FOREST_COIN_CONTRACT_ADDRESS ETHEREUM_ANCHOR_CONTRACT].each do |var|
          expect(violations).to include(a_string_matching(/\[address\].*#{var}.*not set/))
        end
      end

      it "judges the FORMAT of every address too — a placeholder treasury refuses the signer" do
        env = mainnet_rpcs.merge("DAO_TREASURY_ADDRESS" => "REQUIRED_SECRET_NOT_SET")
        expect(described_class.violations(env, **kwargs))
          .to include(a_string_matching(/\[address\].*DAO_TREASURY_ADDRESS.*40-hex/))
      end

      # Every minting/rollback site is a bare `ENV.fetch` → KeyError deep in a worker → the
      # DeadSet, silently. Same class as the boot-critical oracle keys, same loud moment.
      it "demands the Polygon RPC (every minting site is a bare ENV.fetch → silent DeadSet)" do
        env = mainnet_rpcs.except("ALCHEMY_POLYGON_RPC_URL")
        expect(described_class.violations(env, **kwargs))
          .to include(a_string_matching(/\[rpc\].*ALCHEMY_POLYGON_RPC_URL.*not set/))
      end
    end

    # Both axes default to the STRICT side, mirroring `chain_env`'s `mainnet`
    # default: a caller that forgets an axis may over-refuse, never under-protect.
    it "defaults web_process to the strict side" do
      expect(described_class.violations(mainnet_rpcs, signer_process: false))
        .to include(a_string_matching(/\[address\].*CARBON_COIN_CONTRACT_ADDRESS.*not set/))
    end

    # 🔒 DECLARED CEILING of the process-scoping block — rewritten 2026-09-02 from a fresh
    # mutation run (four mutants, each planted alone, the file restored byte-identically
    # between them, `cmp`-checked; the earlier ceiling described the 09-01 fix and no longer
    # named what the block proves). Read the red SETS, not the green bar:
    #   · revert Q3 (scope only the blank branch, format runs wherever a value is present)
    #     → RED ×4: "ignores a malformed address…" (coap), "judges the format only…" (web),
    #       plus BOTH manifest examples in spec/deploy/web3_env_loudness_spec.rb;
    #   · drop the scope line entirely (unconditional verdict) → RED ×8 — every coap example,
    #     both web negatives and both manifest examples;
    #   · unwire `rpc_violations` from `.violations` → RED ×3, exactly the `[rpc]` examples
    #     (web ×2, job ×1) and nothing else;
    #   · make the rpc rule blind to present-but-empty (`present?` → `key?`) → RED ×1, the
    #     "present-but-empty Polygon RPC" example — ⚠️ the FIRST planting of this mutant was a
    #     no-op that landed green: `String#sub` hit the first `next if env[var].present?` in
    #     the file, which belongs to `oracle_violations`, so the run measured the wrong
    #     subject (§Guard-craft #65). A mutant must be checked IN PLACE before its colour
    #     means anything.
    # ⛔ Still not evidence for this block, and kept for other reasons: "does not demand
    # signer keys or the Solana set" (pins the older signer scoping of OTHER axes) and
    # "demands ALL FOUR addresses" (green under every mutant here; it is the only example
    # covering the production job combination and reds only when BOTH kwargs are required
    # at once). Two examples surviving all four mutants is the honest count.
  end
end
