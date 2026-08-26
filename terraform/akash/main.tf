# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# Terraform — Akash Network Deployment for SilkenNet
# =============================================================================
#
# This is a separate Terraform root module that manages the Akash deployment.
# It lives alongside the GCP infrastructure (terraform/) but has its own state
# because the two environments have different lifecycles and credentials:
#
#   terraform/          → GCP infrastructure (Cloud SQL, VPC, Ingress Anchor)
#   terraform/akash/    → Akash decentralized deployment (web + job services)
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
#   - Cloud SQL Auth Proxy configured in Dockerfile (handles external access via HTTPS)
# =============================================================================

terraform {
  # [OPS.21] Дзеркало `terraform/main.tf`: обидва корені валідуються тим самим
  # бінарником, тож і межі в них однакові — `~> 1.15`, рівно доведений діапазон.
  required_version = "~> 1.15"

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
    docker_image                       = var.docker_image
    rails_master_key                   = var.rails_master_key
    db_password                        = var.db_password
    cloud_sql_instance_connection_name = var.cloud_sql_instance_connection_name
    gcp_sa_key_base64                  = var.gcp_sa_key_base64
    redis_url                          = var.redis_url
    # Sentry release tag: empty ⇒ the RELEASE_VERSION line is omitted from the
    # SDL entirely (a present-but-empty value kills Sentry autodetect, [B1]).
    release_version = var.release_version
    # canopy vs production — Grafana external_labels `slot` (config.alloy).
    deployment_slot = var.deployment_slot
    # DB SET selector: pair silken_net_canopy with deployment_slot=canopy.
    # FIRST Akash deploy = canopy render (founder 2026-07-04) — the riskiest
    # path (first-ever Akash) must not debut on production.
    postgres_database  = var.postgres_database
    web_cpu_units      = var.web_cpu_units
    web_memory_size    = var.web_memory_size
    web_storage_size   = var.web_storage_size
    persistent_storage = var.persistent_storage_size
    web_replicas       = var.web_replicas
    max_price_uakt     = var.max_price_uakt
    akash_auditor      = var.akash_auditor_address
    akash_region       = var.akash_region
    web_concurrency    = var.web_concurrency
    rails_max_threads  = var.rails_max_threads
    # 🛑 BOOT-CRITICAL: Rails refuses to boot without this (master_key_strength_check.rb)
    provisioning_master_key = var.provisioning_master_key
    # 🛑 BOOT-CRITICAL: mail_transport_check.rb (password reset + critical-alert email)
    mail_from    = var.mail_from
    smtp_address = var.smtp_address
    # Credentials — not boot-critical themselves (an auth-less relay is legitimate).
    smtp_user_name = var.smtp_user_name
    smtp_password  = var.smtp_password
    # Optional channel [ARCH.60] — empty means OFF, the transport no-ops.
    telegram_bot_token = var.telegram_bot_token
    # 🛑 BOOT-CRITICAL: active_record_encryption_keys_check.rb (hardware_keys + identities)
    active_record_encryption_primary_key         = var.active_record_encryption_primary_key
    active_record_encryption_deterministic_key   = var.active_record_encryption_deterministic_key
    active_record_encryption_key_derivation_salt = var.active_record_encryption_key_derivation_salt
    # Observability
    sentry_dsn = var.sentry_dsn
    # Web3 oracle keys (dual-key split, B-02; Celo dedicated signer — ARCH.50;
    # legacy shared oracle_private_key retired — INF.22)
    oracle_celo_private_key     = var.oracle_celo_private_key
    oracle_minter_private_key   = var.oracle_minter_private_key
    oracle_slasher_private_key  = var.oracle_slasher_private_key
    ethereum_anchor_private_key = var.ethereum_anchor_private_key
    # RPC endpoints (Web3::RpcConnectionPool)
    alchemy_polygon_rpc_url  = var.alchemy_polygon_rpc_url
    alchemy_ethereum_rpc_url = var.alchemy_ethereum_rpc_url
    solana_rpc_url           = var.solana_rpc_url
    celo_rpc_url             = var.celo_rpc_url
    # Solana minting (SolanaMicroRewardWorker)
    solana_wallet_keypair          = var.solana_wallet_keypair
    solana_fee_payer_pubkey        = var.solana_fee_payer_pubkey
    solana_fee_payer_token_account = var.solana_fee_payer_token_account
    solana_usdc_mint_address       = var.solana_usdc_mint_address
    # Webhook HMACs: Chainlink callback (dispatch removed — ARCH.53) + Helium SOS (ARCH.34)
    chainlink_hmac_secret = var.chainlink_hmac_secret
    helium_webhook_secret = var.helium_webhook_secret
    # OBS.1: Grafana Alloy observability sidecar
    grafana_remote_write_url      = var.grafana_remote_write_url
    grafana_remote_write_username = var.grafana_remote_write_username
    grafana_remote_write_token    = var.grafana_remote_write_token
    prometheus_auth_user          = var.prometheus_auth_user
    prometheus_auth_password      = var.prometheus_auth_password
    alloy_config_base64           = filebase64("${path.module}/../../deploy/akash/config.alloy")
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
        # NOTE: Event type is version-specific to Akash API v1beta3.
        # If Akash upgrades the API version, update the event type filter below.
        # Check: akash query tx <txhash> --output json | jq '.logs[0].events[].type'
        DSEQ=$(echo "$RESULT" | jq -r '.logs[0].events[] | select(.type=="akash.v1beta3.EventDeploymentCreated") | .attributes[] | select(.key=="dseq") | .value' 2>/dev/null || true)

        if [ -z "$DSEQ" ]; then
          echo "ERROR: Could not extract DSEQ from transaction result."
          echo "Transaction result: $RESULT"
          echo "Check the deployment manually: akash query deployment list --owner <your-address>"
          exit 1
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
