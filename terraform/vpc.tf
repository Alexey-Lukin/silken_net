# VPC Network
resource "google_compute_network" "silken_net_vpc" {
  name                    = "silken-net-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

# Subnet for compute instances — /20 gives 4094 usable IPs for future growth.
resource "google_compute_subnetwork" "web" {
  name          = "silken-net-web-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.silken_net_vpc.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router for NAT gateway
resource "google_compute_router" "router" {
  name    = "silken-net-router"
  region  = var.region
  network = google_compute_network.silken_net_vpc.id
}

# Cloud NAT — outbound internet access for private instances
resource "google_compute_router_nat" "nat" {
  name                               = "silken-net-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall: Allow SSH (port 22) — restricted to specified source ranges
resource "google_compute_firewall" "allow_ssh" {
  name        = "silken-net-allow-ssh"
  network     = google_compute_network.silken_net_vpc.name
  description = "Allow SSH access from specified CIDR ranges to web nodes"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["web-nodes"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Firewall: Allow HTTP/HTTPS (ports 80, 443)
resource "google_compute_firewall" "allow_web" {
  name        = "silken-net-allow-web"
  network     = google_compute_network.silken_net_vpc.name
  description = "Allow HTTP/HTTPS traffic from the internet to web nodes"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-nodes"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Firewall: Allow CoAP UDP (port 5683) — IoT uplink from Soldier/Queen nodes
resource "google_compute_firewall" "allow_coap" {
  name        = "silken-net-allow-coap"
  network     = google_compute_network.silken_net_vpc.name
  description = "Allow CoAP UDP traffic from IoT gateways (Queen nodes) to web nodes"

  allow {
    protocol = "udp"
    ports    = ["5683"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-nodes"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Firewall: Allow internal communication — restricted to subnet CIDR
resource "google_compute_firewall" "allow_internal" {
  name        = "silken-net-allow-internal"
  network     = google_compute_network.silken_net_vpc.name
  description = "Allow internal communication between instances within the web subnet"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [google_compute_subnetwork.web.ip_cidr_range]
}

# Firewall: Deny all other ingress (explicit default-deny)
resource "google_compute_firewall" "deny_all_ingress" {
  name        = "silken-net-deny-all-ingress"
  network     = google_compute_network.silken_net_vpc.name
  description = "Default deny all ingress traffic not matched by higher-priority rules"
  priority    = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Reserve static external IPs for web nodes
resource "google_compute_address" "web" {
  count  = var.web_node_count
  name   = "silken-net-web-${count.index}"
  region = var.region
}
