# Cloud SQL PostgreSQL instance
resource "google_sql_database_instance" "silken_db" {
  name             = "silken-db"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = var.db_availability_type
    disk_size         = var.db_disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      # [AKASH CONNECTIVITY]: When Akash nodes are deployed, they run OUTSIDE the
      # GCP VPC and cannot reach a private-only Cloud SQL instance. Enable a public
      # IP so that external clients (Akash providers, Cloud SQL Auth Proxy sidecars)
      # can connect. Access is restricted to specific CIDR ranges via
      # authorized_networks — never open to 0.0.0.0/0.
      ipv4_enabled    = var.akash_enabled
      private_network = google_compute_network.silken_net_vpc.id
      require_ssl     = true

      dynamic "authorized_networks" {
        for_each = var.akash_enabled ? var.akash_authorized_networks : []
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.cidr
        }
      }
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

  lifecycle {
    precondition {
      condition     = !var.akash_enabled || length(var.akash_authorized_networks) > 0
      error_message = "When akash_enabled = true, akash_authorized_networks must contain at least one CIDR range to restrict Cloud SQL public IP access."
    }
  }
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

# Solid Queue database
resource "google_sql_database" "queue" {
  name     = "silken_net_production_queue"
  instance = google_sql_database_instance.silken_db.name
}

# Solid Cable database
resource "google_sql_database" "cable" {
  name     = "silken_net_production_cable"
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
  database_version     = "POSTGRES_16"

  replica_configuration {
    failover_target = false
  }

  settings {
    tier            = var.db_tier
    disk_type       = "PD_SSD"
    disk_autoresize = true

    ip_configuration {
      ipv4_enabled    = var.akash_enabled
      private_network = google_compute_network.silken_net_vpc.id
      require_ssl     = true
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
