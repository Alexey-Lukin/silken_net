# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"

module Web3
  # = ===================================================================
  # 🛡️ RESILIENT CLIENT (RPC Fallback Cascade with Circuit Breaker)
  # = ===================================================================
  # Обгортка навколо Eth::Client, яка додає:
  # - Автоматичний fallback на резервні RPC-провайдери при збоях
  # - Circuit Breaker: після MAX_FAILURES збоїв провайдер тимчасово виключається
  # - Розпізнавання HTTP 429 (Rate Limit), Net::ReadTimeout, Errno::ECONNREFUSED
  # - Thread-safe операції через Mutex
  #
  # Каскад: Primary (Alchemy) → Secondary (Infura) → Public (polygon-rpc.com)
  # ВАЖЛИВО: Public RPC використовується ТІЛЬКИ для read-операцій.
  #
  # Використання:
  #   client = Web3::ResilientClient.new(["https://alchemy.io/...", "https://infura.io/..."])
  #   client.call("eth_getTransactionReceipt", [tx_hash])
  class ResilientClient
    # Кількість послідовних збоїв перед відкриттям circuit breaker
    MAX_FAILURES = 3

    # Час (секунди) на який провайдер виключається з ротації після MAX_FAILURES
    CIRCUIT_OPEN_DURATION = 60

    # Помилки, які тригерять fallback (не витрачаємо Sidekiq retry)
    RETRIABLE_ERRORS = [
      Net::ReadTimeout,
      Net::OpenTimeout,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      IOError,
      SocketError
    ].freeze

    def initialize(rpc_urls)
      @rpc_urls = Array(rpc_urls).compact.reject(&:empty?)
      raise ArgumentError, "At least one RPC URL is required" if @rpc_urls.empty?

      @mutex = Mutex.new
      @failure_counts = Hash.new(0)
      @circuit_opened_at = {}
      @clients = {}
    end

    # Делегуємо виклики Eth::Client через fallback cascade.
    # Пробуємо кожен доступний провайдер по черзі.
    def method_missing(method_name, *, &)
      last_error = nil

      available_urls.each do |url|
        client = client_for(url)
        result = client.public_send(method_name, *, &)
        record_success(url)
        return result
      rescue *RETRIABLE_ERRORS => e
        record_failure(url, e)
        last_error = e
      rescue StandardError => e
        # HTTP 429 може бути обгорнутий у різні exception-класи залежно від gem
        if rate_limited?(e)
          record_failure(url, e)
          last_error = e
        else
          raise
        end
      end

      # available_urls ніколи не порожній → якщо цикл не повернув, кожен провайдер
      # зафейлив і last_error встановлено.
      raise last_error
    end

    def respond_to_missing?(method_name, include_private = false)
      Eth::Client.instance_methods.include?(method_name) || super
    end

    # Поточний стан circuit breakers (для моніторингу / Prometheus)
    def provider_health
      @mutex.synchronize do
        @rpc_urls.map do |url|
          masked = mask_url(url)
          {
            provider: masked,
            failures: @failure_counts[url],
            circuit_open: circuit_open?(url),
            available: provider_available?(url)
          }
        end
      end
    end

    private

    def available_urls
      @mutex.synchronize do
        available = @rpc_urls.select { |url| provider_available?(url) }
        # Якщо всі circuit breakers відкриті — скидаємо і пробуємо всіх
        available = @rpc_urls if available.empty?
        available
      end
    end

    def provider_available?(url)
      return true unless circuit_open?(url)

      # Перевіряємо чи минув час cooldown
      opened_at = @circuit_opened_at[url]
      return true unless opened_at

      if Time.current - opened_at >= CIRCUIT_OPEN_DURATION
        # Cooldown минув — закриваємо circuit breaker (half-open → test)
        @failure_counts[url] = 0
        @circuit_opened_at.delete(url)
        # [S2.2]: Скидаємо gauge при переході з open → half-open після cooldown
        set_circuit_breaker_gauge(mask_url(url), 0.0)
        true
      else
        false
      end
    end

    def circuit_open?(url)
      @failure_counts[url] >= MAX_FAILURES
    end

    def record_failure(url, error)
      @mutex.synchronize do
        @failure_counts[url] += 1
        masked = mask_url(url)

        # [S2.2]: Інкрементуємо Prometheus RPC_ERRORS_TOTAL для Grafana alerting
        increment_rpc_error_metric(masked, error)

        if @failure_counts[url] >= MAX_FAILURES && !@circuit_opened_at.key?(url)
          @circuit_opened_at[url] = Time.current
          Rails.logger.warn "🔌 [RPC] Circuit breaker OPEN для #{masked}: #{error.class} — #{error.message}"
          # [S2.2]: Оновлюємо gauge circuit breaker стану
          set_circuit_breaker_gauge(masked, 1.0)
        else
          Rails.logger.warn "🔌 [RPC] Збій #{masked} (#{@failure_counts[url]}/#{MAX_FAILURES}): #{error.class}"
        end

        # Інвалідуємо кешований клієнт для цього URL
        @clients.delete(url)
      end
    end

    def record_success(url)
      @mutex.synchronize do
        was_open = circuit_open?(url)
        @failure_counts[url] = 0
        @circuit_opened_at.delete(url)

        # [S2.2]: Скидаємо gauge при відновленні провайдера
        # Цей шлях активується коли ВСІ circuit breakers відкриті і
        # available_urls fallback (рядок 103) повертає всі URL без cooldown-скидання.
        if was_open
          masked = mask_url(url)
          set_circuit_breaker_gauge(masked, 0.0)
        end
      end
    end

    def client_for(url)
      @mutex.synchronize do
        @clients[url] ||= Eth::Client.create(url)
      end
    end

    def rate_limited?(error)
      message = error.message.to_s.downcase
      message.include?("429") || message.include?("too many requests") || message.include?("rate limit")
    end

    def mask_url(url)
      uri = URI.parse(url)
      "#{uri.host}:#{uri.port}"
    rescue URI::InvalidURIError
      url.first(30)
    end

    # [S2.2]: Prometheus RPC error counter — labeled by provider and error type
    def increment_rpc_error_metric(provider, error)
      error_type = classify_error(error)
      SilkenNet::Metrics::RPC_ERRORS_TOTAL.increment(
        labels: { network: provider, error_type: error_type }
      )
    rescue StandardError
      # Metrics must never break the hot path
    end

    # [S2.2]: Prometheus circuit breaker gauge update
    def set_circuit_breaker_gauge(provider, value)
      SilkenNet::Metrics::RPC_CIRCUIT_BREAKER_OPEN.set(
        value, labels: { provider: provider }
      )
    rescue StandardError
      # Metrics must never break the hot path
    end

    def classify_error(error)
      case error
      when Net::ReadTimeout, Net::OpenTimeout then "timeout"
      when Errno::ECONNREFUSED, Errno::ECONNRESET then "connection_refused"
      when Errno::EHOSTUNREACH then "host_unreachable"
      when SocketError then "dns_error"
      when IOError then "io_error"
      else
        rate_limited?(error) ? "rate_limited" : "unknown"
      end
    end
  end
end
