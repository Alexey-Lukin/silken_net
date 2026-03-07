# Memorystore Redis for Sidekiq queues
resource "google_redis_instance" "silken_redis" {
  name           = "silken-redis"
  tier           = "BASIC"
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region

  location_id = var.zone

  authorized_network = google_compute_network.silken_net_vpc.id

  redis_version = "REDIS_7_0"
  display_name  = "Silken Net Redis (Sidekiq)"

  redis_configs = {
    maxmemory-policy = "noeviction"
  }

  depends_on = [google_project_service.redis]
}
