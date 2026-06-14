# frozen_string_literal: true

# = ===================================================================
# 📊 PROMETHEUS METRICS (Observability for Grafana/Prometheus)
# = ===================================================================
# Lightweight metrics exporter using the official prometheus-client gem.
# Exposes custom business metrics for the Gaia 2.0 platform:
#
# - Sidekiq web3 queue size and latency
# - Web3 RPC error rates (by network/type)
# - Financial: SCC minted, locked funds, slashed tokens
# - IoT: CoAP telemetry ingest rate and fraud detection
#
# The /metrics endpoint is secured via PrometheusCollector middleware
# (IP allowlist + HTTP Basic Auth). See app/middleware/prometheus_collector.rb.

require "prometheus/client"

module SilkenNet
  module Metrics
    REGISTRY = Prometheus::Client::Registry.new

    # -----------------------------------------------------------------------
    # 💎 FINANCIAL METRICS (Web3 / Tokenomics)
    # -----------------------------------------------------------------------

    # Total SCC tokens minted (monotonic counter)
    SCC_MINTED_TOTAL = REGISTRY.counter(
      :silkennet_scc_minted_total,
      docstring: "Total SCC (SilkenCarbonCoin) tokens minted",
      labels: [ :token_type ]
    )

    # Total tokens slashed (monotonic counter)
    SCC_SLASHED_TOTAL = REGISTRY.counter(
      :silkennet_scc_slashed_total,
      docstring: "Total tokens slashed (burned due to cluster stress)"
    )

    # Web3 RPC errors (labeled by network and error type)
    RPC_ERRORS_TOTAL = REGISTRY.counter(
      :silkennet_rpc_errors_total,
      docstring: "Total Web3 RPC errors",
      labels: [ :network, :error_type ]
    )

    # -----------------------------------------------------------------------
    # 📡 IoT / TELEMETRY METRICS
    # -----------------------------------------------------------------------

    # Total telemetry chunks processed (monotonic counter)
    TELEMETRY_PROCESSED_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_processed_total,
      docstring: "Total telemetry chunks processed by TelemetryUnpackerService"
    )

    # Telemetry fraud/anomaly detections (monotonic counter)
    TELEMETRY_FRAUD_DETECTED_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_fraud_detected_total,
      docstring: "Total telemetry packets rejected (sensor noise, unknown DID, tamper)"
    )

    # [SEC.10] Panic packets rejected as replay (Frame Counter nonce collision).
    # Сторожовий пес панічного каналу — кожен сплеск тут означає або
    # legitimate retransmission (LoRa mesh duplicate) або replay-attack.
    # Grafana alert при різкому стрибку → можливий attacker injection.
    PANIC_REPLAY_REJECTED_TOTAL = REGISTRY.counter(
      :silkennet_panic_replay_rejected_total,
      docstring: "Panic packets rejected as replay via SEC.10 Frame Counter SETNX nonce"
    )

    # [FW.2] AES-128-CCM packet decrypted and MIC verified successfully.
    # Should track ~1:1 with TELEMETRY_PROCESSED_TOTAL on the CCM code path
    # once `TELEMETRY_CCM_ENABLED=true` ships fleet-wide.
    TELEMETRY_CCM_DECRYPT_OK_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_ccm_decrypt_ok_total,
      docstring: "FW.2 CCM packets successfully decrypted with valid MIC"
    )

    # [FW.2] CCM MIC verification failed — wrong key, tampered ciphertext,
    # mutilated AAD, or wrong DID/FrameCounter pairing. Any nonzero rate
    # in production is a security signal worth paging on.
    TELEMETRY_CCM_MIC_FAIL_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_ccm_mic_fail_total,
      docstring: "FW.2 CCM packets rejected due to MIC verification failure"
    )

    # [FW.2] Per-DID Frame Counter not strictly monotonic — either replay
    # of an already-seen FC or out-of-order delivery beyond what mesh
    # buffering should produce. Grafana alert: rising rate > 0.1% of all
    # CCM packets/min → attacker injection or device clock reset event.
    TELEMETRY_CCM_FC_REPLAY_REJECTED_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_ccm_fc_replay_rejected_total,
      docstring: "FW.2 CCM packets rejected because per-DID Frame Counter was not strictly increasing"
    )

    # [FW.18b] Telemetry packets whose TTL-byte high bits carry a nonzero
    # rejected-OTA-thresholds counter (firmware/common/ttl_byte.h).
    # БЕЗ per-DID мітки свідомо: cardinality budget (06_03 §2.9) тримає
    # реєстр bounded — per-tree атрибуція йде warn-логом (патерн FW.22
    # acoustic overflow). rate() > 0 = на якомусь дереві корумпований RTC
    # або зловмисний OTA-payload; конкретний DID — у логах поруч.
    TINYML_THRESHOLD_INVALID_REPORTS_TOTAL = REGISTRY.counter(
      :silkennet_tinyml_threshold_invalid_reports_total,
      docstring: "FW.18b telemetry packets reporting a nonzero rejected-OTA-thresholds counter (per-DID attribution in logs)"
    )

    # [FW.42] CCM diag-байт (wire-rev2 byte 18, fauna_skip bit): Солдат
    # пропустив fauna-сесію через низький Vcap (брауноут-захист,
    # 03_03 §10.4). Без per-DID мітки — той самий cardinality-патерн, що
    # TINYML_THRESHOLD_INVALID: дерево атрибутується warn-логом. Стійкий
    # rate() > 0 = енергодефіцит кластера (зима / деградація EDLC).
    FAUNA_SKIP_REPORTS_TOTAL = REGISTRY.counter(
      :silkennet_fauna_skip_reports_total,
      docstring: "FW.42 telemetry packets reporting a fauna session skipped on low Vcap (per-DID attribution in logs)"
    )

    # [FW.2] CCM diag-байт (fc_degraded bit): інваріант I-HW (Flash
    # high-water > усіх переданих FC) тимчасово втрачено — Flash відмовляв
    # багато КЕНОЗИСІВ поспіль. Будь-який ненульовий rate() — деградація
    # nonce-гарантії конкретного вузла (DID у warn-лозі поруч).
    FW2_FC_DEGRADED_REPORTS_TOTAL = REGISTRY.counter(
      :silkennet_fw2_fc_degraded_reports_total,
      docstring: "FW.2 telemetry packets reporting a lost FC high-water invariant (Flash refusing writes; per-DID attribution in logs)"
    )

    # -----------------------------------------------------------------------
    # ⚙️ SIDEKIQ QUEUE METRICS (Gauges — sampled at scrape time)
    # -----------------------------------------------------------------------
    # [PLAN 1.3]: Renamed from WEB3_QUEUE_* to SIDEKIQ_QUEUE_* to reflect
    # monitoring ALL 9 queues (uplink, alerts, critical, downlink, default,
    # web3_critical, web3, web3_low, low), not just web3.

    # Sidekiq queue size (gauge — set on each scrape via collector callback)
    SIDEKIQ_QUEUE_SIZE = REGISTRY.gauge(
      :silkennet_sidekiq_queue_size,
      docstring: "Current size of a Sidekiq queue",
      labels: [ :queue ]
    )

    # Sidekiq queue latency in seconds (gauge — oldest job age)
    SIDEKIQ_QUEUE_LATENCY = REGISTRY.gauge(
      :silkennet_sidekiq_queue_latency_seconds,
      docstring: "Latency (age of oldest job) in a Sidekiq queue",
      labels: [ :queue ]
    )

    # Legacy aliases for backward compatibility with existing Grafana dashboards.
    WEB3_QUEUE_SIZE = SIDEKIQ_QUEUE_SIZE
    WEB3_QUEUE_LATENCY = SIDEKIQ_QUEUE_LATENCY

    # -----------------------------------------------------------------------
    # 🔗 DATABASE CONNECTION POOL METRICS (Gauges — Wiki 04_01 Blocker Fix)
    # -----------------------------------------------------------------------
    # Моніторинг Connection Pool для виявлення насичення під час масової
    # телеметрії. Критично при Sidekiq concurrency=15 та pessimistic locks.

    # Total pool size (max connections per database)
    DB_POOL_SIZE = REGISTRY.gauge(
      :silkennet_db_pool_size,
      docstring: "Maximum number of connections in the database pool",
      labels: [ :database ]
    )

    # Currently active (checked out) connections
    DB_POOL_CONNECTIONS = REGISTRY.gauge(
      :silkennet_db_pool_connections,
      docstring: "Number of active (checked out) database connections",
      labels: [ :database ]
    )

    # Idle connections available in the pool
    DB_POOL_IDLE = REGISTRY.gauge(
      :silkennet_db_pool_idle,
      docstring: "Number of idle database connections in the pool",
      labels: [ :database ]
    )

    # Threads waiting for a connection checkout
    DB_POOL_WAITING = REGISTRY.gauge(
      :silkennet_db_pool_waiting,
      docstring: "Number of threads waiting for a database connection",
      labels: [ :database ]
    )

    # -----------------------------------------------------------------------
    # 💰 TREASURY / ORACLE WALLET METRICS (Multi-chain balance monitoring)
    # -----------------------------------------------------------------------
    # Відстежує баланси Oracle wallets на всіх мережах.
    # Критично для масштабування: при мільйонах дерев витрати газу зростають пропорційно.

    # Oracle wallet balance in native currency (MATIC, SOL, CELO, ETH)
    ORACLE_BALANCE = REGISTRY.gauge(
      :silkennet_oracle_balance,
      docstring: "Oracle wallet balance in native currency (wei/lamports)",
      labels: [ :network ]
    )

    # Oracle wallet balance as ratio to minimum threshold (< 1.0 = critical)
    ORACLE_BALANCE_RATIO = REGISTRY.gauge(
      :silkennet_oracle_balance_ratio,
      docstring: "Oracle balance as ratio to minimum threshold (below 1.0 = critical)",
      labels: [ :network ]
    )

    # Treasury monitor errors (network unreachable, RPC timeout)
    TREASURY_CHECK_ERRORS_TOTAL = REGISTRY.counter(
      :silkennet_treasury_check_errors_total,
      docstring: "Total treasury monitoring RPC errors",
      labels: [ :network, :error_type ]
    )

    # -----------------------------------------------------------------------
    # 🔥 WORKER-SPECIFIC METRICS (Gap Analysis — S2.4)
    # -----------------------------------------------------------------------

    # Slashing events by reason (fraud, cluster_stress, contract_breach)
    SLASHING_EVENTS_TOTAL = REGISTRY.counter(
      :silkennet_slashing_events_total,
      docstring: "Total slashing (burn) events by reason",
      labels: [ :reason ]
    )

    # OTA firmware chunks sent to field devices
    OTA_CHUNKS_SENT_TOTAL = REGISTRY.counter(
      :silkennet_ota_chunks_sent_total,
      docstring: "Total OTA firmware chunks transmitted to field devices",
      labels: [ :firmware_version ]
    )

    # Early Warning System alerts dispatched
    EWS_ALERTS_TOTAL = REGISTRY.counter(
      :silkennet_ews_alerts_total,
      docstring: "Total EWS alerts dispatched (fire, drought, pest, storm)",
      labels: [ :alert_type ]
    )

    # Chainlink oracle dispatch latency (histogram for percentile analysis)
    ORACLE_DISPATCH_DURATION = REGISTRY.histogram(
      :silkennet_oracle_dispatch_duration_seconds,
      docstring: "Chainlink oracle dispatch latency in seconds",
      buckets: [ 0.5, 1, 2.5, 5, 10, 30, 60 ]
    )

    # CoAP UDP packets received by the daemon
    COAP_PACKETS_RECEIVED_TOTAL = REGISTRY.counter(
      :silkennet_coap_packets_received_total,
      docstring: "Total CoAP UDP packets received by the telemetry daemon",
      labels: [ :status ]  # success, decrypt_error, unknown_device, malformed
    )

    # Lorenz attractor computation duration (BigDecimal, 250 iterations)
    LORENZ_COMPUTATION_DURATION = REGISTRY.histogram(
      :silkennet_lorenz_computation_duration_seconds,
      docstring: "Lorenz attractor server-side computation time (Float IEEE-754, 250 iterations)",
      buckets: [ 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5 ]
    )

    # [S6.6] Missed Ethereum L1 anchor weeks detected
    ANCHOR_MISSED_WEEKS_TOTAL = REGISTRY.counter(
      :silkennet_anchor_missed_weeks_total,
      docstring: "Total missed Ethereum L1 anchor weeks detected (gap > 8 days)"
    )

    # [E.50]: Streamr broadcast failures counter — раніше помилки мовчки логувались без метрик.
    # Streamr — потік присутності (не фінансовий консенсус), але масові збої потребують alerting.
    STREAMR_BROADCAST_FAILURES_TOTAL = REGISTRY.counter(
      :silkennet_streamr_broadcast_failures_total,
      docstring: "Total Streamr broadcast failures (P2P real-time telemetry delivery)"
    )

    # [S6.13]: W3bstream Ed25519 → SHA256 hardware-signature fallback counter.
    # `Iotex::W3bstreamVerificationService#hardware_signature` падає з Ed25519
    # (provisioned hardware key) на SHA256 fallback коли HardwareKey відсутній.
    # SHA256 НЕ підтверджує апаратне походження. У production / WEB3_STRICT_MODE=true
    # сервіс fail-closed: інкрементує counter та одразу raise VerificationError
    # (counter все одно інкрементується для observability). Поза production —
    # warn-and-continue (legacy/dev). Grafana alert: > 0 у production = bug
    # (бо raise вже спрацював) АБО legacy fallback використовується у не-prod.
    W3BSTREAM_SIGNATURE_FALLBACK_TOTAL = REGISTRY.counter(
      :silkennet_w3bstream_signature_fallback_total,
      docstring: "Total W3bstream verifications using SHA256 fallback instead of Ed25519 hardware signature",
      labels: [ :reason ]
    )

    # [S6.19]: M2M nonce Redis → DB fallback counter.
    # `Api::V1::M2mAuthController#create` падає з Redis SET NX на DB-backed
    # nonce cache коли Redis недоступний (Upstash outage / network blip).
    # Fallback path має малий TOCTOU window (acceptable у degraded mode).
    # Counter дозволяє виміряти actual outage frequency та alert якщо
    # > 0.1% requests за 1h → escalate до multi-zone Redis.
    M2M_NONCE_FALLBACK_TOTAL = REGISTRY.counter(
      :silkennet_m2m_nonce_fallback_total,
      docstring: "Total M2M nonce checks falling back from Redis to DB-backed cache (Redis outage indicator)"
    )

    # [L1 QATT]: Queen-attestation batch nonce Redis → DB fallback counter.
    # `UnpackTelemetryWorker#qatt_nonce_unique?` падає з Redis SET NX на
    # Solid-Cache nonce коли Redis недоступний — той самий S6.1/S6.19 патерн,
    # що й M2M, але окремий counter: змішування шляхів зробило б M2M-алерт
    # сліпим до батч-стріму (різні частоти: auth ~1/30д vs батчі щогодини).
    QATT_NONCE_FALLBACK_TOTAL = REGISTRY.counter(
      :silkennet_qatt_nonce_fallback_total,
      docstring: "Total Queen-attestation batch nonce checks falling back from Redis to DB-backed cache (Redis outage indicator)"
    )

    # [FW.22 / S2.3]: Acoustic events overflow counter.
    # Firmware saturates acoustic_events at uint8 max (255).
    # Value 255 indicates real count may be higher — sensor data loss.
    # Enables Grafana alerting on acoustic overflow events.
    TELEMETRY_ACOUSTIC_OVERFLOW_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_acoustic_overflow_total,
      docstring: "Total telemetry packets with acoustic_events=255 (uint8 saturation)"
    )

    # [S2.2]: Web3 RPC circuit breaker state gauge.
    # Tracks which RPC providers are currently in circuit-open (disabled) state.
    # 1.0 = circuit open (provider disabled), 0.0 = circuit closed (provider healthy).
    RPC_CIRCUIT_BREAKER_OPEN = REGISTRY.gauge(
      :silkennet_rpc_circuit_breaker_open,
      docstring: "Whether RPC provider circuit breaker is open (1=open/disabled, 0=closed/healthy)",
      labels: [ :provider ]
    )

    # [S2.2 fix 2026-05-29]: Web3 circuit-breaker fast-fail rejections.
    # `Web3CircuitBreaker` already increments this (guarded `if defined?`), but the
    # metric was never registered → the increment was a silent no-op (rejections
    # invisible). Defining it activates that existing instrumentation.
    CIRCUIT_BREAKER_REJECTIONS = REGISTRY.counter(
      :silkennet_circuit_breaker_rejections_total,
      docstring: "Web3 requests fast-failed because a provider circuit breaker was open",
      labels: [ :service ]
    )

    # [S6.16]: TelemetryLog lookup without partition pruning (degraded path).
    # Incremented when a caller looks up a TelemetryLog without supplying
    # `created_at_iso`. Without it, PostgreSQL must scan ALL monthly partitions
    # (Global Partition Scan) — O(P × log N) instead of O(log N). At billions
    # of rows this becomes a multi-second query that blocks the request thread.
    # Acceptable in cold paths (admin tools, manual rollback); ALERT if seen
    # in hot path (oracle callbacks, web3 workers) — indicates upstream worker
    # forgot to pass `created_at_iso`. Grafana rule:
    #     rate(silkennet_telemetry_log_unpruned_lookups_total{caller=~"oracle.*|.*Worker"}[5m]) > 0
    TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_log_unpruned_lookups_total,
      docstring: "Total TelemetryLog lookups without partition pruning (degraded path; missing or invalid ISO8601 created_at_iso)",
      labels: [ :caller ]
    )

    # [06_03 §2.8 / 00_07 S2.5]: PartitionMaintenanceWorker run failures.
    # Each failure = a monthly partition may be missing → the first INSERT against
    # the affected RANGE table on day-1 of the new month crashes with
    # `no partition of relation`. Alert (silkennet-alerts.yaml, P0): increase>0 → page.
    PARTITION_MAINTENANCE_FAILURES_TOTAL = REGISTRY.counter(
      :silkennet_partition_maintenance_failures_total,
      docstring: "PartitionMaintenanceWorker run failures (missing partition → day-1 INSERT crash risk)"
    )

    # [ENTROPY MONITOR]: Shannon entropy of Z-value distribution per cluster.
    # Healthy forest: ≈ 0.75-0.95 (diverse Z-values). Pre-stress: < 0.65.
    # Updated by ClusterEntropyAnalyzerWorker (queue: alerts, hourly).
    CLUSTER_ENTROPY_SCORE = REGISTRY.gauge(
      :silkennet_cluster_entropy_score,
      docstring: "Normalized Shannon entropy of Z-value distribution per cluster (0.0-1.0)",
      labels: [ :cluster_id ]
    )

    # -----------------------------------------------------------------------
    # [06_03 §2.9 Process / runtime health] Ruby VM, GC, memory + Puma pool.
    # Refreshed on each scrape (sample_process_runtime!) — gives prod visibility
    # into memory leaks, GC pressure, and thread/worker saturation that business
    # metrics cannot. Pure Ruby stdlib (GC.stat / Thread.list / /proc / Puma.stats),
    # no extra gems (consistent with §"Чому prometheus-client").
    # -----------------------------------------------------------------------
    PROCESS_RESIDENT_MEMORY_BYTES = REGISTRY.gauge(
      :silkennet_process_resident_memory_bytes,
      docstring: "Resident set size (RSS) of the scraped process in bytes (Linux /proc; 0 elsewhere)"
    )

    RUBY_GC_COUNT = REGISTRY.gauge(
      :silkennet_ruby_gc_count,
      docstring: "Total Ruby GC runs since process start (GC.stat[:count])"
    )

    RUBY_GC_MAJOR_COUNT = REGISTRY.gauge(
      :silkennet_ruby_gc_major_count,
      docstring: "Major Ruby GC runs since process start (GC.stat[:major_gc_count])"
    )

    RUBY_GC_HEAP_LIVE_SLOTS = REGISTRY.gauge(
      :silkennet_ruby_gc_heap_live_slots,
      docstring: "Live objects on the Ruby heap (GC.stat[:heap_live_slots]); sustained growth = leak"
    )

    RUBY_THREADS = REGISTRY.gauge(
      :silkennet_ruby_threads,
      docstring: "Live Ruby threads in the process (Thread.list.size); sustained growth = thread leak"
    )

    PUMA_RUNNING_THREADS = REGISTRY.gauge(
      :silkennet_puma_running_threads,
      docstring: "Puma worker threads currently spawned (busy + idle)"
    )

    PUMA_MAX_THREADS = REGISTRY.gauge(
      :silkennet_puma_max_threads,
      docstring: "Puma configured max threads (pool ceiling)"
    )

    PUMA_POOL_CAPACITY = REGISTRY.gauge(
      :silkennet_puma_pool_capacity,
      docstring: "Puma free thread-pool capacity (0 = saturated → requests queue in backlog)"
    )

    PUMA_BACKLOG = REGISTRY.gauge(
      :silkennet_puma_backlog,
      docstring: "Puma requests waiting for a free thread (backlog; sustained >0 = under-provisioned)"
    )

    # Snapshot connection pool stats for Prometheus scraping.
    # Called from PrometheusCollector middleware or a periodic job.
    def self.sample_connection_pool!
      ActiveRecord::Base.connection_handler.all_connection_pools.each do |pool|
        db_name = pool.db_config.name.to_s

        conns = pool.connections
        in_use = conns.count(&:in_use?)

        DB_POOL_SIZE.set(pool.size, labels: { database: db_name })
        DB_POOL_CONNECTIONS.set(in_use, labels: { database: db_name })
        DB_POOL_IDLE.set(conns.size - in_use, labels: { database: db_name })
        DB_POOL_WAITING.set(pool.num_waiting_in_queue, labels: { database: db_name })
      end
    rescue StandardError => e
      Rails.logger.warn "⚠️ [Prometheus] Connection pool sampling failed: #{e.message}"
    end

    # Snapshot Ruby VM / GC / memory + Puma pool stats for Prometheus scraping.
    # Called from PrometheusCollector on each scrape (cheap: GC.stat is O(1)).
    def self.sample_process_runtime!
      gc = GC.stat
      RUBY_GC_COUNT.set(gc[:count].to_i)
      RUBY_GC_MAJOR_COUNT.set(gc[:major_gc_count].to_i)
      RUBY_GC_HEAP_LIVE_SLOTS.set(gc[:heap_live_slots].to_i)
      RUBY_THREADS.set(Thread.list.size)
      PROCESS_RESIDENT_MEMORY_BYTES.set(process_rss_bytes)
      sample_puma_pool!
    rescue StandardError => e
      Rails.logger.warn "⚠️ [Prometheus] Process runtime sampling failed: #{e.message}"
    end

    # Resident set size in bytes from Linux /proc/self/status (VmRSS, kB → bytes).
    # Returns 0 on non-Linux (dev/test macOS) or if unreadable — gauge stays 0.
    def self.process_rss_bytes
      kb = File.read("/proc/self/status")[/^VmRSS:\s+(\d+)\s+kB/, 1]
      kb ? kb.to_i * 1024 : 0
    rescue StandardError
      0
    end

    # Puma thread-pool stats (web process only). Handles single + clustered modes.
    # No-op when Puma is absent or stats unparseable (e.g. the Sidekiq process).
    def self.sample_puma_pool!
      return unless defined?(::Puma) && ::Puma.respond_to?(:stats)

      raw = ::Puma.stats
      stats = raw.is_a?(String) ? JSON.parse(raw) : raw
      return unless stats.is_a?(Hash)

      if (workers = stats["worker_status"])
        running = capacity = backlog = max = 0
        workers.each do |w|
          ls = w["last_status"] || {}
          running  += ls["running"].to_i
          capacity += ls["pool_capacity"].to_i
          backlog  += ls["backlog"].to_i
          max      += ls["max_threads"].to_i
        end
        PUMA_RUNNING_THREADS.set(running)
        PUMA_POOL_CAPACITY.set(capacity)
        PUMA_BACKLOG.set(backlog)
        PUMA_MAX_THREADS.set(max)
      else
        PUMA_RUNNING_THREADS.set(stats["running"].to_i)
        PUMA_POOL_CAPACITY.set(stats["pool_capacity"].to_i)
        PUMA_BACKLOG.set(stats["backlog"].to_i)
        PUMA_MAX_THREADS.set(stats["max_threads"].to_i)
      end
    rescue StandardError => e
      Rails.logger.warn "⚠️ [Prometheus] Puma stats sampling failed: #{e.message}"
    end
  end
end
