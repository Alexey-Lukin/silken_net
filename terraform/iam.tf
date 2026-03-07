# Service account for deployment and application runtime
resource "google_service_account" "deploy" {
  account_id   = "silken-net-deploy"
  display_name = "Silken Net Deploy Service Account"
}

# Compute Admin role — manage instances during deployment
resource "google_project_iam_member" "deploy_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Storage Admin role — push/pull Docker images to Artifact Registry
resource "google_project_iam_member" "deploy_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Artifact Registry Writer — push Docker images
resource "google_project_iam_member" "deploy_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Generate JSON key for the service account (used in CI/CD)
resource "google_service_account_key" "deploy_key" {
  service_account_id = google_service_account.deploy.name
}
