variable "project_id" {
  description = "GCP project ID"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for compute instances"
  type        = string
  default     = "europe-west1-b"
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

variable "db_password" {
  description = "Cloud SQL database password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "Database password must be at least 16 characters."
  }
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-7680"
}

variable "db_availability_type" {
  description = "Cloud SQL availability: ZONAL (single zone) or REGIONAL (HA with automatic failover)"
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.db_availability_type)
    error_message = "Must be ZONAL or REGIONAL."
  }
}

variable "db_disk_size_gb" {
  description = "Initial Cloud SQL disk size in GB (autoresize is enabled)"
  type        = number
  default     = 50

  validation {
    condition     = var.db_disk_size_gb >= 20
    error_message = "Disk size must be at least 20 GB."
  }
}

variable "db_max_connections" {
  description = "PostgreSQL max_connections — scale with number of web nodes and workers"
  type        = string
  default     = "200"
}

variable "db_read_replica_count" {
  description = "Number of Cloud SQL read replicas (0 to disable)"
  type        = number
  default     = 0

  validation {
    condition     = var.db_read_replica_count >= 0 && var.db_read_replica_count <= 5
    error_message = "Read replica count must be between 0 and 5."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on Cloud SQL and read replicas"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Redis
# -----------------------------------------------------------------------------

variable "redis_memory_size_gb" {
  description = "Memorystore Redis memory size in GB"
  type        = number
  default     = 1

  validation {
    condition     = var.redis_memory_size_gb >= 1
    error_message = "Redis memory must be at least 1 GB."
  }
}

variable "redis_ha_enabled" {
  description = "Enable STANDARD_HA tier for Redis with automatic failover"
  type        = bool
  default     = true
}

variable "redis_alternative_zone" {
  description = "Alternative zone for Redis HA failover replica"
  type        = string
  default     = "europe-west1-c"
}

# -----------------------------------------------------------------------------
# Compute
# -----------------------------------------------------------------------------

variable "web_machine_type" {
  description = "Machine type for web nodes"
  type        = string
  default     = "n2-standard-2"
}

variable "web_node_count" {
  description = "Number of web server instances"
  type        = number
  default     = 1

  validation {
    condition     = var.web_node_count >= 1 && var.web_node_count <= 100
    error_message = "Node count must be between 1 and 100."
  }
}

variable "web_disk_size_gb" {
  description = "Boot disk size for web nodes in GB"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# SSH & Network Access
# -----------------------------------------------------------------------------

variable "ssh_public_key" {
  description = "SSH public key for accessing compute instances"
  type        = string
  default     = ""
}

variable "ssh_user" {
  description = "SSH username for compute instances"
  type        = string
  default     = "deploy"
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to SSH into web nodes — restrict to VPN/office IP in production"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
