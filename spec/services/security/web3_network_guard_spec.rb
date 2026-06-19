# frozen_string_literal: true

require "rails_helper"

RSpec.describe Security::Web3NetworkGuard do
  describe ".violations" do
    let(:clean_env) do
      {
        "ALCHEMY_POLYGON_RPC_URL"  => "https://polygon-mainnet.g.alchemy.com/v2/key",
        "ALCHEMY_ETHEREUM_RPC_URL" => "https://eth-mainnet.g.alchemy.com/v2/key",
        "SOLANA_RPC_URL"           => "https://api.mainnet-beta.solana.com",
        "ORACLE_PRIVATE_KEY"       => "a" * 64
      }
    end

    it "passes a clean mainnet env" do
      expect(described_class.violations(clean_env)).to be_empty
    end

    # --- A1: chain identity ---------------------------------------------------

    it "flags a Polygon Amoy testnet RPC" do
      env = clean_env.merge("ALCHEMY_POLYGON_RPC_URL" => "https://polygon-amoy.g.alchemy.com/v2/key")
      expect(described_class.violations(env)).to include(a_string_matching(/\[A1\].*TESTNET/))
    end

    it "flags a Solana devnet RPC" do
      env = clean_env.merge("SOLANA_RPC_URL" => "https://api.devnet.solana.com")
      expect(described_class.violations(env)).to include(a_string_matching(/\[A1\].*TESTNET/))
    end

    it "does not false-positive when a marker is glued inside an API-key token" do
      # 'amoy' here is bounded by alnum (…9amoyz…) → the lookaround must not match.
      env = clean_env.merge("ALCHEMY_POLYGON_RPC_URL" => "https://polygon-mainnet.g.alchemy.com/v2/x9amoyz2abc")
      expect(described_class.violations(env)).to be_empty
    end

    # --- A2: oracle signer keys -----------------------------------------------

    it "flags a missing minting oracle key (no specific key, no fallback)" do
      env = clean_env.except("ORACLE_PRIVATE_KEY")
      expect(described_class.violations(env)).to include(a_string_matching(/\[A2\].*minting/))
    end

    it "accepts specific minter+slasher keys without the ORACLE_PRIVATE_KEY fallback" do
      env = clean_env.except("ORACLE_PRIVATE_KEY").merge(
        "ORACLE_MINTER_PRIVATE_KEY"  => "b" * 64,
        "ORACLE_SLASHER_PRIVATE_KEY" => "c" * 64
      )
      expect(described_class.violations(env)).to be_empty
    end

    it "flags a malformed oracle key" do
      env = clean_env.merge("ORACLE_PRIVATE_KEY" => "not-a-hex-key")
      expect(described_class.violations(env)).to include(a_string_matching(/\[A2\].*hex/))
    end

    it "accepts a 0x-prefixed key" do
      env = clean_env.merge("ORACLE_PRIVATE_KEY" => "0x#{'d' * 64}")
      expect(described_class.violations(env)).to be_empty
    end
  end
end
