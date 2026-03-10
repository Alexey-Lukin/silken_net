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
  description = "Full Docker image URL (same image Kamal pushes to Artifact Registry)"
  type        = string
  # Example: europe-west1-docker.pkg.dev/your-project/silken-net/silken_net:latest
}

variable "rails_master_key" {
  description = "Rails encrypted credentials master key"
  type        = string
  sensitive   = true
}

variable "database_url" {
  description = "PostgreSQL connection URL (Cloud SQL with PostGIS). Must be reachable from Akash providers (use public IP + SSL or proxy)"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^postgres(ql)?://", var.database_url))
    error_message = "DATABASE_URL must start with postgres:// or postgresql://"
  }
}

variable "redis_url" {
  description = "Redis connection URL for Sidekiq"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^redis(s)?://", var.redis_url))
    error_message = "REDIS_URL must start with redis:// or rediss://"
  }
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

variable "max_price_uakt" {
  description = "Maximum price per block in uAKT (micro-AKT). Controls deployment cost ceiling"
  type        = number
  default     = 10000

  validation {
    condition     = var.max_price_uakt >= 100
    error_message = "Price must be at least 100 uAKT per block."
  }
}
