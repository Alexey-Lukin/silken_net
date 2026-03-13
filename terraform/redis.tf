# Memorystore Redis for Sidekiq queues and Kredis distributed locks.
#
# DB ISOLATION STRATEGY (logical databases on a single instance):
#   DB 0 → Sidekiq job queues (REDIS_URL)
#   DB 1 → Kredis distributed locks for Web3 nonce management (KREDIS_REDIS_URL)
#
# This prevents a telemetry queue flood from evicting critical Web3 nonce locks,
# which would cause EVM nonce collisions and double-spend vulnerabilities.
#
# [ZONE COLOCATION]: Redis MUST be in the same zone as compute instances (var.zone)
# to avoid inter-zone network traffic costs which can bankrupt at scale.
resource "google_redis_instance" "silken_redis" {
  name           = "silken-redis"
  tier           = var.redis_ha_enabled ? "STANDARD_HA" : "BASIC"
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region

  location_id             = var.zone
  alternative_location_id = var.redis_ha_enabled ? var.redis_alternative_zone : null

  authorized_network = google_compute_network.silken_net_vpc.id

  redis_version = "REDIS_7_0"
  display_name  = "Silken Net Redis (Sidekiq + Kredis)"

  transit_encryption_mode = "SERVER_AUTHENTICATION"

  redis_configs = {
    # [MEMORY WALL FIX]: volatile-lru evicts only keys WITH an expire (TTL) set,
    # such as cache entries and silence filters. Sidekiq queue keys have no TTL
    # and will never be evicted. This prevents Redis OOM crashes when the telemetry
    # queue grows faster than workers can drain it, while preserving job data.
    maxmemory-policy = "volatile-lru"
  }

  depends_on = [google_project_service.redis]
}
