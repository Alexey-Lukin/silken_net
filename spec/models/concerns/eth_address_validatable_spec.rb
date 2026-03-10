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

  describe "ETH_ADDRESS_FORMAT constant" do
    it "is accessible from including models" do
      expect(Organization::ETH_ADDRESS_FORMAT).to eq(Wallet::ETH_ADDRESS_FORMAT)
      expect(Wallet::ETH_ADDRESS_FORMAT).to eq(BlockchainTransaction::ETH_ADDRESS_FORMAT)
    end
  end
end
