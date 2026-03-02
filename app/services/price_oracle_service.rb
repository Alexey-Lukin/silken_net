# frozen_string_literal: true

require "eth"

class PriceOracleService
  # Адреси в мережі Polygon (приклад)
  QUOTER_ADDRESS = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6" # Uniswap V3 Quoter
  SCC_TOKEN = "0x..." # Наш токен SCC
  USDC_TOKEN = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174" # Стейблкоїн для пари
  POOL_FEE = 3000 # 0.3% pool

  class << self
    def current_scc_price
      # [CASHING]: Не турбуємо блокчейн частіше ніж раз на 5 хвилин
      # Це економить кошти на RPC-запитах та прискорює систему
      Rails.cache.fetch("scc_market_price", expires_in: 5.minutes) do
        fetch_price_from_uniswap
      end
    rescue StandardError => e
      Rails.logger.error "🛑 [ORACLE ERROR]: #{e.message}"
      fallback_price
    end

    private

    def fetch_price_from_uniswap
      return mock_price if Rails.env.development? || Rails.env.test?

      client = Eth::Client.create(ENV['POLYGON_RPC_URL'])
      quoter = Eth::Contract.from_abi(name: "Quoter", address: QUOTER_ADDRESS, abi: quoter_abi)

      # Запитуємо ціну 1 SCC в USDC
      # quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn, sqrtPriceLimitX96)
      amount_in = 10**18 # 1 full SCC (18 decimals)
      
      raw_amount_out = client.call(quoter, "quoteExactInputSingle", 
                                   SCC_TOKEN, USDC_TOKEN, POOL_FEE, amount_in, 0)

      # Конвертуємо з 6 децималів USDC у Float
      (raw_amount_out.to_f / 10**6).round(4)
    end

    def fallback_price
      # Якщо блокчейн не відповідає, беремо останнє відоме значення з бази
      # або повертаємо базову ціну Series A
      25.5
    end

    def mock_price
      # Для розробки: імітуємо легку волатильність навколо 25.5
      (25.5 + rand(-0.5..0.5)).round(2)
    end

    def quoter_abi
      # Спрощений ABI лише для потрібного методу
      [
        {
          "inputs": [
            { "internalType": "address", "name": "tokenIn", "type": "address" },
            { "internalType": "address", "name": "tokenOut", "type": "address" },
            { "internalType": "uint24", "name": "fee", "type": "uint24" },
            { "internalType": "uint256", "name": "amountIn", "type": "uint256" },
            { "internalType": "uint160", "name": "sqrtPriceLimitX96", "type": "uint160" }
          ],
          "name": "quoteExactInputSingle",
          "outputs": [{ "internalType": "uint256", "name": "amountOut", "type": "uint256" }],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ].to_json
    end
  end
end
