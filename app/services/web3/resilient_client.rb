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
  # Каскад: Primary (Alchemy, keyed) → keyless-публічні фолбеки ІНШИХ операторів
  #   (PublicNode · dRPC — реєстр `RpcConnectionPool::NETWORK_FALLBACK_ENV_KEYS`, [ARCH.114]).
  # ⛔ Розділення read/write тут НЕМАЄ: `method_missing` проксює й `transact`, тож при
  #   відкритому breaker'і primary ЗАПИС піде на публічний ендпоінт без SLA. Це прийнято
  #   свідомо (⚖️ founder 2026-09-02: keyless як фолбек, акаунтний вендор — якщо вкусять
  #   rate-limit-и); стеля названа тут, а не в каноні, бо саме цей клас її і несе.
  #
  # Використання:
  #   client = Web3::ResilientClient.new(["https://alchemy.io/...", "https://polygon-bor-rpc.publicnode.com"])
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
      @max_fee_per_gas = nil
      @max_priority_fee_per_gas = nil
    end

    # 🔴 [SEC.17] FEE-ПОЛІТИКА — РЕАЛЬНІ методи, а не `method_missing`, і це несуче.
    # `Eth::Client#transact` EIP-1559 fee-kwargs НЕ читає взагалі (eth 0.5.17
    # `client.rb:322-336` бере лише `tx_value/gas_limit/address/legacy/sender_key/nonce`);
    # fee приходить з АТРИБУТІВ клієнта, тобто cap ставиться присвоєнням.
    # Через `method_missing` присвоєння дійшло б лише до ПЕРШОГО доступного
    # провайдера (цикл `return`ає на першому успіху), а `record_failure` викидає
    # кешованого клієнта — тож cap мовчки зникав би на fallback і після кожного
    # збою. Саме тому [ARCH.62] називав таку форму «декоративним захистом».
    # Тут політика ЗАПАМʼЯТОВУЄТЬСЯ і застосовується до кожного клієнта каскаду,
    # включно зі створеними пізніше (`client_for` нижче).
    #
    # ⚠️ **Периметр цього лікування — РІВНО ДВА fee-атрибути, і межу названо
    # свідомо** (adversarial-ревʼю 2026-08-27): `Eth::Client` має ще два записувані
    # attr'и — `default_account=` і `block_number=`, — і вони лишились на
    # `method_missing`, тобто з тим самим дефектом, який описано абзацом вище.
    # Сьогодні це латентно (у дереві нуль писачів обох; `default_account` читає
    # лише `send_transaction` гема), але **не пиши «політика працює для всіх
    # атрибутів»** — вона працює для тих, кому дали справжній метод. Зʼявиться
    # писач — йому потрібен такий самий, а не ще один прохід через каскад.
    attr_reader :max_fee_per_gas, :max_priority_fee_per_gas

    def max_fee_per_gas=(value)
      @mutex.synchronize do
        @max_fee_per_gas = value
        @clients.each_value { |c| c.max_fee_per_gas = value }
      end
    end

    def max_priority_fee_per_gas=(value)
      @mutex.synchronize do
        @max_priority_fee_per_gas = value
        @clients.each_value { |c| c.max_priority_fee_per_gas = value }
      end
    end

    # Делегуємо виклики Eth::Client через fallback cascade.
    # Пробуємо кожен доступний провайдер по черзі.
    #
    # 🔴 **`**kwargs` ТУТ НЕСУЧИЙ, І ЙОГО ВІДСУТНІСТЬ БУЛА ГРОШОВИМ ДЕФЕКТОМ** (2026-08-29).
    # Форма `def method_missing(name, *, &)` анонімним splatʼом захоплює й keyword-аргументи,
    # але передає їх приймачеві **позиційним ХЕШЕМ** — приймач бачить зайвий позиційний
    # аргумент і `kwargs = {}`. Виміряно прямою пробою:
    #
    #   прямий виклик:  args=["to","amount"]                          opts={legacy:…, sender_key:…}
    #   через splat:    args=["to","amount", {legacy:…, sender_key:…}] opts={}
    #
    # 💰 Ціна конкретна: `Web3::LocalEnvSigner#transact` передає ОРАКУЛЬНИЙ ключ саме
    # kwargʼом (`sender_key: @key`), а `Eth::Client#transact` читає `sender_key`/`legacy`/
    # `nonce`/`gas_limit` виключно з kwargs. Через каскад вони не доходили ЖОДНОГО разу —
    # тобто підпис money-транзакції лишався без явно переданого ключа, а `legacy: false`
    # (EIP-1559) мовчки не діяв. Дефект був ЛАТЕНТНИЙ рівно тому, що каскад вмикався лише
    # там, де ОБИДВА сайти мережі його передавали (Celo); щойно [ARCH.114] зробив каскад
    # властивістю мережі, він накрив би весь Polygon money-path.
    # ⚠️ Клас той самий, що описано двома абзацами вище про fee-атрибути: **`method_missing`
    # передає не все, що виглядає переданим.** Перш ніж класти сюди ще один метод — спитай
    # не «чи він делегується», а «що саме з нього доходить».
    def method_missing(method_name, *args, **kwargs, &block)
      last_error = nil

      available_urls.each do |url|
        client = client_for(url)
        result = client.public_send(method_name, *args, **kwargs, &block)
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
    # 🔴 [ARCH.84] Звіт читає ЧИСТИЙ предикат, і це не стиль.
    #
    # Доти тут стояв `provider_available?`, який при вичерпаному cooldown
    # ОБНУЛЯЄ `@failure_counts`, видаляє `@circuit_opened_at` і переписує
    # Prometheus-gauge — тобто **відкриття панелі здоровʼя напів-відкривало
    # справжні circuit breaker'и**. Проба, що змінює стан, яким звітує, не є
    # пробою: два оператори, що дивляться на панель одночасно, змінювали
    # маршрутизацію RPC самим фактом перегляду.
    def provider_health
      @mutex.synchronize do
        @rpc_urls.map do |url|
          {
            provider: mask_url(url),
            failures: @failure_counts[url],
            circuit_open: circuit_open?(url),
            available: provider_reachable?(url)
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

    # [ARCH.84] ЧИСТИЙ предикат — той самий вердикт, нуль побічних ефектів.
    # Дім відповіді «чи доступний»; мутуючий сусід нижче лише додає ПЕРЕХІД.
    def provider_reachable?(url)
      return true unless circuit_open?(url)

      opened_at = @circuit_opened_at[url]
      # `circuit_open?` ⇒ `@circuit_opened_at` сет (`record_failure` ставить
      # обидва разом) — гілка мертва, лишається як desync-захист.
      return true unless opened_at

      Time.current - opened_at >= CIRCUIT_OPEN_DURATION
    end

    # Вердикт + ПЕРЕХІД open → half-open. Кличе лише диспетчер
    # (`available_urls`), бо саме він має право випробувати провайдера.
    #
    # ⚠️ Рішення НЕ дублюється — воно все у `provider_reachable?`; тут лише
    # умова ПЕРЕХОДУ. Дзеркальні гілки були б двома копіями мертвої
    # desync-гілки, а мертвий код у двох місцях гірший за мертвий в одному.
    # Умова `key?` тримає ту саму семантику, що й оригінал: у desync-стані
    # (breaker відкритий, а моменту відкриття немає) перехід НЕ відбувається.
    def provider_available?(url)
      return false unless provider_reachable?(url)

      if @circuit_opened_at.key?(url)
        @failure_counts[url] = 0
        @circuit_opened_at.delete(url)
        # [S2.2]: Скидаємо gauge при переході з open → half-open після cooldown
        set_circuit_breaker_gauge(mask_url(url), 0.0)
      end
      true
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

    # ⚠️ [SEC.17] Клієнт створюється ТУТ і не лише на старті: `record_failure` викидає
    # кешованого при кожному збої провайдера, тож fee-політику треба накладати саме
    # в момент створення — інакше перший же RPC-збій повертав би gem-дефолти
    # (`Tx::DEFAULT_GAS_PRICE` 42.69 Gwei) під виглядом чинного cap'а.
    def client_for(url)
      @mutex.synchronize do
        @clients[url] ||= Eth::Client.create(url).tap do |client|
          client.max_fee_per_gas = @max_fee_per_gas if @max_fee_per_gas
          client.max_priority_fee_per_gas = @max_priority_fee_per_gas if @max_priority_fee_per_gas
        end
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
