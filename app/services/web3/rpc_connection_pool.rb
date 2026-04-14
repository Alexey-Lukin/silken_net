# frozen_string_literal: true

require "eth"

module Web3
  # = ===================================================================
  # 🔗 RPC CONNECTION POOL (Thread-Safe Client Caching + Fallback Cascade)
  # = ===================================================================
  # Кешує Eth::Client інстанси per-thread для запобігання:
  # - Повторному встановленню TCP з'єднань при кожному виклику worker'а
  # - Rate-limiting від RPC провайдерів (Alchemy, Infura)
  # - Зайвому навантаженню на TLS handshake у Sidekiq-потоках
  #
  # Thread-safety: кожен Sidekiq thread отримує власний клієнт через Thread.current.
  # Це безпечно, оскільки Sidekiq worker'и виконуються ізольовано в межах потоку.
  #
  # [RPC FALLBACK CASCADE]: Підтримує масив резервних URL через fallback_env_keys.
  # При Net::ReadTimeout або HTTP 429 автоматично перемикається на наступний RPC.
  # Circuit Breaker вимикає провайдера після 3 послідовних збоїв на 60 секунд.
  #
  # Використання:
  #   # Простий виклик (зворотна сумісність):
  #   client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
  #
  #   # З fallback cascade:
  #   client = Web3::RpcConnectionPool.client_for(
  #     "ALCHEMY_POLYGON_RPC_URL",
  #     fallback_env_keys: ["INFURA_POLYGON_RPC_URL"]
  #   )
  module RpcConnectionPool
    THREAD_KEY_PREFIX = :web3_rpc_client_

    class << self
      # Повертає кешований клієнт для вказаного RPC URL env key.
      # Підтримує fallback cascade через fallback_env_keys.
      #
      # @param rpc_url_env_key [String] назва ENV-змінної з primary RPC URL
      # @param fallback [String, nil] резервний URL, якщо ENV-змінна відсутня (legacy)
      # @param fallback_env_keys [Array<String>] додаткові ENV-ключі для fallback cascade
      # @return [Eth::Client, Web3::ResilientClient]
      def client_for(rpc_url_env_key, fallback: nil, fallback_env_keys: [])
        thread_key = :"#{THREAD_KEY_PREFIX}#{rpc_url_env_key}"
        Thread.current[thread_key] ||= build_client(rpc_url_env_key, fallback, fallback_env_keys)
      end

      # Скидає всі кешовані клієнти в поточному потоці.
      # Використовується при зміні RPC URL або в тестах.
      def reset!
        prefix = THREAD_KEY_PREFIX.to_s
        Thread.current.keys.each do |key|
          Thread.current[key] = nil if key.to_s.start_with?(prefix)
        end
      end

      private

      def build_client(rpc_url_env_key, fallback, fallback_env_keys)
        primary_url = fallback ? ENV.fetch(rpc_url_env_key, fallback) : ENV.fetch(rpc_url_env_key)

        # Збираємо всі доступні URLs для cascade
        all_urls = [ primary_url ]
        Array(fallback_env_keys).each do |key|
          url = ENV[key]
          all_urls << url if url.present?
        end

        all_urls.compact!
        all_urls.reject!(&:empty?)

        # Якщо тільки один URL — повертаємо звичайний Eth::Client (без overhead)
        if all_urls.size <= 1
          Eth::Client.create(primary_url)
        else
          Web3::ResilientClient.new(all_urls)
        end
      end
    end
  end
end
