# frozen_string_literal: true

require "bigdecimal"

module Web3
  # = ===================================================================
  # 💱 WEI CONVERTER (Shared Token Amount Conversion)
  # = ===================================================================
  # Централізований конвертер для перетворення людських сум (SCC/SFC)
  # у wei-формат (ERC-20 standard: 10^18).
  #
  # Використовує BigDecimal для абсолютної точності фінансових операцій.
  # Float арифметика (amount.to_f * 10**18) дає похибку в кількох wei,
  # що неприпустимо для Web3-транзакцій і Slashing Protocol.
  #
  # Використання:
  #   Web3::WeiConverter.to_wei(1.5)          # => 1_500_000_000_000_000_000
  #   Web3::WeiConverter.to_wei("0.001", 6)   # => 1000 (USDC decimals)
  module WeiConverter
    # Стандартна розрядність ERC-20 токена
    DEFAULT_DECIMALS = 18

    # Конвертує суму токена у найменші одиниці (wei).
    #
    # @param amount [Numeric, String] сума у людському форматі
    # @param decimals [Integer] кількість десяткових знаків токена (default: 18)
    # @return [Integer] сума в wei
    def self.to_wei(amount, decimals = DEFAULT_DECIMALS)
      (BigDecimal(amount.to_s) * 10**decimals).to_i
    end
  end
end
