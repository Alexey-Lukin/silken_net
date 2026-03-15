# Service account for deployment and application runtime
resource "google_service_account" "deploy" {
  account_id   = "silken-net-deploy"
  display_name = "Silken Net Deploy Service Account"
  description  = "Least-privilege SA for Kamal deployment and application runtime"
}

# Compute Instance Admin (v1) — start/stop/SSH into instances during deployment
resource "google_project_iam_member" "deploy_compute_instance_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# OS Login — allow SSH via OS Login on Shielded VMs
resource "google_project_iam_member" "deploy_os_login" {
  project = var.project_id
  role    = "roles/compute.osLogin"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Artifact Registry Writer — push Docker images during deployment
resource "google_project_iam_member" "deploy_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Artifact Registry Reader — pull Docker images at runtime
resource "google_project_iam_member" "deploy_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Log Writer — send application logs to Cloud Logging
resource "google_project_iam_member" "deploy_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Monitoring Metric Writer — send metrics to Cloud Monitoring
resource "google_project_iam_member" "deploy_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Cloud SQL Client — connect via Cloud SQL Auth Proxy (required for Akash sidecar proxy)
resource "google_project_iam_member" "deploy_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}
