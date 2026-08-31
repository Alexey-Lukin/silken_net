# SPDX-License-Identifier: AGPL-3.0-or-later
variable "project_id" {
  description = "GCP project ID"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, lowercase letters, digits, and hyphens."
  }
}

# ⚠️ NOT a free default — this value is pinned by something terraform does not manage.
# Our Upstash Redis lives OUTSIDE this state (one instance per deploy slot), and its region is
# chosen at CREATION and never again: Upstash offers read-replicas for a live instance but no
# way to move a PRIMARY. `silkennet-canopy` was therefore created in GCP `europe-west1` to be
# same-region with Cloud SQL, and the production instance is to be created there for the same
# reason (it is still pending — Upstash Free allows exactly one instance per account; see
# `00_07` Фаза −1). Changing this variable does not "move the stack": it silently splits it
# across regions and puts a cross-region RTT on every Rack::Attack throttle check (the hot
# path). Nothing goes red — the ceiling is recorded in `config/initializers/rack_attack.rb`.
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
  description = "PostgreSQL max_connections — must exceed sum of all pool sizes across all Puma workers, Sidekiq processes, and the anchor coap daemon"
  type        = string
  default     = "400"
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
# SSH & Network Access
# -----------------------------------------------------------------------------

# INF.20 (в): admin SSH rides the IAP tunnel + OS Login — metadata ssh-keys are NOT
# used (enable-oslogin=TRUE ignores them; the old ssh_public_key/ssh_user vars were
# dead — consumed by nothing). Members here get osAdminLogin (sudo) + IAP tunnel access.
variable "iap_admin_members" {
  description = "IAM members allowed to SSH into the Ingress Anchor via IAP with sudo (e.g. [\"user:founder@example.com\"])"
  type        = list(string)
  default     = []
}

# [INF.21] CoAP-daemon image on the Ingress Anchor. Pin to an immutable tag for any
# real bring-up: mirror-ghcr pushes `sha-<commit>` on every main push and `vX.Y.Z`
# on releases — `:latest` moves under you on VM reboot/restart and has no rollback
# target. The default stays :latest only as a dev convenience.
variable "coap_daemon_image" {
  description = "Container image for the Anchor coap-daemon systemd unit (pin sha-<commit>/vX.Y.Z for deploys)"
  type        = string
  # [INF.21] fail-closed: PIN_ME is NOT a real tag → forgetting to pin fails LOUD (docker pull
  # errors) instead of the systemd unit silently riding mutable :latest across VM reboots.
  default = "ghcr.io/alexey-lukin/silken_net:PIN_ME"
  validation {
    condition     = !endswith(var.coap_daemon_image, ":latest")
    error_message = "Pin an immutable sha-<commit>/vX.Y.Z image, never :latest — mutable tag = no rollback, non-reproducible deploy (INF.21)."
  }
}

# Optional DIRECT ssh (bypassing IAP) — normally stays []: the canonical admin path
# is the IAP tunnel (allow_iap_ssh is unconditional). Fill only for a break-glass
# direct-CIDR window.
variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to SSH into web nodes directly (IAP is the normal path; leave [])"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.ssh_source_ranges) == 0 || !contains(var.ssh_source_ranges, "0.0.0.0/0")
    error_message = "ssh_source_ranges must not include 0.0.0.0/0 (open to the world). Restrict to VPN/office CIDR. Example: [\"203.0.113.0/24\"]"
  }
}

# -----------------------------------------------------------------------------
# FinOps (OPS.11)
# -----------------------------------------------------------------------------

# Empty = billing budget not managed here (count-guard, billing.tf). Once set,
# mirror the value into the GitHub secret GCP_BILLING_ACCOUNT_ID — a CI apply
# without it destroys the budget (count flips back to 0).
variable "billing_account_id" {
  description = "GCP billing account id (XXXXXX-XXXXXX-XXXXXX) for the [OPS.11] budget guard; empty disables"
  type        = string
  default     = ""
}

variable "billing_budget_usd" {
  description = "Monthly budget ceiling in USD — thresholds alert at 50/90/100% + forecasted-100% (operator-tuned; default sized for e2-small + Cloud SQL dev-tier)"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# Workload Identity Federation (INF.22) — keyless CI → GCP
# -----------------------------------------------------------------------------

# GitHub owner/repo whose Actions workflows may impersonate the deploy SA via WIF
# (wif.tf). Case-insensitive: the OIDC claim preserves GitHub's stored mixed case,
# so both the provider condition and the SA binding lowercase it. Change only if the
# repo is renamed/transferred.
variable "github_repository" {
  description = "GitHub owner/repo allowed to impersonate the deploy SA via WIF (case-insensitive)"
  type        = string
  default     = "Alexey-Lukin/silken_net"

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "Must be in owner/repo form (e.g. Alexey-Lukin/silken_net)."
  }
}
