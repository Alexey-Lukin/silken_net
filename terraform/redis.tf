# Memorystore Redis for Sidekiq queues
resource "google_redis_instance" "silken_redis" {
  name           = "silken-redis"
  tier           = var.redis_ha_enabled ? "STANDARD_HA" : "BASIC"
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region

  location_id             = var.zone
  alternative_location_id = var.redis_ha_enabled ? var.redis_alternative_zone : null

  authorized_network = google_compute_network.silken_net_vpc.id

  redis_version = "REDIS_7_0"
  display_name  = "Silken Net Redis (Sidekiq)"

  transit_encryption_mode = "SERVER_AUTHENTICATION"

  redis_configs = {
    maxmemory-policy = "noeviction"
  }

  depends_on = [google_project_service.redis]
}
