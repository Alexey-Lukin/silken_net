# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Enterprise-grade Sidekiq configuration with Redis connection pooling,
# network timeouts, and DB isolation.
#
# DB ISOLATION STRATEGY:
#   DB 0 → Sidekiq (job queues & scheduler)
#   DB 1 → Kredis (distributed locks for Web3 nonce management)
#
# This prevents a telemetry queue flood from evicting critical Web3 locks.

SIDEKIQ_REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
SIDEKIQ_REDIS_POOL_SIZE = ENV.fetch("SIDEKIQ_REDIS_POOL_SIZE", 15).to_i
SIDEKIQ_REDIS_TIMEOUT = ENV.fetch("SIDEKIQ_REDIS_TIMEOUT", 5).to_i

Sidekiq.configure_server do |config|
  config.redis = {
    url: SIDEKIQ_REDIS_URL,
    network_timeout: SIDEKIQ_REDIS_TIMEOUT,
    pool_timeout: SIDEKIQ_REDIS_TIMEOUT,
    size: SIDEKIQ_REDIS_POOL_SIZE
  }

  # [INF.14 / 06_03 §2.9] Job-контейнер віддає власний /metrics: реєстр
  # Prometheus — in-process, тож money-path/telemetry-лічильники воркерів
  # web:80 фізично не бачить. Alloy скрейпить job:9394 другим таргетом.
  config.on(:startup) do
    SilkenNet::MetricsExporter.start(port: ENV.fetch("METRICS_PORT", 9394).to_i)
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: SIDEKIQ_REDIS_URL,
    network_timeout: SIDEKIQ_REDIS_TIMEOUT,
    pool_timeout: SIDEKIQ_REDIS_TIMEOUT,
    size: ENV.fetch("SIDEKIQ_CLIENT_POOL_SIZE", 5).to_i
  }
end
