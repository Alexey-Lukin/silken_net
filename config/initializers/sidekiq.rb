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
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: SIDEKIQ_REDIS_URL,
    network_timeout: SIDEKIQ_REDIS_TIMEOUT,
    pool_timeout: SIDEKIQ_REDIS_TIMEOUT,
    size: ENV.fetch("SIDEKIQ_CLIENT_POOL_SIZE", 5).to_i
  }
end
