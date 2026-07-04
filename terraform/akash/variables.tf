# =============================================================================
# Variables — Akash Deployment Configuration
# =============================================================================
# Mirrors the structure of terraform/variables.tf for consistency.
# Values are injected via terraform.tfvars or CI/CD environment variables.

# -----------------------------------------------------------------------------
# Akash Network
# -----------------------------------------------------------------------------

variable "akash_key_name" {
  description = "Akash wallet key name (from `akash keys list`)"
  type        = string
}

variable "akash_chain_id" {
  description = "Akash blockchain chain ID"
  type        = string
  default     = "akashnet-2"
}

variable "akash_node" {
  description = "Akash RPC node URL"
  type        = string
  default     = "https://rpc.akashnet.net:443"
}

variable "akash_auditor_address" {
  description = "Akash auditor address for provider verification (ensures high-uptime providers)"
  type        = string
  default     = "akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24"
}

# -----------------------------------------------------------------------------
# Application — Docker Image & Secrets
# -----------------------------------------------------------------------------

variable "docker_image" {
  description = "Full Docker image URL. Default: GHCR public image (accessible to Akash providers). Override for private registries."
  type        = string
  default     = "ghcr.io/alexey-lukin/silken_net:latest"
  # GHCR image is mirrored automatically by .github/workflows/mirror-ghcr.yml
  # For GCP Artifact Registry (private): europe-west1-docker.pkg.dev/your-project/silken-net/silken_net:latest
}

variable "rails_master_key" {
  description = "Rails encrypted credentials master key"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Cloud SQL PostgreSQL password (component style — config/database.yml). host=127.0.0.1 (Auth Proxy) and user=silken_net are non-secret literals in the SDL; only the password is injected as a secret. Mirror of terraform/variables.tf db_password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "db_password must be at least 16 characters."
  }
}

variable "cloud_sql_instance_connection_name" {
  description = "Cloud SQL instance connection name for Auth Proxy (format: project:region:instance). From `terraform output database_connection_name`"
  type        = string
}

variable "gcp_sa_key_base64" {
  description = "Base64-encoded GCP Service Account JSON key for Cloud SQL Auth Proxy. Generate: cat gcp-sa-key.json | base64 -w0"
  type        = string
  sensitive   = true
}

variable "redis_url" {
  description = "Redis connection URL for Sidekiq (DB 0). Use Upstash with TLS: rediss://default:password@endpoint.upstash.io:6379"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^redis(s)?://", var.redis_url))
    error_message = "REDIS_URL must start with redis:// or rediss://"
  }
}

# kredis_redis_url variable removed [B1] — Kredis auto-derives DB 1 from REDIS_URL in
# config/redis/shared.yml, so the SDL no longer injects KREDIS_REDIS_URL (a non-empty
# inject would override the Rails-side derive). Re-add only to point at a separate instance.

# -----------------------------------------------------------------------------
# 🛑 BOOT-CRITICAL Secrets — Rails refuses to boot in production without these
# -----------------------------------------------------------------------------
# These secrets are checked by Rails initializers at `after_initialize` time.
# Missing values cause Puma to crash before the accept loop — Akash provider
# will restart the container in a hot loop, never accepting requests.

variable "provisioning_master_key" {
  description = "HKDF root key for hardware provisioning (HardwareKeyService, OtaHmacKeyService). Generate: ruby -e \"require 'securerandom'; puts SecureRandom.hex(32)\". Without this, config/initializers/master_key_strength_check.rb raises SecurityError at boot."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.provisioning_master_key) >= 32
    error_message = "PROVISIONING_MASTER_KEY must be at least 32 chars (recommend 64 hex chars = 256-bit entropy)."
  }
}

# -----------------------------------------------------------------------------
# Observability — Sentry
# -----------------------------------------------------------------------------

variable "sentry_dsn" {
  description = "Sentry DSN for production error tracking (config/initializers/sentry.rb). Without it Sentry is inert — silent failures in production."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Web3 Oracle Keys (dual-key split — B-02 resolved)
# -----------------------------------------------------------------------------
# Plaintext on Akash providers — rotate every 90 days. Prefer minimal on-chain
# roles (MINTER_ROLE only, never DEFAULT_ADMIN_ROLE) for the per-Akash-deployment
# keys. See docs/06_02 § "Akash ENV plaintext exposure".

variable "oracle_private_key" {
  description = "Legacy fallback Web3 oracle key (Celo/Etherisc/Toucan/Klima/PuroEarth services). Hex-encoded, with 0x prefix. Used as fallback by BlockchainMintingService and BlockchainBurningService if dedicated keys absent."
  type        = string
  sensitive   = true
}

variable "oracle_minter_private_key" {
  description = "Web3 minter key — holds MINTER_ROLE on SCC & SFC contracts (BlockchainMintingService:107). Hex-encoded, with 0x prefix."
  type        = string
  sensitive   = true
}

variable "oracle_slasher_private_key" {
  description = "Web3 slasher key — holds SLASHER_ROLE on SCC & SFC contracts (BlockchainBurningService:58). Hex-encoded, with 0x prefix."
  type        = string
  sensitive   = true
}

variable "ethereum_anchor_private_key" {
  description = "Dedicated Ethereum L1 wallet for weekly state-root anchor (Ethereum::StateAnchorService:147). MUST differ from oracle_private_key. Hex-encoded, with 0x prefix."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# RPC Endpoints (Web3::RpcConnectionPool requires these via ENV.fetch)
# -----------------------------------------------------------------------------

variable "alchemy_polygon_rpc_url" {
  description = "Alchemy Polygon RPC URL for SCC/SFC minting, burning, Chainlink Functions dispatch, treasury monitoring, Toucan/Klima/PuroEarth bridges. Without it Web3::RpcConnectionPool.client_for raises KeyError."
  type        = string
  sensitive   = true
}

variable "alchemy_ethereum_rpc_url" {
  description = "Alchemy Ethereum L1 RPC URL for weekly state-root anchoring (Ethereum::StateAnchorService:146)."
  type        = string
  sensitive   = true
}

variable "solana_rpc_url" {
  description = "Solana RPC URL for micro-reward minting (Solana::MintingService:112). Defaults to DEVNET_RPC_URL in code if blank — set explicitly in prod."
  type        = string
  sensitive   = true
}

variable "polygon_rpc_url" {
  description = "Polygon RPC for PriceOracleService (Web3::RpcConnectionPool.client_for(\"POLYGON_RPC_URL\"), ENV.fetch without fallback → KeyError if absent). May equal alchemy_polygon_rpc_url or a public endpoint (https://polygon-rpc.com)."
  type        = string
  sensitive   = true
}

variable "celo_rpc_url" {
  description = "Celo RPC for CommunityRewardService. Code falls back to Alfajores TESTNET (DEFAULT_RPC_URL) if blank — set a mainnet endpoint (Forno/Alchemy) in prod to avoid paying real cUSD on testnet (E.49)."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Solana Minting (Solana::MintingService raises explicit errors)
# -----------------------------------------------------------------------------

variable "solana_wallet_keypair" {
  description = "Solana wallet keypair (hex-encoded 64-byte private key) for fee-payer signing (Solana::MintingService:116)."
  type        = string
  sensitive   = true
}

variable "solana_fee_payer_pubkey" {
  description = "Solana fee-payer public key (base58). Solana::MintingService:119 raises if absent."
  type        = string
  sensitive   = true
}

variable "solana_fee_payer_token_account" {
  description = "Solana fee-payer USDC SPL token account (ATA, base58). Solana::MintingService:125 raises if absent."
  type        = string
  sensitive   = true
}

variable "solana_usdc_mint_address" {
  description = "Solana USDC mint address (base58, e.g. EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v for mainnet). Solana::MintingService:127 raises if absent."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Chainlink oracle-callback HMAC (on-chain dispatch removed — ARCH.53)
# -----------------------------------------------------------------------------

variable "chainlink_hmac_secret" {
  description = "HMAC-SHA256 secret for verifying X-Chainlink-Signature header in /api/v1/oracle_callbacks (replay protection)."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Compute Resources — maps to Akash SDL profiles.compute
# -----------------------------------------------------------------------------

variable "web_cpu_units" {
  description = "CPU units for the web service (1 unit = 1 vCPU). Higher than GCP to compensate for variable provider performance"
  type        = number
  default     = 4

  validation {
    condition     = var.web_cpu_units >= 1 && var.web_cpu_units <= 32
    error_message = "CPU units must be between 1 and 32."
  }
}

variable "web_memory_size" {
  description = "Memory allocation for the web service (e.g., 8Gi)"
  type        = string
  default     = "8Gi"
}

variable "web_storage_size" {
  description = "Ephemeral storage for the web service (e.g., 50Gi)"
  type        = string
  default     = "50Gi"
}

variable "persistent_storage_size" {
  description = "Persistent storage for Active Storage uploads and logs (e.g., 10Gi)"
  type        = string
  default     = "10Gi"
}

# -----------------------------------------------------------------------------
# Scaling & Pricing
# -----------------------------------------------------------------------------

variable "web_replicas" {
  description = "Number of web service replicas (maps to deployment.web.count). Like Terraform web_node_count"
  type        = number
  default     = 1

  validation {
    condition     = var.web_replicas >= 1 && var.web_replicas <= 10
    error_message = "Replica count must be between 1 and 10."
  }
}

variable "web_concurrency" {
  description = "Puma WEB_CONCURRENCY — number of worker processes (set to match CPU units)"
  type        = number
  default     = 4
}

variable "rails_max_threads" {
  description = "Puma RAILS_MAX_THREADS — threads per worker process (keep low 3-5 to limit GVL contention)"
  type        = number
  default     = 3

  validation {
    condition     = var.rails_max_threads >= 1 && var.rails_max_threads <= 8
    error_message = "RAILS_MAX_THREADS must be between 1 and 8 to avoid GVL thrashing."
  }
}

variable "max_price_uakt" {
  description = "Maximum price per block in uAKT (micro-AKT). Controls deployment cost ceiling"
  type        = number
  default     = 10000

  validation {
    condition     = var.max_price_uakt >= 100
    error_message = "Price must be at least 100 uAKT per block."
  }
}

# -----------------------------------------------------------------------------
# Observability — Grafana Cloud (OBS.1)
# -----------------------------------------------------------------------------
# Grafana Alloy runs as a sidecar in the Akash deployment, scraping the Rails
# /metrics endpoint and pushing metrics to Grafana Cloud via remote_write.
# Resolves 06_03 BLOCKERs 1-3 (Prometheus Server, Grafana, Alertmanager).

variable "grafana_remote_write_url" {
  description = "Grafana Cloud Prometheus remote_write endpoint URL (e.g., https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push)"
  type        = string
}

variable "grafana_remote_write_username" {
  description = "Grafana Cloud instance ID (numeric) for remote_write authentication"
  type        = string
}

variable "grafana_remote_write_token" {
  description = "Grafana Cloud API token with metrics:write scope for remote_write authentication"
  type        = string
  sensitive   = true
}

variable "prometheus_auth_user" {
  description = "HTTP Basic Auth username for Rails /metrics endpoint (must match PROMETHEUS_AUTH_USER env var in web service)"
  type        = string
}

variable "prometheus_auth_password" {
  description = "HTTP Basic Auth password for Rails /metrics endpoint (must match PROMETHEUS_AUTH_PASSWORD env var in web service)"
  type        = string
  sensitive   = true
}
