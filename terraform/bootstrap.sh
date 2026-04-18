#!/usr/bin/env bash
# ============================================================================
# Terraform State Bootstrap Script
# ============================================================================
# This script solves the chicken-and-egg problem: the GCS bucket for Terraform
# state must exist BEFORE the first `terraform init`.
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

echo "🌲 SilkenNet Terraform Bootstrap"
echo "================================"
echo "Project:  ${PROJECT_ID}"
echo "Bucket:   gs://${BUCKET_NAME}"
echo "Region:   ${REGION}"
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

# 4. Create GCS bucket for Terraform state (if not exists)
if gsutil ls -b "gs://${BUCKET_NAME}" 2>/dev/null; then
  echo "✅ Bucket gs://${BUCKET_NAME} already exists"
else
  echo "🪣 Creating GCS bucket gs://${BUCKET_NAME}..."
  gsutil mb -p "${PROJECT_ID}" -l "${REGION}" -b on "gs://${BUCKET_NAME}"
  echo "✅ Bucket created"
fi

# 5. Enable versioning (critical for state recovery)
echo "📦 Enabling object versioning on state bucket..."
gsutil versioning set on "gs://${BUCKET_NAME}"

# 6. Set lifecycle policy — keep 30 versions, delete after 90 days
echo "🔄 Setting lifecycle policy (30 noncurrent versions, 90-day cleanup)..."
cat > /tmp/lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"numNewerVersions": 30}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"daysSinceNoncurrentTime": 90}
    }
  ]
}
EOF
gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}"
rm -f /tmp/lifecycle.json

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
