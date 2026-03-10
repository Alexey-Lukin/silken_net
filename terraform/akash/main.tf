# =============================================================================
# Terraform — Akash Network Deployment for SilkenNet
# =============================================================================
#
# This is a separate Terraform root module that manages the Akash deployment.
# It lives alongside the GCP infrastructure (terraform/) but has its own state
# because the two environments have different lifecycles and credentials:
#
#   terraform/          → GCP infrastructure (Cloud SQL, Redis, Compute, VPC)
#   terraform/akash/    → Akash decentralized deployment (web service only)
#
# The Akash deployment connects BACK to GCP Cloud SQL for the database —
# only the compute layer is decentralized.
#
# Usage:
#   cd terraform/akash
#   terraform init
#   terraform plan -var-file="terraform.tfvars"
#   terraform apply -var-file="terraform.tfvars"
#
# Prerequisites:
#   - Akash CLI (`akash`) installed: https://docs.akash.network/guides/cli
#   - Akash wallet funded with AKT tokens
#   - AKASH_KEY_NAME, AKASH_KEYRING_BACKEND, AKASH_ACCOUNT_ADDRESS,
#     AKASH_NODE, AKASH_CHAIN_ID environment variables set
#   - Docker image pushed to an accessible registry
#   - Cloud SQL configured for external access (public IP + SSL or proxy)
# =============================================================================

terraform {
  required_version = ">= 1.5"

  # ---------------------------------------------------------------------------
  # State Backend — separate from the GCP state to avoid coupling.
  # Uses the same GCS bucket but a different prefix.
  # ---------------------------------------------------------------------------
  backend "gcs" {
    bucket = "silken-net-terraform-state"
    prefix = "terraform/akash"
  }
}

# =============================================================================
# SDL Template Rendering
# =============================================================================
# Generates the final SDL file from the template with injected variables.
# This avoids hardcoding secrets in deploy/akash/deploy.yaml.

resource "local_file" "akash_sdl" {
  content = templatefile("${path.module}/../../deploy/akash/deploy.yaml.tpl", {
    docker_image       = var.docker_image
    rails_master_key   = var.rails_master_key
    database_url       = var.database_url
    redis_url          = var.redis_url
    web_cpu_units      = var.web_cpu_units
    web_memory_size    = var.web_memory_size
    web_storage_size   = var.web_storage_size
    persistent_storage = var.persistent_storage_size
    web_replicas       = var.web_replicas
    max_price_uakt     = var.max_price_uakt
    akash_auditor      = var.akash_auditor_address
    web_concurrency    = var.web_concurrency
  })
  filename = "${path.module}/generated-deploy.yaml"

  # Restrict permissions — file contains secrets.
  file_permission = "0600"
}

# =============================================================================
# Akash Deployment via CLI
# =============================================================================
# Akash does not have an official Terraform provider. The recommended approach
# is to use the `akash` CLI wrapped in a null_resource provisioner.
#
# Lifecycle:
#   terraform apply  → akash tx deployment create (new deployment)
#   terraform apply  → akash tx deployment update (if SDL changed)
#   terraform destroy → akash tx deployment close
#
# The deployment ID (DSEQ) is stored in a local file so subsequent runs
# can update or close the existing deployment.

resource "null_resource" "akash_deployment" {
  # Re-run when the SDL content changes.
  # Store connection details in triggers so the destroy provisioner can access them.
  triggers = {
    sdl_hash       = sha256(local_file.akash_sdl.content)
    akash_key_name = var.akash_key_name
    akash_chain_id = var.akash_chain_id
    akash_node     = var.akash_node
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-e", "-o", "pipefail", "-c"]
    command     = <<-EOT
      DSEQ_FILE="${path.module}/akash-dseq.txt"

      if [ -f "$DSEQ_FILE" ]; then
        echo "==> Updating existing Akash deployment (DSEQ=$(cat "$DSEQ_FILE"))..."
        akash tx deployment update "${local_file.akash_sdl.filename}" \
          --dseq "$(cat "$DSEQ_FILE")" \
          --from "${var.akash_key_name}" \
          --chain-id "${var.akash_chain_id}" \
          --node "${var.akash_node}" \
          --fees 5000uakt \
          --gas auto \
          --yes
      else
        echo "==> Creating new Akash deployment..."
        RESULT=$(akash tx deployment create "${local_file.akash_sdl.filename}" \
          --from "${var.akash_key_name}" \
          --chain-id "${var.akash_chain_id}" \
          --node "${var.akash_node}" \
          --fees 5000uakt \
          --gas auto \
          --yes \
          --output json)

        # Extract DSEQ from transaction result.
        DSEQ=$(echo "$RESULT" | jq -r '.logs[0].events[] | select(.type=="akash.v1beta3.EventDeploymentCreated") | .attributes[] | select(.key=="dseq") | .value' 2>/dev/null || true)

        if [ -z "$DSEQ" ]; then
          echo "Warning: Could not extract DSEQ from transaction. Check deployment manually."
          echo "Transaction result: $RESULT"
        else
          echo "$DSEQ" > "$DSEQ_FILE"
          echo "==> Deployment created with DSEQ=$DSEQ"
          echo "==> Waiting for bids from providers..."
          echo "==> Accept a bid with: akash tx market lease create --dseq $DSEQ --from ${var.akash_key_name}"
        fi
      fi
    EOT
  }

  # Close deployment on terraform destroy.
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-e", "-o", "pipefail", "-c"]
    command     = <<-EOT
      DSEQ_FILE="${path.module}/akash-dseq.txt"

      if [ -f "$DSEQ_FILE" ]; then
        echo "==> Closing Akash deployment (DSEQ=$(cat "$DSEQ_FILE"))..."
        akash tx deployment close \
          --dseq "$(cat "$DSEQ_FILE")" \
          --from "${self.triggers.akash_key_name}" \
          --chain-id "${self.triggers.akash_chain_id}" \
          --node "${self.triggers.akash_node}" \
          --fees 5000uakt \
          --yes || true
        rm -f "$DSEQ_FILE"
      fi
    EOT
  }

  depends_on = [local_file.akash_sdl]
}
