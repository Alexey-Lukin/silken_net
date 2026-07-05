# frozen_string_literal: true

module SilkenNet
  module LoadTest
    # = ===================================================================
    # 📊 LoadReport — статистика + ЧЕСНА рамка результату (INF.23)
    # = ===================================================================
    # Sorted-array перцентилі (research: досить на десятки тисяч семплів;
    # HdrHistogram = YAGNI, потрібен лише для CO-корекції або млн-soak).
    # Головне — #environment_class: детектор КЛАСУ вузького місця (red-team #1).
    # dev (local PG + localhost Redis + async-cable + memory-cache) робить
    # пайплайн compute/GVL-bound; prod (Cloud SQL + Upstash + solid_cable +
    # solid_cache) — network-IO-bound. Число з першого ЗАВИЩУЄ друге у 10-50×
    # і НЕ переноситься множником → dev-прогін = regression + structural
    # detector, абсолютна стеля народжується лише на staging з prod-адаптерами.
    module LoadReport
      module_function

      def percentiles(samples, ps: [ 50, 95, 99, 99.9 ])
        return {} if samples.empty?

        sorted = samples.sort
        ps.to_h do |p|
          rank = ((p / 100.0) * (sorted.size - 1)).round
          [ "p#{p}", sorted[rank] ]
        end
      end

      # Little's Law: середній in-flight L = λ·W. Валідний ЛИШЕ у steady-state
      # (arrival-режим), НЕ на backlog-drain (non-stationary — red-team #3).
      def littles_law(arrival_rate:, mean_latency_s:)
        (arrival_rate * mean_latency_s).round(2)
      end

      # Coefficient of variation — гейт довіри до dev-числа (research):
      # CoV > 0.05 → прогін ще не стабільний, екстраполювати рано.
      def coefficient_of_variation(samples)
        return nil if samples.size < 2

        mean = samples.sum.to_f / samples.size
        return nil if mean.zero?

        variance = samples.sum { |x| (x - mean)**2 } / (samples.size - 1)
        (Math.sqrt(variance) / mean).round(4)
      end

      # Клас вузького місця + чи dev-число можна вважати capacity.
      def environment_class
        cache = Rails.cache.class.name
        cable = detect_cable_adapter
        redis = classify_redis(ENV["REDIS_URL"].to_s)
        io_prod = cache.include?("SolidCache") && cable.to_s.include?("solid") && redis == "upstash(network)"

        {
          db_rtt_us: measure_db_rtt_us,
          cache_store: cache, cable_adapter: cable, redis: redis,
          bottleneck_class: io_prod ? "io-bound (prod-like)" : "compute-bound (dev proxy)",
          capacity_valid: io_prod
        }
      end

      # Банер, який МУСИТЬ стояти над кожним числом бенчмарка.
      def banner(env = environment_class)
        caveat = env[:capacity_valid] ? "" : " — dev-число = regression+structural detector, НЕ capacity (red-team #1)"
        [
          "⚠️  BOTTLENECK-CLASS: #{env[:bottleneck_class]}#{caveat}",
          "    db_rtt=#{env[:db_rtt_us]}µs  cache=#{env[:cache_store]}  " \
          "cable=#{env[:cable_adapter]}  redis=#{env[:redis]}"
        ].join("\n")
      end

      def measure_db_rtt_us
        ActiveRecord::Base.connection.execute("SELECT 1") # warmup: cold-connect ≠ RTT
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecord::Base.connection.execute("SELECT 1")
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000_000).round
      rescue StandardError
        nil
      end

      def detect_cable_adapter
        ActionCable.server.config.cable&.with_indifferent_access&.fetch("adapter", "unknown") || "unknown"
      rescue StandardError
        "unknown"
      end

      def classify_redis(url)
        return "local" if url.empty? || url.include?("localhost") || url.include?("127.0.0.1")

        url.include?("upstash") ? "upstash(network)" : "remote/other"
      end
    end
  end
end
