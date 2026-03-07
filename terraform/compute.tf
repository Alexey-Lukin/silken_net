# Web server instances — OS Login + Shielded VM for security best practices
resource "google_compute_instance" "web" {
  count        = var.web_node_count
  name         = "silken-net-web-${count.index}"
  machine_type = var.web_machine_type
  zone         = var.zone
  tags         = ["web-nodes"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = var.web_disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.web.id

    access_config {
      nat_ip = google_compute_address.web[count.index].address
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
    ssh-keys       = var.ssh_public_key != "" ? "${var.ssh_user}:${var.ssh_public_key}" : null
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.deploy.email
    scopes = ["logging-write", "monitoring-write", "storage-ro"]
  }

  allow_stopping_for_update = true

  depends_on = [google_project_service.compute]
}
