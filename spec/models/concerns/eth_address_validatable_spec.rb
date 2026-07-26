# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EthAddressValidatable do
  describe "when included in Organization" do
    it "accepts valid Ethereum address" do
      org = build(:organization, crypto_public_address: "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B")
      expect(org).to be_valid
    end

    it "rejects invalid address" do
      org = build(:organization, crypto_public_address: "not-a-wallet")
      expect(org).not_to be_valid
      expect(org.errors[:crypto_public_address]).to be_present
    end

    it "rejects nil when presence is required" do
      org = build(:organization, crypto_public_address: nil)
      expect(org).not_to be_valid
    end
  end

  describe "when included in Wallet" do
    it "accepts valid Ethereum address" do
      wallet = create(:tree).wallet
      wallet.crypto_public_address = "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B"
      expect(wallet).to be_valid
    end

    it "allows blank address" do
      wallet = create(:tree).wallet
      wallet.crypto_public_address = ""
      expect(wallet).to be_valid
    end

    it "rejects invalid address format" do
      wallet = create(:tree).wallet
      wallet.crypto_public_address = "invalid"
      expect(wallet).not_to be_valid
      expect(wallet.errors[:crypto_public_address]).to be_present
    end
  end

  describe "when included in BlockchainTransaction" do
    it "accepts valid Ethereum address" do
      tx = build(:blockchain_transaction, to_address: "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B")
      expect(tx).to be_valid
    end

    it "rejects invalid address" do
      tx = build(:blockchain_transaction, to_address: "invalid")
      expect(tx).not_to be_valid
      expect(tx.errors[:to_address]).to be_present
    end

    it "requires address presence" do
      tx = build(:blockchain_transaction, to_address: nil)
      expect(tx).not_to be_valid
    end
  end

  # [ARCH.56] EIP-55: shape alone cannot see a typo — 40 hex stay 40 hex. A mixed-case
  # address carries its own checksum, so a mismatch is a mistyped character.
  describe "EIP-55 checksum layer" do
    # Same address as the happy-path examples above with ONE final character flipped
    # (…aeC9B → …aeC9A) — the exact single-char typo class the checksum exists to catch.
    let(:mistyped) { "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9A" }

    it "rejects a mixed-case address whose checksum does not match" do
      org = build(:organization, crypto_public_address: mistyped)

      expect(org).not_to be_valid
      expect(org.errors[:crypto_public_address]).to include(EthAddressValidatable::EIP55_MESSAGE)
    end

    it "accepts an all-lowercase address (carries no checksum → nothing to verify)" do
      org = build(:organization, crypto_public_address: mistyped.downcase)
      expect(org).to be_valid
    end

    it "accepts an all-uppercase address (likewise unchecksummed)" do
      org = build(:organization, crypto_public_address: "0x#{mistyped.delete_prefix('0x').upcase}")
      expect(org).to be_valid
    end

    it "reports ONE cause for a malformed address — shape only, no checksum noise" do
      org = build(:organization, crypto_public_address: "not-a-wallet")

      expect(org).not_to be_valid
      expect(org.errors[:crypto_public_address]).to contain_exactly("має бути валідною 0x адресою")
    end

    # The boot guard (`Security::Web3NetworkGuard`) reuses this predicate — One-Home.
    describe ".eip55_valid?" do
      it "is false for a mistyped mixed-case address and true for every accepted form" do
        expect(described_class.eip55_valid?(mistyped)).to be(false)
        expect(described_class.eip55_valid?("0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B")).to be(true)
        expect(described_class.eip55_valid?(mistyped.downcase)).to be(true)
      end
    end
  end

  describe "ETH_ADDRESS_FORMAT constant" do
    it "is accessible from including models" do
      expect(Organization::ETH_ADDRESS_FORMAT).to eq(Wallet::ETH_ADDRESS_FORMAT)
      expect(Wallet::ETH_ADDRESS_FORMAT).to eq(BlockchainTransaction::ETH_ADDRESS_FORMAT)
    end
  end
end
