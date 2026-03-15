output "web_server_ips" {
  description = "External IP addresses of web server instances"
  value       = google_compute_address.web[*].address
}

output "database_private_ip" {
  description = "Private IP of Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.silken_db.private_ip_address
}

output "database_connection_name" {
  description = "Cloud SQL connection name (used by Cloud SQL Auth Proxy)"
  value       = google_sql_database_instance.silken_db.connection_name
}

output "database_public_ip" {
  description = "Public IP of Cloud SQL instance (only available when akash_enabled = true)"
  value       = var.akash_enabled ? google_sql_database_instance.silken_db.public_ip_address : null
}

output "database_url" {
  description = "PostgreSQL connection URL for the primary database"
  value       = "postgres://${google_sql_user.silken_net.name}:${var.db_password}@${google_sql_database_instance.silken_db.private_ip_address}:5432/${google_sql_database.production.name}"
  sensitive   = true
}

output "read_replica_ips" {
  description = "Private IPs of Cloud SQL read replicas"
  value       = google_sql_database_instance.read_replica[*].private_ip_address
}

output "redis_host" {
  description = "Memorystore Redis host"
  value       = google_redis_instance.silken_redis.host
}

output "redis_port" {
  description = "Memorystore Redis port"
  value       = google_redis_instance.silken_redis.port
}

output "redis_url" {
  description = "Redis connection URL for Sidekiq (DB 0)"
  value       = "redis://${google_redis_instance.silken_redis.host}:${google_redis_instance.silken_redis.port}/0"
}

output "kredis_redis_url" {
  description = "Redis connection URL for Kredis distributed locks (DB 1)"
  value       = "redis://${google_redis_instance.silken_redis.host}:${google_redis_instance.silken_redis.port}/1"
}

output "artifact_registry_url" {
  description = "Docker registry URL for Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/silken-net"
}

output "service_account_email" {
  description = "Deploy service account email"
  value       = google_service_account.deploy.email
}

output "nat_name" {
  description = "Cloud NAT resource name (IPs are auto-allocated)"
  value       = google_compute_router_nat.nat.name
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.silken_net_vpc.name
}

output "canopy_server_ip" {
  description = "External IP address of the Canopy server"
  value       = var.canopy_enabled ? google_compute_address.canopy[0].address : null
}
