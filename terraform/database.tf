# Cloud SQL PostgreSQL instance
resource "google_sql_database_instance" "silken_db" {
  name             = "silken-db"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_size         = 20
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.silken_net_vpc.id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }

    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }
  }

  deletion_protection = true

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
}
