terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "silken-net-terraform-state"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required GCP APIs
resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sqladmin" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "redis" {
  service            = "redis.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# Artifact Registry for Docker images
resource "google_artifact_registry_repository" "silken_net" {
  location      = var.region
  repository_id = "silken-net"
  format        = "DOCKER"
  description   = "Docker images for Silken Net application"

  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "keep-latest-10"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
  cleanup_policies {
    id     = "delete-old-images"
    action = "DELETE"
    condition {
      older_than = "2592000s"
    }
  }

  depends_on = [google_project_service.artifactregistry]
}

# ============================================================================
# Logging Cost Control (The Bill Shield)
# ============================================================================
# GCP Cloud Logging charges per ingested GB. Millions of INFO-level logs from
# telemetry processing, health checks, and background jobs can cost more than
# the entire infrastructure. Exclude INFO and DEBUG logs from ingestion —
# only WARNING, ERROR, and CRITICAL reach Cloud Logging.

resource "google_logging_project_exclusion" "exclude_info_logs" {
  name        = "silken-net-exclude-info-debug"
  description = "Exclude INFO and DEBUG logs to reduce Cloud Logging costs. Only WARNING+ are ingested."
  filter      = "severity = DEFAULT OR severity = DEBUG OR severity = INFO"
}
