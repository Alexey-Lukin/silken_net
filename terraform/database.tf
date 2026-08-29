# SPDX-License-Identifier: AGPL-3.0-or-later
# Cloud SQL PostgreSQL instance
resource "google_sql_database_instance" "silken_db" {
  name             = "silken-db"
  database_version = "POSTGRES_17"
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = var.db_availability_type
    disk_size         = var.db_disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      # PRIVATE-ONLY [OPS.37]. The public listener existed for exactly one reason:
      # the Auth Proxy uses the Google API only for AUTH (ephemeral certs/IAM) while
      # the socket still dials the instance IP, and a container outside the VPC could
      # reach only the PUBLIC one. Both live clients now sit INSIDE the VPC and use the
      # private IP directly (compute.tf anchor coap.env; config/deploy.yml POSTGRES_HOST),
      # so the listener had no consumer left — and the read replica below has been
      # private-only all along. Re-enabling it needs a NAMED out-of-VPC client, and the
      # .trivyignore suppression was removed in the same commit so AVD-GCP-0017 will say so.
      ipv4_enabled    = false
      private_network = google_compute_network.silken_net_vpc.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 30

      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    database_flags {
      name  = "max_connections"
      value = var.db_max_connections
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    # log_lock_waits/log_temp_files — prod observability (deadlock diagnosis +
    # query-spill tuning); satisfy AVD-GCP-0020/0014, mirror the flags above.
    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    database_flags {
      name  = "log_temp_files"
      value = "0"
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }
  }

  deletion_protection = var.enable_deletion_protection

  depends_on = [
    google_project_service.sqladmin,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Primary application database
resource "google_sql_database" "production" {
  name     = "silken_net_production"
  instance = google_sql_database_instance.silken_db.name
}

# Solid Cache database
resource "google_sql_database" "cache" {
  name     = "silken_net_production_cache"
  instance = google_sql_database_instance.silken_db.name
}

# Solid Cable database
resource "google_sql_database" "cable" {
  name     = "silken_net_production_cable"
  instance = google_sql_database_instance.silken_db.name
}

# ---------------------------------------------------------------------------
# Canopy database set — isolated DB names on the SAME instance (INF.16).
# Canopy shares host/user/password with production (config/deploy.canopy.yml
# overrides only POSTGRES_DATABASE); `db:prepare` expects all three databases
# of the set to exist (primary + cache + cable — Solid Queue pruned, INF.18).
# ---------------------------------------------------------------------------
resource "google_sql_database" "canopy" {
  name     = "silken_net_canopy"
  instance = google_sql_database_instance.silken_db.name
}

resource "google_sql_database" "canopy_cache" {
  name     = "silken_net_canopy_cache"
  instance = google_sql_database_instance.silken_db.name
}

resource "google_sql_database" "canopy_cable" {
  name     = "silken_net_canopy_cable"
  instance = google_sql_database_instance.silken_db.name
}

# Database user
resource "google_sql_user" "silken_net" {
  name     = "silken_net"
  instance = google_sql_database_instance.silken_db.name
  password = var.db_password
}

# Read replica (optional, for horizontal read scaling)
resource "google_sql_database_instance" "read_replica" {
  count                = var.db_read_replica_count
  name                 = "silken-db-replica-${count.index}"
  master_instance_name = google_sql_database_instance.silken_db.name
  region               = var.region
  database_version     = "POSTGRES_17"

  replica_configuration {
    failover_target = false
  }

  settings {
    tier            = var.db_tier
    disk_type       = "PD_SSD"
    disk_autoresize = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.silken_net_vpc.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }
  }

  deletion_protection = var.enable_deletion_protection
}

# Private Service Access for Cloud SQL
resource "google_compute_global_address" "private_ip_range" {
  name          = "silken-net-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.silken_net_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.silken_net_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [google_project_service.servicenetworking]
}
