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
#   GCP (Kamal):  n2-standard-2 → 2 vCPU, 8 GB RAM  → WEB_CONCURRENCY=2
#   Akash (SDL):  4 CPU units,   8 GB RAM             → WEB_CONCURRENCY=4
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
# full concurrency math including Solid Queue and ActionCable headroom.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# ---------------------------------------------------------------------------
# 2. Workers — forked processes (clustered mode)
# ---------------------------------------------------------------------------
# Each worker is a forked copy of the master process. Set to the number of
# available CPU cores for maximum throughput. Combined with preload_app!, the
# master loads the app once and workers share read-only memory pages (CoW).
#
# Formula: WEB_CONCURRENCY = number of vCPUs (or CPU units on Akash).
# Total Puma threads = WEB_CONCURRENCY × RAILS_MAX_THREADS.
# Total DB connections per database = WEB_CONCURRENCY × pool (see database.yml).
#
# Defaults:
#   GCP  (2 vCPU):  WEB_CONCURRENCY=2 → 2 workers × 3 threads = 6 threads
#   Akash (4 CPU):  WEB_CONCURRENCY=4 → 4 workers × 3 threads = 12 threads
workers ENV.fetch("WEB_CONCURRENCY", 2)

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
# and on_worker_boot hooks below handle reconnection safely.
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

# 6a. Before fork — master disconnects shared resources
before_fork do
  # Disconnect all ActiveRecord connection pools (primary, cache, queue, cable).
  # Workers will establish their own connections on first use via on_worker_boot.
  ActiveRecord::Base.connection_handler.clear_all_connections!(:all)

  # Disconnect Sidekiq client Redis pool. Workers re-initialize from the
  # Sidekiq initializer which reads REDIS_URL on boot.
  Sidekiq.configure_client { |config| config.redis = { size: 0 } } if defined?(Sidekiq)
end

# 6b. After fork — each worker establishes its own connections
on_worker_boot do
  # Re-establish ActiveRecord connections for all databases.
  # Rails 8 multi-database (primary, cache, queue, cable) automatically
  # creates pools for each `connects_to` database on first query, but
  # calling establish_connection ensures the primary pool is ready immediately.
  ActiveRecord::Base.establish_connection

  # Re-initialize Kredis Redis connection if Kredis is loaded.
  # Kredis uses a separate Redis DB (DB 1) for distributed locks.
  if defined?(Kredis)
    Kredis.configurator.instance_variable_set(:@connections, {})
  end
end

# ---------------------------------------------------------------------------
# 7. Plugins
# ---------------------------------------------------------------------------
# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments.
# Solid Queue spawns its own threads (configured in config/queue.yml) within
# each Puma worker. These threads need DB connections — accounted for in
# database.yml pool size calculation.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# ---------------------------------------------------------------------------
# 8. PID file
# ---------------------------------------------------------------------------
# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
