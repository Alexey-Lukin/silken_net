# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::BalanceFrame do
  def mock_wallet(id: 1, scc_balance: 42.5, locked_balance: 0.0,
                  esg_retired_balance: 0.0)
    wallet = OpenStruct.new(
      id: id,
      scc_balance: scc_balance,
      locked_balance: locked_balance,
      esg_retired_balance: esg_retired_balance
    )
    wallet.define_singleton_method(:model_name) { ActiveModel::Name.new(Wallet) }
    wallet.define_singleton_method(:to_key) { [ id ] }
    wallet.define_singleton_method(:to_param) { id.to_s }
    wallet
  end

  describe "turbo frame wrapper" do
    it "wraps content in a turbo frame tag with the wallet id" do
      html = render_component(wallet: mock_wallet(id: 7))
      expect(html).to include("wallet_balance_frame_7")
    end

    it "uses wallet id 1 in the frame id" do
      html = render_component(wallet: mock_wallet(id: 1))
      expect(html).to include("wallet_balance_frame_1")
    end

    it "uses a unique frame id per wallet" do
      html_a = render_component(wallet: mock_wallet(id: 10))
      html_b = render_component(wallet: mock_wallet(id: 99))
      expect(html_a).to include("wallet_balance_frame_10")
      expect(html_b).to include("wallet_balance_frame_99")
    end
  end

  describe "balance display delegation" do
    let(:html) { render_component(wallet: mock_wallet(scc_balance: 12.3456)) }

    it "renders the SCC balance from BalanceDisplay" do
      expect(html).to include("12.3456")
    end

    it "renders SCC label" do
      expect(html).to include("SCC")
    end
  end

  describe "locked balance" do
    it "shows locked balance when present" do
      html = render_component(wallet: mock_wallet(locked_balance: 5.0))
      expect(html).to include("5.0")
    end
  end

  describe "esg retired balance" do
    it "shows retired balance when present" do
      html = render_component(wallet: mock_wallet(esg_retired_balance: 3.25))
      expect(html).to include("3.25")
    end
  end
end
