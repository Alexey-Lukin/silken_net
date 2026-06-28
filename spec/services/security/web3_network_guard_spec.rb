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
    # address and collide on a single oracle lock (the canon 07_01 §B-02 rule, now boot-enforced).
    let(:clean_env) do
      chain_env.merge(
        "ORACLE_MINTER_PRIVATE_KEY"  => "b" * 64,
        "ORACLE_SLASHER_PRIVATE_KEY" => "c" * 64
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

    # --- oracle signer keys: presence + format ----------------------------

    it "flags a missing minting oracle key (no specific key, no fallback)" do
      env = clean_env.except("ORACLE_MINTER_PRIVATE_KEY")
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*minting/))
    end

    it "accepts a legacy ORACLE_PRIVATE_KEY present alongside distinct minter + slasher keys" do
      # The fallback is legitimate for Chainlink/Celo/legacy signers as long as the
      # role-specific keys resolve to DIFFERENT addresses than each other.
      env = clean_env.merge("ORACLE_PRIVATE_KEY" => "a" * 64)
      expect(described_class.violations(env)).to be_empty
    end

    it "flags a malformed oracle key" do
      env = clean_env.merge("ORACLE_PRIVATE_KEY" => "not-a-hex-key")
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

    it "flags a shared ORACLE_PRIVATE_KEY fallback (both specific keys absent)" do
      # minter and slasher both resolve to the single base address → one lock key.
      env = chain_env.merge("ORACLE_PRIVATE_KEY" => "a" * 64)
      expect(described_class.violations(env)).to include(a_string_matching(/\[oracle-key\].*SAME signer key/))
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
  end
end
