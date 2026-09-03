# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "base64"
require "yaml"

module SilkenNet
  module LoadTest
    # = ===================================================================
    # 🕳️ DrainBench — Sidekiq drain-throughput пайплайну (INF.23)
    # = ===================================================================
    # Міряє СПРАВЖНЮ стелю (load-model: не UDP-intake, а drain-каскад). Два
    # режими з РІЗНИМИ питаннями (red-team #3):
    #
    #   • backlog — насипати K батчів, зміряти time-to-drain → μ (max backlog
    #     throughput). Відповідає INF.23 «drain-rate під backlog». ⚠️ μ ≠
    #     sustainable λ; латентність тут = queue-wait ≈ K/μ, НЕ сервіс.
    #   • arrival — подавати батчі темпом λ, дивитись чи backlog стабільний
    #     (drain встигає) чи росте необмежено (λ > μ). Відповідає SLO-питанню
    #     06_08 §2.4 (completion під arrival), а не μ.
    #
    # ⚠️ Обидва режими РЕАЛЬНО дренажать → потрібен ЖИВИЙ Sidekiq-процес
    # (bin/coap_load проти dev/staging-стека). Done-signal — КОМПОЗИТНИЙ по
    # всьому каскаду (red-team #2): uplink==0 — це лише stage-1 із 12, бо
    # verified-пакет фанаутить у web3_critical (Iotex+Chainlink).
    # DB-pool скрейпиться по ТРЬОХ Postgres-DB (drain-cost TOP-1: primary +
    # Solid Cache + Solid Cable — «Rails.cache»/broadcast НЕ Redis).
    class DrainBench
      # Повний strict-ланцюг — done-signal мусить бачити ВСІ черги, не лише
      # uplink (інакше «drained» бреше, поки money-фанаут ще біжить). Читаємо
      # з дому config/sidekiq.yml (не другий літерал — той тихо застаріє при
      # reorder; bin бутає через config/environment, Sidekiq.default_config порожній).
      QUEUES = YAML.load_file(
        Rails.root.join("config/sidekiq.yml"), permitted_classes: [ Symbol ], aliases: true
      ).fetch(:queues).freeze

      class DrainTimeout < StandardError; end

      class << self
        # Насипати `batches` валідних encrypted-батчів проти provisioned Королеви.
        # Дерева повторюються між батчами (red-team #6: wallet-lock рекурує,
        # Lorenz-continuation теплішає). Повертає число enqueued job'ів.
        def enqueue_backlog(result, batches:, batch_size: 45)
          key  = result.gateway.hardware_key.binary_key
          dids = result.trees.map { |t| t.did.delete_prefix("SNET-").to_i(16) }
          ip   = result.gateway.ip_address
          uid  = result.gateway.uid

          batches.times do
            chosen  = dids.sample([ batch_size, dids.size ].min)
            payload = TelemetryBatchFactory.encrypted_batch(key: key, dids: chosen)
            UnpackTelemetryWorker.perform_async(Base64.strict_encode64(payload), ip, uid)
          end
          batches
        end

        # Композитний done-signal: ВСІ черги порожні + нуль busy + нуль
        # retry/scheduled. Race-safe тільки в парі з debounce у #wait_for_drain
        # (останній uplink-job знятий з черги size==0, але ще не запушив 2N дітей).
        def cascade_drained?
          QUEUES.all? { |q| Sidekiq::Queue.new(q).size.zero? } &&
            Sidekiq::Workers.new.size.zero? &&
            Sidekiq::RetrySet.new.size.zero? &&
            Sidekiq::ScheduledSet.new.size.zero?
        end

        # Poll до drained, стабільно `stable` замірів підряд (debounce проти
        # transient-нуля між stage-переходами). Монотонний час (не wall/NTP).
        def wait_for_drain(timeout: 300, poll: 0.5, stable: 3)
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          consecutive = 0
          loop do
            consecutive = cascade_drained? ? consecutive + 1 : 0
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            return elapsed if consecutive >= stable
            raise DrainTimeout, "не дренажнулось за #{timeout}с" if elapsed > timeout

            sleep poll
          end
        end

        # 3-DB snapshot (drain-cost TOP-1): один пакет б'є primary + _cache
        # (Solid Cache) + _cable (Solid Cable) — усі Postgres. waiting > 0 на
        # будь-якій = saturation-сигнал.
        def pool_snapshot
          ActiveRecord::Base.connection_handler.all_connection_pools.to_h do |pool|
            [ pool.db_config.name,
              { size: pool.size, in_use: pool.connections.count(&:in_use?),
                waiting: pool.num_waiting_in_queue } ]
          end
        end

        # BACKLOG-режим → μ. Насипати все, зміряти повний cascade-drain.
        def run_backlog(result, batches:, batch_size: 45, timeout: 300)
          jobs = enqueue_backlog(result, batches: batches, batch_size: batch_size)
          wall = wait_for_drain(timeout: timeout)
          {
            mode: :backlog, jobs: jobs, wall_s: wall.round(3),
            throughput_jobs_s: (jobs / wall).round(1),
            pools: pool_snapshot,
            caveat: "μ = max-backlog throughput; НЕ sustainable λ. Латентність = queue-wait."
          }
        end

        # ARRIVAL-режим → sustainable λ. Подавати `batches` темпом λ батчів/с,
        # дивитись чи backlog розходиться. Повертає backlog-траєкторію (глибина
        # uplink у часі) — монотонне зростання = λ пробив μ. Latency-перцентилі
        # [target: потребує per-job enqueued_at→processed middleware — 00_07].
        def run_arrival(result, batches:, lambda_per_s:, batch_size: 45, timeout: 300)
          raise ArgumentError, "lambda_per_s має бути > 0" unless lambda_per_s.positive?

          key  = result.gateway.hardware_key.binary_key
          dids = result.trees.map { |t| t.did.delete_prefix("SNET-").to_i(16) }
          interval = 1.0 / lambda_per_s
          depths = []

          batches.times do
            payload = TelemetryBatchFactory.encrypted_batch(key: key, dids: dids.sample([ batch_size, dids.size ].min))
            UnpackTelemetryWorker.perform_async(Base64.strict_encode64(payload), result.gateway.ip_address, result.gateway.uid)
            depths << Sidekiq::Queue.new("uplink").size
            sleep interval
          end
          drain_wall = wait_for_drain(timeout: timeout)
          {
            mode: :arrival, lambda_per_s: lambda_per_s, batches: batches,
            backlog_trajectory: depths, backlog_diverged: diverging?(depths),
            drain_tail_s: drain_wall.round(3), pools: pool_snapshot
          }
        end

        private

        # Груба монотонність: остання третина глибша за першу → backlog росте.
        def diverging?(depths)
          return false if depths.size < 6

          third = depths.size / 3
          depths.last(third).sum.to_f / third > depths.first(third).sum.to_f / third * 1.5
        end
      end
    end
  end
end
