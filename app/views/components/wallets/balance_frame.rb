# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Wallets
  class BalanceFrame < ApplicationComponent
    # 🔴 [UI.4] Дім target-id балансу — ЧОТИРИ сайти називали цю адресу рукою:
    # продюсер (`Wallet#broadcast_balance_update`), сторінка гаманця, цей компонент
    # і його broadcast-стаб. Вісь має shipping-record у цьому ж репо: два з трьох
    # відомих «продюсер і підписник на різних адресах» були саме розходженням
    # target-id, і жоден дім ІМЕН стрімів їх не накриває. Форма — метод класу на
    # тому, хто фрейм РЕНДЕРИТЬ (прецедент `Actuators::CommandStatusFrame.dom_id`).
    # ⚠️ `dom_id` тут НЕ підходить: він вставляє `param_key` між префіксом і id
    # (`wallet_balance_frame_wallet_42`), тобто перехід на нього був би
    # координованим перейменуванням обох боків, а не заміною.
    def self.dom_id(wallet_id) = "wallet_balance_frame_#{wallet_id}"

    def initialize(wallet:)
      @wallet = wallet
    end

    def view_template
      turbo_frame_tag self.class.dom_id(@wallet.id) do
        render Wallets::BalanceDisplay.new(wallet: @wallet)
      end
    end
  end
end
