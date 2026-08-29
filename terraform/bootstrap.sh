#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ============================================================================
# Terraform State Bootstrap Script
# ============================================================================
# This script solves the chicken-and-egg problem: the GCS bucket for Terraform
# state must exist BEFORE the first `terraform init` — and so must the CMEK
# key that encrypts it [SEC.22], which is why the silken-tfstate-ew1 keyring
# lives HERE (gcloud, out-of-band) and not in kms.tf like its two siblings.
#
# Usage:
#   1. Authenticate: gcloud auth application-default login
#   2. Set your project: export GCP_PROJECT_ID=your-project-id
#   3. Run: ./terraform/bootstrap.sh
#   4. Then: cd terraform && terraform init
#
# This script is idempotent — safe to run multiple times.
# ============================================================================

set -euo pipefail

# Configuration (must match terraform/main.tf backend "gcs" block)
BUCKET_NAME="silken-net-terraform-state"
REGION="europe-west1"
PROJECT_ID="${GCP_PROJECT_ID:?Error: Set GCP_PROJECT_ID environment variable}"

# CMEK for the state bucket [SEC.22]: tf-state is a full plaintext copy of every
# secret terraform touches (db_password et al) — second copy after Kamal-ENV and
# coap.env. Keyring MUST be in the exact bucket region (hard KMS<->GCS constraint).
KMS_KEYRING="silken-tfstate-ew1"
KMS_KEY="tfstate"
KEY_RESOURCE="projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KMS_KEYRING}/cryptoKeys/${KMS_KEY}"

echo "🌲 SilkenNet Terraform Bootstrap"
echo "================================"
echo "Project:  ${PROJECT_ID}"
echo "Bucket:   gs://${BUCKET_NAME}"
echo "Region:   ${REGION}"
echo "CMEK:     ${KEY_RESOURCE}"
echo ""

# 1. Verify gcloud authentication
if ! gcloud auth list --format="value(account)" --filter="status:ACTIVE" --limit=1 2>/dev/null | grep -q .; then
  echo "❌ No active gcloud authentication found."
  echo "   Run: gcloud auth application-default login"
  exit 1
fi

# 2. Set project
gcloud config set project "${PROJECT_ID}" --quiet

# 3. Enable required APIs
echo "📡 Enabling required GCP APIs..."
gcloud services enable storage.googleapis.com --quiet
gcloud services enable compute.googleapis.com --quiet
gcloud services enable sqladmin.googleapis.com --quiet
gcloud services enable cloudkms.googleapis.com --quiet

# 4. KMS keyring + key for state-bucket CMEK [SEC.22]
# `create` is NOT idempotent (409 ALREADY_EXISTS kills the script under -e),
# so guard with describe — same pattern as the bucket check below.
if gcloud kms keyrings describe "${KMS_KEYRING}" --location="${REGION}" >/dev/null 2>&1; then
  echo "✅ KMS keyring ${KMS_KEYRING} already exists"
else
  echo "🔐 Creating KMS keyring ${KMS_KEYRING}..."
  gcloud kms keyrings create "${KMS_KEYRING}" --location="${REGION}"
fi

if gcloud kms keys describe "${KMS_KEY}" --keyring="${KMS_KEYRING}" --location="${REGION}" >/dev/null 2>&1; then
  echo "✅ KMS key ${KMS_KEY} already exists"
else
  echo "🔐 Creating KMS key ${KMS_KEY} (90d rotation)..."
  # --purpose takes the gcloud literal "encryption" (Terraform's ENCRYPT_DECRYPT
  # is a different client's spelling). --next-rotation-time is omitted on
  # purpose: gcloud then schedules the first rotation one period from creation,
  # which spares a cross-platform (macOS/Linux) `date` incantation. Rotation
  # mints a new PRIMARY; old versions stay decrypt-capable, so existing state
  # versions keep reading.
  gcloud kms keys create "${KMS_KEY}" \
    --keyring="${KMS_KEYRING}" \
    --location="${REGION}" \
    --purpose="encryption" \
    --rotation-period="90d"
fi

# 5. Create GCS bucket for Terraform state (if not exists)
if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "✅ Bucket gs://${BUCKET_NAME} already exists"
else
  echo "🪣 Creating GCS bucket gs://${BUCKET_NAME}..."
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

# 6. Default CMEK on the bucket [SEC.22]
# The crypto principal is the GCS SERVICE AGENT (service-<num>@gs-project-accounts…),
# NOT the deploy SA — the terraform gcs-backend needs only storage.objectAdmin on
# the bucket (already scoped in iam.tf), no KMS role. Skip fast when already set.
if gcloud storage buckets describe "gs://${BUCKET_NAME}" --format=json 2>/dev/null | grep -q "${KEY_RESOURCE}"; then
  echo "✅ Default CMEK already set on gs://${BUCKET_NAME}"
else
  echo "🔐 Authorizing GCS service agent on ${KMS_KEY} + setting default CMEK..."
  gcloud storage service-agent --project="${PROJECT_ID}" --authorize-cmek="${KEY_RESOURCE}"
  # Documented GCS race: the service-agent IAM grant can take ~30s to propagate;
  # updating the bucket immediately 403s intermittently under -e.
  echo "⏳ Waiting 30s for IAM propagation (documented GCS delay)..."
  sleep 30
  gcloud storage buckets update "gs://${BUCKET_NAME}" --default-encryption-key="${KEY_RESOURCE}"
  echo "✅ Default CMEK set (applies to NEW writes; pre-existing objects re-wrap on next state write)"
fi

# 7. Enable versioning (critical for state recovery)
echo "📦 Enabling object versioning on state bucket..."
gcloud storage buckets update "gs://${BUCKET_NAME}" --versioning

# 8. Lifecycle — keep 10 noncurrent versions, delete after 30 days [SEC.22]
# Every noncurrent version is one more full plaintext copy of the secrets in
# state; 10/30d still covers rollback of a corrupted apply without hoarding
# a 90-day secret trail.
echo "🔄 Setting lifecycle policy (10 noncurrent versions, 30-day cleanup)..."
LIFECYCLE_JSON="$(mktemp)"
cat > "${LIFECYCLE_JSON}" << 'EOF'
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"numNewerVersions": 10}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"daysSinceNoncurrentTime": 30}
    }
  ]
}
EOF
gcloud storage buckets update "gs://${BUCKET_NAME}" --lifecycle-file="${LIFECYCLE_JSON}"
rm -f "${LIFECYCLE_JSON}"

echo ""
echo "✅ Bootstrap complete!"
echo ""
echo "Next steps:"
echo "  1. cd terraform"
echo "  2. cp terraform.tfvars.example terraform.tfvars"
echo "  3. Edit terraform.tfvars with your values"
echo "  4. terraform init"
echo "  5. terraform plan"
echo "  6. terraform apply"
