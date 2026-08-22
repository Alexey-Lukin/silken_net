# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Security::Web3NetworkGuard do
  describe ".violations" do
    # Mainnet RPC endpoints, no oracle keys — the chain half of a clean env.
    let(:chain_env) do
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
      chain_env.merge(
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

    # [E.49] The blank-skip misses CELO_RPC_URL: unset falls back to Alfajores TESTNET in
    # code (no raise) — so presence is demanded conditionally, only when the Celo path is
    # armed (its signer key present).
    it "flags a blank CELO_RPC_URL when the Celo signer key is present (silent Alfajores fallback)" do
      env = clean_env.merge("ORACLE_CELO_PRIVATE_KEY" => "d" * 64)
      expect(described_class.violations(env)).to include(a_string_matching(/\[chain\].*CELO_RPC_URL.*Alfajores/))
    end

    it "does not demand CELO_RPC_URL while the Celo path is unarmed (no signer key)" do
      expect(described_class.violations(clean_env)).not_to include(a_string_matching(/CELO_RPC_URL/))
    end

    it "accepts an armed Celo path with a mainnet RPC" do
      env = clean_env.merge("ORACLE_CELO_PRIVATE_KEY" => "d" * 64, "CELO_RPC_URL" => "https://forno.celo.org")
      expect(described_class.violations(env)).to be_empty
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
      violations = described_class.violations(chain_env.merge("ORACLE_PRIVATE_KEY" => "a" * 64))
      expect(violations).to include(a_string_matching(/RETIRED/))
      expect(violations).to include(a_string_matching(/minting/))
      expect(violations).to include(a_string_matching(/slashing/))
    end

    it "flags identical specific minter + slasher keys" do
      env = chain_env.merge(
        "ORACLE_MINTER_PRIVATE_KEY"  => "e" * 64,
        "ORACLE_SLASHER_PRIVATE_KEY" => "e" * 64
      )
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*SAME signer key/))
    end

    it "flags a 0x-vs-bare collision (same secret, different prefix)" do
      env = chain_env.merge(
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

    # --- process scoping: web/coap boot keyless by design ------------------

    context "when signer_process: false (web / coap containers)" do
      it "does not demand key presence — a keyless env is clean" do
        expect(described_class.violations(chain_env, signer_process: false)).to be_empty
      end

      it "still flags a malformed key that IS present" do
        env = chain_env.merge("ORACLE_MINTER_PRIVATE_KEY" => "not-a-hex-key")
        expect(described_class.violations(env, signer_process: false))
          .to include(a_string_matching(/\[oracle-key\].*hex/))
      end

      it "still flags a lock-key collision when both keys are present" do
        env = chain_env.merge(
          "ORACLE_MINTER_PRIVATE_KEY"  => "e" * 64,
          "ORACLE_SLASHER_PRIVATE_KEY" => "e" * 64
        )
        expect(described_class.violations(env, signer_process: false))
          .to include(a_string_matching(/SAME signer key/))
      end

      it "still flags a testnet RPC" do
        env = chain_env.merge("SOLANA_RPC_URL" => "https://api.devnet.solana.com")
        expect(described_class.violations(env, signer_process: false))
          .to include(a_string_matching(/\[chain\].*TESTNET/))
      end

      it "does not demand the silent-address or Solana sets (web/coap never mint/audit)" do
        violations = described_class.violations(chain_env, signer_process: false)
        expect(violations).not_to include(a_string_matching(/\[address\]/))
        expect(violations).not_to include(a_string_matching(/\[solana\]/))
      end

      it "still flags a malformed treasury address that IS present" do
        env = chain_env.merge("DAO_TREASURY_ADDRESS" => "not-an-address")
        expect(described_class.violations(env, signer_process: false))
          .to include(a_string_matching(/\[address\].*40-hex/))
      end
    end
  end
end
