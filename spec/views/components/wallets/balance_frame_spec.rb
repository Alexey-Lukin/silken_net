# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::BalanceFrame do
  def mock_wallet(id: 1, balance: 42.5, locked_balance: 0.0,
                  esg_retired_balance: 0.0)
    wallet = OpenStruct.new(
      id: id,
      balance: balance,
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
    # [ARCH.88] Значення кратне кроку джерела (0.01) — див. `balance_display_spec`.
    let(:html) { render_component(wallet: mock_wallet(balance: 12.35)) }

    it "renders the growth-point balance from BalanceDisplay" do
      expect(html).to include("12.35")
    end

    it "renders the GP unit label" do
      # [ARCH.88] Пара, що РОЗРІЗНЯЄ: доти пін ловив «SCC» із декоративного
      # водяного знака й лишався зеленим навіть при виправленій мітці.
      expect(html).to include("GP")
      expect(html).not_to include("SCC")
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
