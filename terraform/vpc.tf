# VPC Network
resource "google_compute_network" "silken_net_vpc" {
  name                    = "silken-net-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

# Subnet for compute instances
resource "google_compute_subnetwork" "web" {
  name          = "silken-net-web-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.silken_net_vpc.id

  private_ip_google_access = true
}

# Firewall: Allow SSH (port 22)
resource "google_compute_firewall" "allow_ssh" {
  name    = "silken-net-allow-ssh"
  network = google_compute_network.silken_net_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["web-nodes"]
}

# Firewall: Allow HTTP/HTTPS (ports 80, 443)
resource "google_compute_firewall" "allow_web" {
  name    = "silken-net-allow-web"
  network = google_compute_network.silken_net_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-nodes"]
}

# Firewall: Allow CoAP UDP (port 5683)
resource "google_compute_firewall" "allow_coap" {
  name    = "silken-net-allow-coap"
  network = google_compute_network.silken_net_vpc.name

  allow {
    protocol = "udp"
    ports    = ["5683"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-nodes"]
}

# Firewall: Allow internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "silken-net-allow-internal"
  network = google_compute_network.silken_net_vpc.name

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

  source_ranges = ["10.0.0.0/8"]
}

# Reserve static external IPs for web nodes
resource "google_compute_address" "web" {
  count  = var.web_node_count
  name   = "silken-net-web-${count.index}"
  region = var.region
}
