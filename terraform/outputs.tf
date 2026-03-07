output "web_server_ips" {
  description = "External IP addresses of web server instances"
  value       = google_compute_address.web[*].address
}

output "database_private_ip" {
  description = "Private IP of Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.silken_db.private_ip_address
}

output "database_connection_name" {
  description = "Cloud SQL connection name"
  value       = google_sql_database_instance.silken_db.connection_name
}

output "database_url" {
  description = "PostgreSQL connection URL for the primary database"
  value       = "postgres://silken_net:${var.db_password}@${google_sql_database_instance.silken_db.private_ip_address}:5432/silken_net_production"
  sensitive   = true
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
  description = "Redis connection URL for Sidekiq"
  value       = "redis://${google_redis_instance.silken_redis.host}:${google_redis_instance.silken_redis.port}/0"
}

output "artifact_registry_url" {
  description = "Docker registry URL for Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/silken-net"
}

output "service_account_email" {
  description = "Deploy service account email"
  value       = google_service_account.deploy.email
}

output "service_account_key" {
  description = "Deploy service account JSON key (base64)"
  value       = google_service_account_key.deploy_key.private_key
  sensitive   = true
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.silken_net_vpc.name
}
