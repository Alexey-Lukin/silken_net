# frozen_string_literal: true

module Wallets
  class BalanceFrame < ApplicationComponent
    def initialize(wallet:)
      @wallet = wallet
    end

    def view_template
      turbo_frame_tag "wallet_balance_frame_#{@wallet.id}" do
        render Wallets::BalanceDisplay.new(wallet: @wallet)
      end
    end
  end
end
