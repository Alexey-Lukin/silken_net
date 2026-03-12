# frozen_string_literal: true

require "eth"

module Web3
  # = ===================================================================
  # 🔗 RPC CONNECTION POOL (Thread-Safe Client Caching)
  # = ===================================================================
  # Кешує Eth::Client інстанси per-thread для запобігання:
  # - Повторному встановленню TCP з'єднань при кожному виклику worker'а
  # - Rate-limiting від RPC провайдерів (Alchemy, Infura)
  # - Зайвому навантаженню на TLS handshake у Sidekiq-потоках
  #
  # Thread-safety: кожен Sidekiq thread отримує власний клієнт через Thread.current.
  # Це безпечно, оскільки Sidekiq worker'и виконуються ізольовано в межах потоку.
  #
  # Використання:
  #   client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
  #   client.eth_get_transaction_receipt(tx_hash)
  module RpcConnectionPool
    THREAD_KEY_PREFIX = :web3_rpc_client_

    class << self
      # Повертає кешований Eth::Client для вказаного RPC URL env key.
      # Клієнт створюється один раз per-thread і перевикористовується.
      #
      # @param rpc_url_env_key [String] назва ENV-змінної з RPC URL (e.g., "ALCHEMY_POLYGON_RPC_URL")
      # @param fallback [String, nil] резервний URL, якщо ENV-змінна відсутня (e.g., testnet URL)
      # @return [Eth::Client]
      def client_for(rpc_url_env_key, fallback: nil)
        thread_key = :"#{THREAD_KEY_PREFIX}#{rpc_url_env_key}"
        Thread.current[thread_key] ||= begin
          rpc_url = fallback ? ENV.fetch(rpc_url_env_key, fallback) : ENV.fetch(rpc_url_env_key)
          Eth::Client.create(rpc_url)
        end
      end

      # Скидає всі кешовані клієнти в поточному потоці.
      # Використовується при зміні RPC URL або в тестах.
      def reset!
        prefix = THREAD_KEY_PREFIX.to_s
        Thread.current.keys.each do |key|
          Thread.current[key] = nil if key.to_s.start_with?(prefix)
        end
      end
    end
  end
end
