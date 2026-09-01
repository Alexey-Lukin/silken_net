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
    # The silent-address set (treasury + SCC/SFC) and the Solana signer set are part of a
    # clean signer env: their read-sites fail SILENT (rescue umbrellas / no-escalation batch
    # loop), so boot presence is the only loud gate they have.
    let(:clean_env) do
      mainnet_rpcs.merge(
        "ORACLE_MINTER_PRIVATE_KEY"      => "b" * 64,
        "ORACLE_SLASHER_PRIVATE_KEY"     => "c" * 64,
        "DAO_TREASURY_ADDRESS"           => "0x#{'a' * 40}",
        "CARBON_COIN_CONTRACT_ADDRESS"   => "0x#{'b' * 40}",
        "FOREST_COIN_CONTRACT_ADDRESS"   => "0x#{'c' * 40}",
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

      it "does not demand ALCHEMY_POLYGON_RPC_URL on a testnet slot with no minter key" do
        env = clean_env.merge(testnet_rpcs).merge("WEB3_CHAIN_ENV" => "testnet")
                       .except("ALCHEMY_POLYGON_RPC_URL", "ORACLE_MINTER_PRIVATE_KEY")
        expect(described_class.violations(env, signer_process: false))
          .not_to include(a_string_matching(/ALCHEMY_POLYGON_RPC_URL/))
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

      it "still flags a malformed treasury address that IS present" do
        env = mainnet_rpcs.merge("DAO_TREASURY_ADDRESS" => "not-an-address")
        expect(described_class.violations(env, **kwargs))
          .to include(a_string_matching(/\[address\].*40-hex/))
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

      it "is clean once the SCC address is present — the demand is narrow" do
        env = mainnet_rpcs.merge("CARBON_COIN_CONTRACT_ADDRESS" => "0x" + ("a" * 40))
        expect(described_class.violations(env, **kwargs)).to be_empty
      end

      it "does not demand signer keys or the Solana set" do
        violations = described_class.violations(mainnet_rpcs, **kwargs)
        expect(violations).not_to include(a_string_matching(/\[oracle-key\]/))
        expect(violations).not_to include(a_string_matching(/\[solana\]/))
      end
    end

    # The JOB combination, and it is here because an adversarial pass found it MISSING:
    # the initializer hands Sidekiq `{signer_process: true, web_process: false}`, and that
    # exact pair appeared in no example — every other production class had its own context,
    # and the one holding the money keys did not. The default `(true, true)` does NOT stand
    # in for it: no real process is ever both.
    context "when the process is job (signs, serves nothing)" do
      let(:kwargs) { { signer_process: true, web_process: false } }

      it "demands ALL THREE addresses — the signer reads every one of them" do
        violations = described_class.violations(mainnet_rpcs, **kwargs)
        %w[DAO_TREASURY_ADDRESS CARBON_COIN_CONTRACT_ADDRESS FOREST_COIN_CONTRACT_ADDRESS].each do |var|
          expect(violations).to include(a_string_matching(/\[address\].*#{var}.*not set/))
        end
      end
    end

    # Both axes default to the STRICT side, mirroring `chain_env`'s `mainnet`
    # default: a caller that forgets an axis may over-refuse, never under-protect.
    it "defaults web_process to the strict side" do
      expect(described_class.violations(mainnet_rpcs, signer_process: false))
        .to include(a_string_matching(/\[address\].*CARBON_COIN_CONTRACT_ADDRESS.*not set/))
    end

    # 🔒 DECLARED CEILING of this block, written because an adversarial pass measured it and
    # the first version of this comment would have overstated the coverage. The two mutations
    # this block is verified against are NOT caught evenly:
    #   · revert the fix (`next unless signer_process`) → RED: "demands the SCC address" and
    #     "defaults web_process to the strict side". TWO examples, not five.
    #   · demand unconditionally (drop the `next`) → RED: both coap examples plus
    #     "does NOT demand the job-only addresses" and "is clean once the SCC address is present".
    # ⛔ So TWO examples survive BOTH mutations and the revert, and both are regression pins
    # rather than evidence for this fix — do not count either as such:
    #   · "does not demand signer keys or the Solana set" — pins the pre-existing signer
    #     scoping of OTHER axes (`[oracle-key]`, `[solana]`), which this change never touched;
    #   · "demands ALL THREE addresses" (the job context) — its result is decided purely by
    #     `signer_process`, so it is green under the current code, the revert AND the
    #     unconditional demand alike. ⚠️ It was still worth adding: it is the only example
    #     covering the production job combination, and it IS load-bearing against a different
    #     mutation — requiring BOTH axes at once (`signer_process && web_process`) reds it and
    #     nothing else. Naming that here because the first version of this ceiling listed one
    #     survivor and read as a complete audit of the block, which it was not.
  end
end
