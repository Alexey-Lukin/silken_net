# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🔧 SIDEKIQ PRO/ENTERPRISE SHIMS (Development & Test Compatibility)
# = ===================================================================
# Забезпечує сумісність з Sidekiq Pro та Enterprise API в середовищах
# розробки та тестування, де ліцензовані gem'и не встановлені.
#
# В продакшені ці класи надаються gem'ами sidekiq-pro та sidekiq-ent.
# Shim'и просто делегують виконання без обмежень — вся бізнес-логіка
# залишається ідентичною, лише enforcement-механізми відключені.
#
# Sidekiq Pro:  Batch (orchestration), expires_in (stale job TTL)
# Sidekiq Ent:  Limiter (rate limiting), unique_for (deduplication)
#
# 🔴 УВАГА, і це не деталь: шимляться лише те, що є КЛАСОМ — `Batch` і `Limiter`.
# `expires_in` та `unique_for` — це КЛЮЧІ `sidekiq_options`, тож шима для них не
# існує й існувати не може: OSS-Sidekiq кладе їх у job-hash і ніколи не читає
# (у 8.1.6 рядок `expires_in` не зустрічається в `lib/` ЖОДНОГО разу — виміряно
# 2026-08-21). Перелік вище описує API ГЕМА, а не покриття цього файлу, і читався
# як друге — саме тому три з чотирьох воркерів роками пояснювали свій TTL у
# теперішньому часі, ніби він діє. Наслідки й порядок активації — `04_02 §11`
# DOC-R.10 (крок 1 озброює `expires_in`, і на uplink це втрата growth_points).

# --- Sidekiq Pro: Batch API ---
# Оркестрація груп воркерів з колбеками (on_success, on_complete, on_death).
# Використовується TokenomicsEvaluatorWorker для координації циклу емісії.
unless defined?(Sidekiq::Batch)
  module Sidekiq
    class Batch
      attr_accessor :description
      attr_reader :bid

      def initialize
        @bid = SecureRandom.hex(8)
        @callbacks = []
      end

      # Реєстрація колбеків: :success, :complete, :death
      def on(event, klass, options = {})
        @callbacks << { event: event.to_sym, klass: klass, options: options }
      end

      # Блок, що визначає джоби цього батчу.
      # В продакшені Sidekiq Pro відстежує всі enqueued джоби всередині блоку.
      def jobs
        yield
      end

      # Доступ до зареєстрованих колбеків (для тестування)
      def callbacks
        @callbacks
      end

      # Status API для колбеків
      class Status
        attr_reader :bid

        def initialize(bid)
          @bid = bid
        end

        def total = 0
        def failures = 0
        def pending = 0
        def complete? = true
      end
    end
  end
end

# --- Sidekiq Enterprise: Rate Limiter API ---
# Захист зовнішніх API від перевантаження (Web3 RPC: Alchemy, Infura, QuickNode).
# Використовується ApplicationWeb3Worker для глобального обмеження RPC-запитів.
unless defined?(Sidekiq::Limiter)
  module Sidekiq
    module Limiter
      # Виключення, що сигналізує про перевищення ліміту.
      # Sidekiq Enterprise middleware автоматично перепланує джобу.
      class OverLimit < StandardError; end

      # Створює window-based лімітер (N запитів за period).
      # @param name [String] унікальне ім'я лімітера (ключ у Redis)
      # @param limit [Integer] максимальна кількість запитів
      # @param period [Symbol] :second, :minute, :hour
      # @param wait [Integer] секунд очікування перед OverLimit (default: nil)
      def self.window(name, limit, period, wait: nil)
        WindowLimiter.new(name, limit, period)
      end

      # Shim WindowLimiter — просто виконує блок без обмежень.
      class WindowLimiter
        attr_reader :name, :limit, :period

        def initialize(name, limit, period)
          @name = name
          @limit = limit
          @period = period
        end

        def within_limit
          yield
        end
      end
    end
  end
end
