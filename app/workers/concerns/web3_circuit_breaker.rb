# frozen_string_literal: true

# = ===================================================================
# ⚡ WEB3 CIRCUIT BREAKER (Chaos-Resilient Web3 Protection)
# = ===================================================================
# Патерн Circuit Breaker для Web3-черг. Захищає систему від каскадних
# збоїв при недоступності блокчейн-нод або зовнішніх сервісів.
#
# Три стани:
#   :closed   — нормальна робота, запити проходять
#   :open     — сервіс недоступний, запити блокуються (fail-fast)
#   :half_open — пробний запит для перевірки відновлення
#
# Використання:
#   class MyWeb3Worker
#     include ApplicationWeb3Worker
#     include Web3CircuitBreaker
#
#     def perform(...)
#       with_circuit_breaker("iotex_w3bstream") do
#         with_web3_error_handling("IoTeX", "...") { ... }
#       end
#     end
#   end
#
# Кешування стану через Rails.cache (Solid Cache) — працює між
# процесами Sidekiq та навіть між серверами (при shared cache).
module Web3CircuitBreaker
  extend ActiveSupport::Concern

  # Кількість послідовних помилок для відкриття circuit breaker
  FAILURE_THRESHOLD = 5

  # Час, протягом якого circuit breaker залишається відкритим (секунди)
  OPEN_TIMEOUT = 300 # 5 хвилин

  # Помилки, що рахуються як збої circuit breaker
  CIRCUIT_BREAKER_ERRORS = [
    HTTPX::TimeoutError,
    HTTPX::ConnectionError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    IOError,
    Web3::HttpClient::RequestError
  ].freeze

  class CircuitOpenError < StandardError; end

  # Обгортка з Circuit Breaker для Web3-викликів.
  #
  # @param service_name [String] унікальний ідентифікатор сервісу (e.g., "iotex_w3bstream", "chainlink_functions")
  # @yield блок з RPC-операціями
  # @raise [CircuitOpenError] якщо circuit відкритий
  def with_circuit_breaker(service_name)
    state = circuit_state(service_name)

    case state
    when :open
      SilkenNet::Metrics::CIRCUIT_BREAKER_REJECTIONS.increment(labels: { service: service_name }) if defined?(SilkenNet::Metrics::CIRCUIT_BREAKER_REJECTIONS)
      Rails.logger.warn "⚡ [CircuitBreaker] #{service_name} — OPEN. Запит відхилено (fail-fast). " \
                        "Відновлення через #{remaining_open_seconds(service_name)}с."
      raise CircuitOpenError, "Circuit breaker OPEN for #{service_name}. Service unavailable."
    when :half_open
      Rails.logger.info "⚡ [CircuitBreaker] #{service_name} — HALF_OPEN. Пробний запит..."
    end

    result = yield

    # Успішний запит — скидаємо лічильник помилок
    reset_circuit!(service_name)
    result
  rescue CircuitOpenError
    raise # Re-raise circuit open errors без зміни стану
  rescue *CIRCUIT_BREAKER_ERRORS => e
    record_failure!(service_name)
    raise e
  rescue StandardError => e
    # Перевіряємо, чи оригінальна помилка (cause) є transient.
    # Сервіси часто обгортають RPC-помилки у свої custom errors
    # (DispatchError, VerificationError), але root cause — transient.
    if transient_cause?(e)
      record_failure!(service_name)
    end
    raise e
  end

  private

  def circuit_state(service_name)
    failures = circuit_failure_count(service_name)
    opened_at = circuit_opened_at(service_name)

    if failures >= FAILURE_THRESHOLD
      if opened_at && (Time.current.to_f - opened_at) > OPEN_TIMEOUT
        :half_open
      else
        :open
      end
    else
      :closed
    end
  end

  def record_failure!(service_name)
    key = circuit_failure_key(service_name)
    count = Rails.cache.increment(key, 1, expires_in: OPEN_TIMEOUT * 2)

    # Якщо щойно досягли порогу — фіксуємо час відкриття
    if count && count >= FAILURE_THRESHOLD
      Rails.cache.write(circuit_opened_at_key(service_name), Time.current.to_f, expires_in: OPEN_TIMEOUT * 2)
      Rails.logger.error "🚨 [CircuitBreaker] #{service_name} — OPENED після #{count} послідовних помилок. " \
                         "Всі запити будуть відхилені на #{OPEN_TIMEOUT}с."
    end
  end

  def reset_circuit!(service_name)
    Rails.cache.delete(circuit_failure_key(service_name))
    Rails.cache.delete(circuit_opened_at_key(service_name))
  end

  def circuit_failure_count(service_name)
    Rails.cache.read(circuit_failure_key(service_name)).to_i
  end

  def circuit_opened_at(service_name)
    Rails.cache.read(circuit_opened_at_key(service_name))&.to_f
  end

  def remaining_open_seconds(service_name)
    opened_at = circuit_opened_at(service_name)
    return 0 unless opened_at

    remaining = OPEN_TIMEOUT - (Time.current.to_f - opened_at)
    [ remaining.ceil, 0 ].max
  end

  def circuit_failure_key(service_name)
    "circuit_breaker:#{service_name}:failures"
  end

  def circuit_opened_at_key(service_name)
    "circuit_breaker:#{service_name}:opened_at"
  end

  # Перевіряє, чи root cause помилки є transient (мережева/RPC).
  # Використовується для wrapped errors (DispatchError, VerificationError),
  # де оригінальна помилка збережена в Exception#cause.
  def transient_cause?(error)
    cause = error.cause
    return false unless cause

    CIRCUIT_BREAKER_ERRORS.any? { |klass| cause.is_a?(klass) } || transient_cause?(cause)
  end
end
