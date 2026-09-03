# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "httpx"
require "json"

module Web3
  # = ===================================================================
  # 🌐 HTTP CLIENT (Shared HTTP Utility for External API Services)
  # = ===================================================================
  # Централізована утиліта для всіх HTTP-запитів до зовнішніх API:
  # IPFS/Filecoin, IoTeX W3bstream, Polygon Hadron, The Graph,
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
  # - [S6.4]: Per-service circuit breaker — тимчасово вимикає сервіс після
  #   MAX_FAILURES послідовних збоїв, запобігаючи cascade failure
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

    # [S6.4]: Circuit breaker thresholds (aligned with Web3::ResilientClient)
    MAX_FAILURES = 3
    CIRCUIT_OPEN_DURATION = 60 # seconds

    THREAD_KEY = :web3_httpx_session

    class RequestError < StandardError; end

    # [S6.4]: Raised when circuit breaker is open for a service.
    # Callers can rescue this separately to implement fallback logic.
    class CircuitOpenError < RequestError; end

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
        check_circuit!(service_name)

        request_headers = { "content-type" => "application/json" }.merge(headers)

        response = session
          .with(
            timeout: { connect_timeout: open_timeout, read_timeout: read_timeout },
            headers: request_headers
          )
          .post(url, body: JSON.generate(body))

        result = handle_response(response, service_name:)
        record_success(service_name)
        result
      rescue RequestError
        record_failure(service_name)
        raise
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
        check_circuit!(service_name)

        response = session
          .with(
            timeout: { connect_timeout: open_timeout, read_timeout: read_timeout },
            headers: headers
          )
          .get(url)

        result = handle_response(response, service_name:)
        record_success(service_name)
        result
      rescue RequestError
        record_failure(service_name)
        raise
      end

      # Скидає кешовану HTTPX-сесію в поточному потоці.
      # Використовується при зміні конфігурації або в тестах.
      def reset!
        old_session = Thread.current[THREAD_KEY]
        old_session&.close
        Thread.current[THREAD_KEY] = nil
      end

      # [S6.4]: Скидає всі circuit breakers. Використовується в тестах.
      def reset_circuit_breakers!
        @mutex.synchronize do
          @failure_counts.clear
          @circuit_opened_at.clear
        end
      end

      # [S6.4]: Повертає стан circuit breaker для вказаного сервісу (для моніторингу / Prometheus).
      #
      # @param service_name [String] ім'я сервісу
      # @return [Hash] з ключами :service, :failures, :circuit_open, :available
      def circuit_status(service_name)
        key = service_name.downcase
        @mutex.synchronize do
          {
            service: service_name,
            failures: @failure_counts[key],
            circuit_open: circuit_open?(key),
            # 🔴 [ARCH.84] ЧИСТИЙ предикат: доти тут стояв `provider_available?`,
            # який при вичерпаному cooldown видаляє `@failure_counts` і
            # `@circuit_opened_at` — тобто метод, чий власний коментар каже «для
            # моніторингу / Prometheus», напів-відкривав справжній circuit
            # breaker. Дзеркало того самого дефекту в `Web3::ResilientClient`;
            # нога трекера називала лише його, а сайтів було два.
            available: provider_reachable?(key)
          }
        end
      end

      private

      # Thread-safe persistent HTTPX session.
      # Кожен Sidekiq thread отримує власну сесію з persistent connections.
      # З'єднання перевикористовуються для всіх origins (Pinata, Solana тощо).
      def session
        Thread.current[THREAD_KEY] ||= HTTPX.plugin(:persistent)
      end

      # [S6.4]: Circuit breaker check — raises CircuitOpenError if service is temporarily disabled.
      def check_circuit!(service_name)
        key = service_name.downcase
        @mutex.synchronize do
          return if provider_available?(key)

          Rails.logger.warn "🔌 [#{service_name}] Circuit breaker OPEN — request blocked (cooldown #{CIRCUIT_OPEN_DURATION}s)"
          raise CircuitOpenError, "#{service_name} circuit breaker is open — service temporarily unavailable"
        end
      end

      # [S6.4]: Records a failure for the service. Opens circuit after MAX_FAILURES.
      def record_failure(service_name)
        key = service_name.downcase
        @mutex.synchronize do
          @failure_counts[key] += 1

          if @failure_counts[key] >= MAX_FAILURES && !@circuit_opened_at.key?(key)
            @circuit_opened_at[key] = Time.current
            Rails.logger.warn "🔌 [#{service_name}] Circuit breaker OPEN after #{MAX_FAILURES} consecutive failures"
          end
        end
      end

      # [S6.4]: Records a success — resets failure count and closes circuit.
      def record_success(service_name)
        key = service_name.downcase
        @mutex.synchronize do
          @failure_counts.delete(key)
          @circuit_opened_at.delete(key)
        end
      end

      # [ARCH.84] ЧИСТИЙ предикат — той самий вердикт без побічних ефектів.
      # Читає `circuit_status` (звіт); мутуючий сусід нижче — лише диспетчер.
      def provider_reachable?(key)
        return true unless circuit_open?(key)

        opened_at = @circuit_opened_at[key]
        return true unless opened_at

        Time.current - opened_at >= CIRCUIT_OPEN_DURATION
      end

      # Вердикт + ПЕРЕХІД open → half-open. Кличе лише `check_circuit!`.
      #
      # ⚠️ Рішення живе у `provider_reachable?` і тут НЕ дублюється — інакше
      # мертва desync-гілка стояла б двома копіями. `key?` сам тримає семантику
      # оригіналу (лічильник і момент відкриття завжди чистяться разом), тож
      # пара з `circuit_open?` дала б лише непокривану завжди-істинну гілку.
      def provider_available?(key)
        return false unless provider_reachable?(key)

        if @circuit_opened_at.key?(key)
          # Cooldown expired — close circuit breaker (half-open → test)
          @failure_counts.delete(key)
          @circuit_opened_at.delete(key)
        end
        true
      end

      def circuit_open?(key)
        @failure_counts[key] >= MAX_FAILURES
      end

      def handle_response(response, service_name:)
        if response.is_a?(HTTPX::ErrorResponse)
          error = response.error
          if error.is_a?(HTTPX::TimeoutError)
            Rails.logger.error "🛑 [#{service_name}] Timeout: #{error.message}"
            raise RequestError, "#{service_name} Timeout: #{error.message}"
          else
            raise RequestError, "#{service_name} connection error (#{error.class}): #{error.message}"
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

    # [S6.4]: Circuit breaker state — shared across all threads (protected by @mutex).
    # @failure_counts tracks consecutive failures per service_name (downcased).
    # @circuit_opened_at records when circuit was opened for cooldown timing.
    @mutex = Mutex.new
    @failure_counts = Hash.new(0)
    @circuit_opened_at = {}

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
