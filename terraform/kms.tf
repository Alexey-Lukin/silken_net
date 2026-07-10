# =============================================================================
# Cloud KMS — customer-managed encryption keys (CMEK).
# =============================================================================
#
# Home for the project's KMS keyring/IAM architecture. Three keyrings, ISOLATED
# by purpose so a role on one can never leak to a sibling (blast-radius boundary):
#
#   silken-disk-ew1    (this file)  — ENCRYPT_DECRYPT, disk CMEK.
#                                      Grantee: Compute Engine Service Agent only.
#   silken-sign-ew1    (SEC.17, pre-mainnet; keyring-arch §5.6, custody §5.5) — ASYMMETRIC_SIGN,
#                                      oracle-minter/slasher. Grantee: the job
#                                      signer SA only. NEVER the compute agent.
#   silken-tfstate-ew1 (bootstrap.sh, out-of-band [SEC.22]) — ENCRYPT_DECRYPT,
#                                      state-bucket CMEK. Chicken-and-egg: the
#                                      backend bucket needs the key before
#                                      terraform init can run, so gcloud owns it
#                                      (drift-invisible here; `terraform import`
#                                      if that ever matters). Grantee: the GCS
#                                      service agent only — the deploy SA needs
#                                      NO KMS role (gcs-backend reads/writes with
#                                      storage.objectAdmin alone, iam.tf).
#
# Coherence: same region (europe-west1, EU data-at-rest pin — and a hard KMS<->GCS
# same-region constraint for the state bucket), purpose-scoped names, one
# architecture home — so SEC.17 later just adds silken-sign-ew1 with zero rename.
# GCP's `purpose` enum is a hard type barrier (a symmetric key physically cannot
# sign, an asymmetric key cannot wrap a disk) → the only residual risk is IAM
# scope, eliminated by the keyring split + key-level bindings below.
# =============================================================================

resource "google_project_service" "cloudkms" {
  service            = "cloudkms.googleapis.com"
  disable_on_destroy = false # match main.tf service pattern
}

# Unconditional project lookup — the compute service-agent email needs the
# project NUMBER. billing.tf's `data.google_project.current` is COUNT-guarded
# (null when billing is unmanaged), so it can't back an always-on binding.
data "google_project" "project" {}

# --- Disk CMEK keyring (isolated) ------------------------------------------
resource "google_kms_key_ring" "disk" {
  name       = "silken-disk-ew1"
  location   = var.region # MUST match the disk region (europe-west1)
  depends_on = [google_project_service.cloudkms]
}

# Boot-disk key for the Ingress Anchor (holds /etc/silkennet/coap.env —
# RAILS_MASTER_KEY / PROVISIONING_MASTER_KEY). CMEK gives key-lifecycle control
# (disable/rotate/audit/crypto-shred) over that at-rest secret material.
resource "google_kms_crypto_key" "anchor_boot" {
  name     = "anchor-boot"
  key_ring = google_kms_key_ring.disk.id
  purpose  = "ENCRYPT_DECRYPT"

  # 90d rotation. NOTE: rotation mints a new PRIMARY version but does NOT
  # re-encrypt the live disk (it keeps wrapping under its original version);
  # old versions stay enabled + decrypt-capable → rotation never breaks boot.
  rotation_period = "7776000s"

  # Version-destroy grace pinned to 30d (Terraform/API default is 24h; the DR
  # canon 06_06 §1 promises 30d — pin so the doc stays code-true). Only bites on
  # an out-of-band gcloud/console version-destroy — prevent_destroy blocks the
  # Terraform-initiated ones.
  destroy_scheduled_duration = "2592000s"

  # Destroying the key permanently orphans the disk (unbootable). KMS keys are
  # also undeletable in GCP; dev teardown needs `terraform state rm` first.
  lifecycle {
    prevent_destroy = true
  }
}

# The KMS principal that wraps/unwraps the boot-disk DEK is the Compute Engine
# SERVICE AGENT (service-<PROJECT_NUMBER>@compute-system…) — NOT the deploy SA,
# NOT the default compute SA. It gets encrypter/decrypter on THIS key only.
# `google_project_service_identity` is NOT used: it is beta-only and excludes
# compute (verified against terraform-google-project-factory +
# cloud-foundation-fabric — both build the string + depend on API enablement).
resource "google_kms_crypto_key_iam_member" "anchor_boot_agent" {
  crypto_key_id = google_kms_crypto_key.anchor_boot.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@compute-system.iam.gserviceaccount.com"

  depends_on = [google_project_service.compute]
}
