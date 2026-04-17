# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::MetadataFrame do
  def mock_wallet(id: 1, crypto_public_address: "0xDEAD1234BEEF5678CAFE", locked_balance: 0, available_balance: 42.5, esg_retired_balance: 0)
    OpenStruct.new(
      id: id,
      crypto_public_address: crypto_public_address,
      locked_balance: locked_balance,
      available_balance: available_balance,
      esg_retired_balance: esg_retired_balance
    )
  end

  describe "rendering" do
    let(:html) { render_component(wallet: mock_wallet) }

    it "renders the turbo frame tag with correct id" do
      expect(html).to include("wallet_metadata_frame_1")
    end

    it "displays the Blockchain Identity heading" do
      expect(html).to include("Blockchain Identity")
    end

    it "displays the Polygon Address label" do
      expect(html).to include("Polygon Address")
    end

    it "displays the Network name" do
      expect(html).to include("Polygon PoS (Mainnet)")
    end

    it "renders the crypto public address" do
      expect(html).to include("0xDEAD1234BEEF5678CAFE")
    end
  end

  describe "balance display" do
    let(:html) { render_component(wallet: mock_wallet(locked_balance: 10.5, available_balance: 89.5, esg_retired_balance: 5.25)) }

    it "displays Locked Balance label" do
      expect(html).to include("Locked Balance")
    end

    it "displays locked balance value" do
      expect(html).to include("10.5")
    end

    it "displays Available Balance label" do
      expect(html).to include("Available Balance")
    end

    it "displays available balance value" do
      expect(html).to include("89.5")
    end

    it "displays ESG Retired label" do
      expect(html).to include("ESG Retired")
    end

    it "displays ESG retired balance value" do
      expect(html).to include("5.25")
    end

    it "shows SCC unit labels" do
      expect(html).to include("SCC")
    end
  end

  describe "not provisioned wallet" do
    it "shows NOT_PROVISIONED when address is blank" do
      wallet = mock_wallet(crypto_public_address: nil)
      wallet.define_singleton_method(:crypto_public_address) { nil }
      # Override present? for nil
      html = render_component(wallet: wallet)
      expect(html).to include("NOT_PROVISIONED")
    end

    it "shows NOT_PROVISIONED when address is empty string" do
      wallet = mock_wallet(crypto_public_address: "")
      html = render_component(wallet: wallet)
      expect(html).to include("NOT_PROVISIONED")
    end
  end

  describe "turbo frame id uniqueness" do
    it "uses wallet id in frame id" do
      html = render_component(wallet: mock_wallet(id: 99))
      expect(html).to include("wallet_metadata_frame_99")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(wallet: mock_wallet) }

    it "uses text-tiny for labels" do
      expect(html).to include("text-tiny")
    end

    it "uses gaia design tokens for text" do
      expect(html).to include("text-gaia-text-muted")
    end

    it "uses status-warning-text for locked balance" do
      expect(html).to include("text-status-warning-text")
    end

    it "uses gaia-primary for available balance" do
      expect(html).to include("text-gaia-primary")
    end
  end
end
