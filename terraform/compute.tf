# Web server instances
resource "google_compute_instance" "web" {
  count        = var.web_node_count
  name         = "silken-net-web-${count.index}"
  machine_type = var.web_machine_type
  zone         = var.zone
  tags         = ["web-nodes"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 30
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
    ssh-keys = var.ssh_public_key != "" ? "${var.ssh_user}:${var.ssh_public_key}" : null
  }

  service_account {
    email  = google_service_account.deploy.email
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true

  depends_on = [google_project_service.compute]
}
