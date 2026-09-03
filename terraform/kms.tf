# SPDX-License-Identifier: AGPL-3.0-or-later
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

# Boot-disk key for the APP host (Kamal web+job+coap). Same keyring, own key —
# key-level IAM is the barrier, so a second key costs nothing and keeps the two
# machines independently shreddable.
#
# 🔴 WHY the app host needs CMEK at all, measured against the kamal source rather
# than assumed (kamal 2.12, lib/kamal/cli/app/boot.rb): booting a role runs
#   upload! role.secrets_io(host), role.secrets_path, mode: "0600"
# and `secrets_path` resolves to .kamal/apps/<service>-<dest>/env/roles/<role>.env
# on the HOST. So the money/signing quintet (ORACLE_MINTER/SLASHER/CELO +
# ETHEREUM_ANCHOR + SOLANA_WALLET_KEYPAIR) lands as PLAINTEXT on this disk under
# the `job` role — exactly the class the Anchor got CMEK for (/etc/silkennet/
# coap.env). At-rest ≠ runtime [SEC.22]: this does not seal anything (the real
# seal is SEC.17 KMS-signing), it buys key-lifecycle control — disable, rotate,
# audit, crypto-shred — over secret material that otherwise sits on a PD in the
# clear. ⚠️ Timing is the whole discount: `kms_key_self_link` is ForceNew, so
# adding it to a LIVE instance replaces the VM. Done pre-first-deploy it is free.
resource "google_kms_crypto_key" "app_boot" {
  name     = "app-boot"
  key_ring = google_kms_key_ring.disk.id
  purpose  = "ENCRYPT_DECRYPT"

  # Same 90d/30d posture as anchor-boot — see that key for why rotation never
  # breaks boot and why the destroy grace is pinned rather than defaulted.
  rotation_period            = "7776000s"
  destroy_scheduled_duration = "2592000s"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "app_boot_agent" {
  crypto_key_id = google_kms_crypto_key.app_boot.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@compute-system.iam.gserviceaccount.com"

  depends_on = [google_project_service.compute]
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

# --- Oracle signing keyring (SEC.17, flag-gated) ---------------------------
# ASYMMETRIC_SIGN secp256k1 for the Polygon oracle-minter / oracle-slasher
# custody move (docs/06_04 §5.5; 00_07 SEC.17). Every resource is COUNT-gated
# on `enable_oracle_signing_keys` so `plan` without the flag is a no-op and the
# keys are created only by a deliberate founder-local `apply` (INF.22).
#
# Grantee = the VM service account (`silken-net-deploy`) at KEY level only:
# `signerVerifier` (asymmetricSign) + `viewer` (getPublicKey → address
# derivation). ⚠️ IAM alone is NOT enough: compute.tf pins the VM OAuth scopes
# to logging/monitoring, and Cloud KMS answers 403 without the `cloud-platform`
# scope regardless of IAM — that scope change is part of the same ⚖️, not this
# block (measured by reading 2026-09-03, SEC.17).
#
# Rotation: asymmetric keys have NO automatic rotation. A new version = a new
# public key = a NEW on-chain address, so rotation is re-funding + re-pointing
# `ORACLE_*_KMS_KEY` (the resource name carries `cryptoKeyVersions/1`).
# Protection level HSM is the only level Cloud KMS offers for EC_SIGN_SECP256K1.
resource "google_kms_key_ring" "sign" {
  count      = var.enable_oracle_signing_keys ? 1 : 0
  name       = "silken-sign-ew1"
  location   = var.region
  depends_on = [google_project_service.cloudkms]
}

resource "google_kms_crypto_key" "oracle_signer" {
  for_each = var.enable_oracle_signing_keys ? toset(["oracle-minter", "oracle-slasher"]) : toset([])

  name     = each.key
  key_ring = google_kms_key_ring.sign[0].id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "EC_SIGN_SECP256K1_SHA256"
    protection_level = "HSM"
  }

  # A destroyed signing key = an on-chain role holder that can never act again
  # (MINTER_ROLE / SLASHER_ROLE are granted to its address); Timelock re-grant
  # is the only recovery, so the key is never a casual `apply` casualty.
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "oracle_signer_sign" {
  for_each = google_kms_crypto_key.oracle_signer

  crypto_key_id = each.value.id
  role          = "roles/cloudkms.signerVerifier"
  member        = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_kms_crypto_key_iam_member" "oracle_signer_view" {
  for_each = google_kms_crypto_key.oracle_signer

  crypto_key_id = each.value.id
  role          = "roles/cloudkms.viewer"
  member        = "serviceAccount:${google_service_account.deploy.email}"
}
