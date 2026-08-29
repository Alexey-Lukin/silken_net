# SPDX-License-Identifier: AGPL-3.0-or-later
output "ingress_ip" {
  description = "Static external IP of the Ingress Anchor — point IoT Queens (CoAP) and DNS here"
  value       = google_compute_address.ingress_ip.address
}

output "database_private_ip" {
  description = "Private IP of Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.silken_db.private_ip_address
}

output "database_connection_name" {
  description = "Cloud SQL connection name (used by Cloud SQL Auth Proxy)"
  value       = google_sql_database_instance.silken_db.connection_name
}

output "database_url" {
  description = "PostgreSQL connection URL for the primary database (private IP, use within GCP VPC only)"
  value       = "postgres://${google_sql_user.silken_net.name}:${var.db_password}@${google_sql_database_instance.silken_db.private_ip_address}:5432/${google_sql_database.production.name}"
  sensitive   = true
}

output "database_url_proxy" {
  description = "PostgreSQL connection URL via Cloud SQL Auth Proxy — break-glass admin session. Must run INSIDE the VPC (IAP-tunnel onto the Ingress Anchor, then proxy/psql there) — ipv4_enabled is false, so there is no public listener to dial from a workstation [OPS.37]. Runtime uses the private VPC IP directly"
  value       = "postgres://${google_sql_user.silken_net.name}:${var.db_password}@127.0.0.1:5432/${google_sql_database.production.name}"
  sensitive   = true
}

output "read_replica_ips" {
  description = "Private IPs of Cloud SQL read replicas"
  value       = google_sql_database_instance.read_replica[*].private_ip_address
}

output "artifact_registry_url" {
  description = "Docker registry URL for Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/silken-net"
}

output "service_account_email" {
  description = "Deploy service account email — set as GitHub repo Variable GCP_SERVICE_ACCOUNT (keyless CI auth, INF.22)"
  value       = google_service_account.deploy.email
}

# [INF.22] After the first (founder-local) apply, set this as the GitHub repo Variable
# GCP_WORKLOAD_IDENTITY_PROVIDER — the deploy/drift workflows auth with it instead of
# GCP_SA_KEY. Non-secret (a resource identifier, not a credential).
output "workload_identity_provider" {
  description = "WIF provider resource name — set as GitHub repo Variable GCP_WORKLOAD_IDENTITY_PROVIDER (keyless CI auth, INF.22)"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "nat_name" {
  description = "Cloud NAT resource name (IPs are auto-allocated)"
  value       = google_compute_router_nat.nat.name
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.silken_net_vpc.name
}

# [OPS.37] The app host's PRIVATE IP — there is no external one by design (the
# Ingress Anchor is the single public entry). This is the value step 10 of the
# deploy runbook feeds to the Anchor:
#   gcloud compute instances add-metadata silken-net-ingress \
#     --metadata app-host-ip=$(terraform output -raw app_host_ip) --zone <zone>
# and the value that replaces the 192.168.0.1 placeholder in config/deploy.yml.
output "app_host_ip" {
  description = "Private IP of the Kamal app host (web+job+coap) — feeds the Anchor's app-host-ip metadata and config/deploy.yml servers"
  value       = google_compute_instance.app.network_interface[0].network_ip
}
