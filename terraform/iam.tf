# SPDX-License-Identifier: AGPL-3.0-or-later
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

# IAP admin access (INF.20 (в)) — human operators enter the Anchor through the IAP
# tunnel with sudo (coap.env is root-owned 0600; systemctl needs it). osAdminLogin,
# not osLogin: the plain role gets a shell but no sudo. tunnelResourceAccessor lets
# the same identity open the IAP tunnel itself.
resource "google_project_iam_member" "iap_admin_os_login" {
  for_each = toset(var.iap_admin_members)
  project  = var.project_id
  role     = "roles/compute.osAdminLogin"
  member   = each.value
}

resource "google_project_iam_member" "iap_admin_tunnel" {
  for_each = toset(var.iap_admin_members)
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
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

# Cloud SQL Client — break-glass Auth-Proxy session from an admin workstation;
# the runtime path is the private VPC IP + password, not this role.
resource "google_project_iam_member" "deploy_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Storage Object Admin — scoped to the Terraform state bucket so the deploy SA can
# read/write `terraform/state` objects (the GCS backend in main.tf). Bucket is created
# out-of-band by bootstrap.sh (chicken-and-egg before `terraform init`). Scoped to the
# bucket, NOT project-wide, so the SA cannot touch Active Storage / other buckets. [INF.15]
resource "google_storage_bucket_iam_member" "deploy_tf_state" {
  bucket = "silken-net-terraform-state"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.deploy.email}"
}

# Service Account User — the deploy SA must "act as" the runtime SA when it creates
# compute instances that run under that SA (Ingress Anchor service_account block). [INF.15]
resource "google_service_account_iam_member" "deploy_act_as" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deploy.email}"
}
