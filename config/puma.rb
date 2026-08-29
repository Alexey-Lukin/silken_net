# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# Puma Configuration — SilkenNet IoT/Web3 Production Server
# =============================================================================
#
# Architecture: Thruster (HTTP/2) → Puma (clustered) → Rails 8.1
#
# Thruster handles TLS termination, HTTP/2, gzip, and slow-client buffering,
# so Puma focuses purely on fast request execution with forked workers.
#
# Memory strategy: preload_app! + jemalloc (LD_PRELOAD in Dockerfile) enables
# Copy-on-Write (CoW) across forked workers, cutting per-worker RSS by ~30-40%.
#
# Infrastructure targets:
#   Kamal (GCP):  the only target. deploy.yml pins WEB_CONCURRENCY=2 — and since
#                 [OPS.37] that stopped being a conservative fallback default and
#                 became the SPEC of the app host, so it moves together with the
#                 machine when terraform regains the web resource. The separate
#                 e2-small Ingress Anchor runs no Puma (CoAP daemon + HAProxy only —
#                 terraform/compute.tf).
#
# For DSL reference see: https://puma.io/puma/Puma/DSL.html
# =============================================================================

# ---------------------------------------------------------------------------
# 1. Threads — per-worker thread pool
# ---------------------------------------------------------------------------
# Each Puma worker runs this many threads. Threads share the GVL but improve
# throughput during IO waits (database queries, Web3 RPC calls, Redis).
# Keep low (3–5) to limit GVL contention and per-process connection usage.
#
# The database.yml pool size must be >= this value. See database.yml for the
# full concurrency math including ActionCable headroom.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# ---------------------------------------------------------------------------
# 1b. Max IO threads — Web3 RPC concurrency without OOM (Puma 8.0+)
# ---------------------------------------------------------------------------
# When a request handler calls `env["puma.mark_as_io_bound"]&.call`, Puma
# treats that worker thread as IO-bound and is allowed to spawn additional
# threads beyond `max_threads` (up to `max_threads + max_io_threads`) without
# blocking the regular CPU pool.
#
# 🔴 [ARCH.80, присуд власника 2026-08-14] Жоден шлях НЕ позначений IO-bound —
# `MarkWeb3RequestsAsIoBound` знято разом з обома його записами.
#
# Тут раніше стояло: «`oracle_callbacks#create` і `provisioning#register`
# синхронно ходять по HTTP до IoTeX W3bstream / Polygon RPC / Hadron KYC».
# **Виміряно 2026-08-14 — жоден із двох цього не робить:** обидва лише кладуть
# job у Sidekiq (`perform_async`), тобто синхронного вихідного HTTP на цих
# шляхах немає взагалі. Гірше того, `provisioning#register` виконує
# HKDF-деривацію ключа, тобто він CPU-bound — позначати його IO-bound означало
# дозволяти Puma перепідписувати потоки під роботу, що ТРИМАЄ процесор, тобто
# прапорець брехав у шкідливий бік.
#
# `max_io_threads` лишається налаштованим СВІДОМО: механізм Puma працює, і
# повернути його треба буде того дня, коли зʼявиться справжній синхронний
# RPC-шлях — тоді ж повертається й middleware (`git log` віддає його цілим).
# Доти бонус недосяжний, бо ніхто не кличе `puma.mark_as_io_bound`.
#
# Default 0 means "no IO-thread bonus" — fully backward-compatible.
max_io_threads ENV.fetch("PUMA_MAX_IO_THREADS", 16).to_i

# ---------------------------------------------------------------------------
# 2. Workers — forked processes (clustered mode)
# ---------------------------------------------------------------------------
# Each worker is a forked copy of the master process. Set to the number of
# available CPU cores for maximum throughput. Combined with preload_app!, the
# master loads the app once and workers share read-only memory pages (CoW).
#
# Formula: WEB_CONCURRENCY = number of vCPUs.
# Total Puma threads = WEB_CONCURRENCY × RAILS_MAX_THREADS.
# Total DB connections per database = WEB_CONCURRENCY × pool (see database.yml).
#
# Defaults:
#   Kamal/GCP: WEB_CONCURRENCY=2 → 2 workers × 3 threads = 6 threads
#     — assumes a 2-vCPU app host. Raising the tier without raising this wastes it;
#       raising this without the tier oversubscribes. One value, one machine.
#
# In development we run single-mode (workers=0) by default, which matches the
# `cluster do … end` block below — the connection-lifecycle hooks intentionally
# never fire in single mode. This makes `bin/rails server` predictable for
# debuggers (binding.irb / debug gem) and avoids the master/worker fork dance.
default_workers = ENV.fetch("RAILS_ENV", "development") == "development" ? 0 : 2
workers ENV.fetch("WEB_CONCURRENCY", default_workers)

# ---------------------------------------------------------------------------
# 3. Preload — Copy-on-Write memory optimization
# ---------------------------------------------------------------------------
# Loads the Rails application in the master process before forking workers.
# Forked workers share the master's memory pages (code, gem bytecode, i18n
# data) via OS-level CoW. Pages are only duplicated when a worker writes to
# them. Combined with jemalloc (which avoids glibc's per-arena fragmentation),
# this reduces total RSS by 30-40% compared to non-preloaded workers.
#
# IMPORTANT: preload_app! means connections opened in the master (ActiveRecord,
# Redis) are inherited by workers as stale file descriptors. The before_fork
# and before_worker_boot hooks below handle reconnection safely.
#
# Note (Puma 8.0+): preload_app! is now the default in clustered mode, so this
# line is technically redundant. We keep it explicit for clarity and to guard
# against future default changes. See docs/06_05_Puma_Configuration.md
preload_app!

# ---------------------------------------------------------------------------
# 4. Worker timeout — Web3 RPC stall protection
# ---------------------------------------------------------------------------
# If a worker doesn't respond to the master's heartbeat within this many
# seconds, the master kills it with SIGKILL and spawns a replacement.
#
# Web3 RPC calls (Alchemy, Infura, Polygon) can hang indefinitely when a
# node is overloaded or the network partitions. 60s is generous enough for
# legitimate long-running requests (telemetry batch inserts, AI Lorenz
# analysis) but ruthlessly kills truly stuck workers.
#
# Thruster buffers slow clients upstream, so Puma workers never block on
# client socket reads — this timeout targets purely server-side execution.
worker_timeout ENV.fetch("PUMA_WORKER_TIMEOUT", 60)

# ---------------------------------------------------------------------------
# 4b. Forced-shutdown debugging — backtrace dump on SIGKILL (Puma 8.0+)
# ---------------------------------------------------------------------------
# When `worker_timeout` fires (60s above), Puma SIGKILLs the worker. With
# `shutdown_debug on_force: true` Puma writes the backtraces of ALL threads
# to STDERR right before kill. This is the only way to learn which Web3 RPC
# call (or DB query) hung the worker.
#
# `on_force: true` means dumps happen ONLY on forced shutdown — graceful
# Kamal phased restarts stay quiet (no log spam). Without `on_force` Puma
# would dump on every restart, drowning real incidents.
#
# Backtraces flow through Rails structured-JSON logger (`06_03 §3.3`) into
# GCP Cloud Logging, where the `sentry_trace_id` field correlates them with
# Sentry events. PUMA-DBG-1 in `06_05`. (F-3)
shutdown_debug on_force: true

# ---------------------------------------------------------------------------
# 5. Port
# ---------------------------------------------------------------------------
# Thruster listens on PORT (default 80 in production Docker) and reverse-
# proxies to Puma on port 3000. In development, Puma listens directly.
port ENV.fetch("PORT", 3000)

# ---------------------------------------------------------------------------
# 6. Connection lifecycle hooks (clustered mode safety)
# ---------------------------------------------------------------------------
# preload_app! loads the app in the master process. Database connections and
# Redis sockets opened during boot become invalid in forked workers (the
# underlying file descriptors are shared, causing socket hijacking and
# protocol desync). These hooks disconnect before fork and reconnect after.
#
# The `cluster do … end` block (Puma 8.0+ DSL, F-2 in 06_05) makes the intent
# explicit: these hooks NEVER run in single mode (`workers 0`, our default
# in `RAILS_ENV=development`). Previously the same hooks were defined at the
# top level and Puma silently ignored them in single mode — correct behavior
# but obscure. PUMA-DSL-1.
cluster do
  # 6a. Before fork — master disconnects shared resources
  before_fork do
    # Disconnect all ActiveRecord connection pools (primary, cache, cable).
    # Workers will establish their own connections on first use via before_worker_boot.
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)

    # Shutdown the Sidekiq client Redis connection pool inherited from the
    # master. Each worker re-establishes its own pool from the initializer.
    if defined?(Sidekiq)
      config = Sidekiq.default_configuration
      config.redis_pool.shutdown(&:close) if config.respond_to?(:redis_pool)
    end
  end

  # 6b. After fork — each worker establishes its own connections
  #
  # Note (Puma 7.0): the `on_worker_boot` hook was renamed to `before_worker_boot`.
  # The old name is preserved as a deprecated alias but emits warnings. We use
  # the new name to be Puma 7.0+ compliant. See docs/06_05_Puma_Configuration.md.
  before_worker_boot do
    # Re-establish ActiveRecord connections for all databases.
    # Rails 8 multi-database (primary, cache, queue, cable) automatically
    # creates pools for each `connects_to` database on first query, but
    # calling establish_connection ensures the primary pool is ready immediately.
    ActiveRecord::Base.establish_connection

    # Clear cached Kredis Redis connections inherited from the master.
    # Kredis uses a separate Redis DB (DB 1) for distributed locks.
    # New connections are lazily established on first use in the worker.
    Kredis.clear_all if defined?(Kredis)
  end
end

# ---------------------------------------------------------------------------
# 7. Plugins
# ---------------------------------------------------------------------------
# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Background jobs: all 32 workers use Sidekiq directly (separate process).
# ActiveJob (mailer deliver_later) is also routed to Sidekiq via
# config.active_job.queue_adapter = :sidekiq in production.rb.
# No in-process job supervisor needed — Puma focuses purely on HTTP.

# ---------------------------------------------------------------------------
# 8. PID file
# ---------------------------------------------------------------------------
# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
