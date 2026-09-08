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

# IAP tunnel for the DEPLOY SA — move (4) of the INF.20 (б) glue, and the one that
# was unnamed until 2026-08-31. [OPS.37] made kamal the primary path onto a host with
# NO external IP, so `kamal deploy` reaches :22 only through an IAP ProxyCommand
# (`gcloud compute start-iap-tunnel`, config/deploy.yml `ssh:` header). The block
# above grants that role via `for_each = toset(var.iap_admin_members)` — i.e. to
# HUMANS only; the SA held `compute.osLogin` and no tunnel role at all, so the CI leg
# would 403 no matter how correct the proxy_command is, and the error names IAP rather
# than kamal. Deliberately the NARROW role: tunnelResourceAccessor opens the tunnel and
# grants no shell — the shell still comes from `compute.osLogin` above, and sudo stays
# reserved for `iap_admin_members` (which is why docker is pre-installed, not
# bootstrapped — see terraform/compute.tf `google_compute_instance.app`).
resource "google_project_iam_member" "deploy_iap_tunnel" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
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

# Cloud SQL Client — break-glass Auth-Proxy session. ⚠️ Since `ipv4_enabled = false`
# (OPS.37) that session must run INSIDE the VPC: IAP-tunnel onto the Ingress Anchor and
# proxy/psql from there. The runtime path is the private VPC IP + password, not this role.
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

# Service Account User — "act as" the runtime SA for any instance that runs under it
# (Ingress Anchor / app host `service_account` blocks). [INF.15] ⚠️ Instance CREATION is
# no longer a CI capability: [INF.22] made every `terraform apply` founder-local, so the
# grant's live justification is a `plan` refresh over those instances plus break-glass —
# not "when it creates compute instances", which is what this said until 2026-08-31.
resource "google_service_account_iam_member" "deploy_act_as" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deploy.email}"
}
# ---------------------------------------------------------------------------
# READ-ONLY grants for the scheduled drift detector (`Ops · TF Drift`, INF.22).
#
# Measured 2026-09-08: the weekly `terraform plan` died with exit 1 on 403s, so it
# could not report drift AT ALL — a detector that is always red equals a disabled
# one. Exactly two permissions were missing, and NEITHER is a write:
#   · resourcemanager.projects.getIamPolicy — refresh the 11 google_project_iam_member
#     resources above (without it, every one of them errors);
#   · servicenetworking.services.get        — refresh google_service_networking_connection
#     (database.tf), the Cloud SQL private-peering link.
#
# ⚖️ Role chosen by SURFACE SIZE, not by name (founder 2026-09-08): roles/browser is
# SIX permissions of pure hierarchy read, against 2535 in roles/iam.securityReviewer
# and 6083 in roles/viewer — both of which would have worked and both of which hand
# the CI identity a project-wide read it has no use for. This keeps the [INF.22]
# posture ("every apply is founder-local, CI is narrow") intact while letting the
# detector actually see. Same justification shape as deploy_act_as above: the live
# reason is a `plan` REFRESH, not a capability the pipeline exercises.
resource "google_project_iam_member" "deploy_drift_browser" {
  project = var.project_id
  role    = "roles/browser"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# No predefined READ-only role carries servicenetworking.services.get — verified
# 2026-09-08: roles/servicenetworking.networksViewer DOES NOT EXIST, and networksAdmin
# is write-capable. Hence a custom role holding that single permission (confirmed
# custom-role-grantable via `gcloud iam list-testable-permissions`).
resource "google_project_iam_custom_role" "drift_servicenetworking_read" {
  project     = var.project_id
  role_id     = "driftSvcNetRead"
  title       = "Drift detector — Service Networking read"
  description = "Single-permission read role so the scheduled terraform plan can refresh google_service_networking_connection. No write, no data access. [INF.22]"
  permissions = ["servicenetworking.services.get"]
  stage       = "GA"
}

resource "google_project_iam_member" "deploy_drift_servicenetworking" {
  project = var.project_id
  role    = google_project_iam_custom_role.drift_servicenetworking_read.id
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

