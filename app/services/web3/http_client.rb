# frozen_string_literal: true

require "httpx"
require "json"

module Web3
  # = ===================================================================
  # 🌐 HTTP CLIENT (Shared HTTP Utility for External API Services)
  # = ===================================================================
  # Централізована утиліта для всіх HTTP-запитів до зовнішніх API:
  # IPFS/Filecoin, IoTeX W3bstream, Streamr, Polygon Hadron, The Graph,
  # peaq DID, Solana JSON RPC.
  #
  # Використовує HTTPX замість Net::HTTP для:
  # - Persistent connections (TCP з'єднання перевикористовуються)
  # - HTTP/2 підтримка з мультиплексуванням
  # - Connection pooling per origin (автоматичний пул для кожного сервера)
  # - Thread-safe sessions (кожен Sidekiq thread має власну сесію)
  #
  # Забезпечує:
  # - Уніфіковані таймаути з конфігурацією per-service
  # - Стандартну обробку помилок (таймаути, HTTP-коди, JSON-парсинг)
  # - Єдиний формат логування помилок
  #
  # Використання:
  #   response = Web3::HttpClient.post(url,
  #     body: payload,
  #     headers: { "Authorization" => "Bearer #{api_key}" },
  #     open_timeout: 10,
  #     read_timeout: 30,
  #     service_name: "Filecoin"
  #   )
  #   data = response.parsed_body # parsed JSON
  module HttpClient
    DEFAULT_OPEN_TIMEOUT = 10
    DEFAULT_READ_TIMEOUT = 30

    THREAD_KEY = :web3_httpx_session

    class RequestError < StandardError; end

    class << self
      # Виконує HTTP POST запит з JSON body.
      #
      # @param url [String] повний URL endpoint
      # @param body [Hash] тіло запиту (буде серіалізовано у JSON)
      # @param headers [Hash] додаткові HTTP заголовки
      # @param open_timeout [Integer] таймаут на з'єднання (секунди)
      # @param read_timeout [Integer] таймаут на відповідь (секунди)
      # @param service_name [String] ім'я сервісу для логування помилок
      # @return [Response] обгортка з body та parsed_body
      def post(url, body:, headers: {}, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT, service_name: "HTTP")
        request_headers = { "content-type" => "application/json" }.merge(headers)

        response = session
          .with(
            timeout: { connect_timeout: open_timeout, read_timeout: read_timeout },
            headers: request_headers
          )
          .post(url, body: JSON.generate(body))

        handle_response(response, service_name:)
      end

      # Виконує HTTP GET запит.
      #
      # @param url [String] повний URL endpoint
      # @param headers [Hash] додаткові HTTP заголовки
      # @param open_timeout [Integer] таймаут на з'єднання (секунди)
      # @param read_timeout [Integer] таймаут на відповідь (секунди)
      # @param service_name [String] ім'я сервісу для логування помилок
      # @return [Response] обгортка з body та parsed_body
      def get(url, headers: {}, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT, service_name: "HTTP")
        response = session
          .with(
            timeout: { connect_timeout: open_timeout, read_timeout: read_timeout },
            headers: headers
          )
          .get(url)

        handle_response(response, service_name:)
      end

      # Скидає кешовану HTTPX-сесію в поточному потоці.
      # Використовується при зміні конфігурації або в тестах.
      def reset!
        old_session = Thread.current[THREAD_KEY]
        old_session&.close
        Thread.current[THREAD_KEY] = nil
      end

      private

      # Thread-safe persistent HTTPX session.
      # Кожен Sidekiq thread отримує власну сесію з persistent connections.
      # З'єднання перевикористовуються для всіх origins (Pinata, Streamr, Solana тощо).
      def session
        Thread.current[THREAD_KEY] ||= HTTPX.plugin(:persistent)
      end

      def handle_response(response, service_name:)
        if response.is_a?(HTTPX::ErrorResponse)
          error = response.error
          if error.is_a?(HTTPX::TimeoutError)
            Rails.logger.error "🛑 [#{service_name}] Timeout: #{error.message}"
            raise RequestError, "#{service_name} Timeout: #{error.message}"
          else
            raise RequestError, "#{service_name} connection error: #{error.message}"
          end
        end

        unless (200..299).cover?(response.status)
          raise RequestError, "#{service_name} API returned #{response.status}: #{response.body}"
        end

        Response.new(response.body.to_s)
      rescue RequestError
        raise
      rescue StandardError => e
        raise RequestError, "#{service_name} connection error: #{e.message}"
      end
    end

    # Lightweight wrapper for HTTP response with lazy JSON parsing
    class Response
      attr_reader :body

      def initialize(body)
        @body = body
      end

      def parsed_body
        @parsed_body ||= JSON.parse(@body)
      rescue JSON::ParserError => e
        raise RequestError, "Invalid JSON response: #{e.message}"
      end
    end
  end
end
