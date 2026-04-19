# =============================================================================
# Ingress Anchor — Lightweight Static IP Proxy for IoT Queens
# =============================================================================
#
# With Rails and Sidekiq running on Akash Network (decentralized compute),
# GCP no longer hosts heavy application servers. Instead, this e2-micro instance
# serves as a "Static Anchor" — a fixed IP address that IoT Queen gateways
# (SIM7070G / Starlink) can reach reliably.
#
# The Ingress Anchor runs HAProxy to forward:
#   - UDP 5683 (CoAP telemetry from Queens) → Akash deployment
#   - TCP 80/443 (HTTP/HTTPS web traffic)   → Akash deployment
#
# Cost: ~$5/month (e2-micro with Always Free tier eligibility)
# Purpose: Stable IP for IoT devices that cannot discover dynamic Akash IPs
#
# The AKASH_DEPLOYMENT_IP must be updated when the Akash deployment migrates
# to a new provider. This can be automated via a cron job or webhook.
# =============================================================================

# Static external IP for the Ingress Anchor — this is the IP that Queens target.
# Point DNS (api.silkennet.com) and Queen firmware configuration here.
resource "google_compute_address" "ingress_ip" {
  name   = "silken-net-ingress-ip"
  region = var.region
}

resource "google_compute_instance" "ingress_anchor" {
  name         = "silken-net-ingress"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["web-nodes"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.silken_net_vpc.name
    subnetwork = google_compute_subnetwork.web.name
    access_config { nat_ip = google_compute_address.ingress_ip.address }
  }

  # HAProxy configuration for forwarding traffic to Akash deployment.
  # AKASH_DEPLOYMENT_IP is a placeholder — update after each Akash deployment.
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e

    # Install HAProxy if not present
    if ! command -v haproxy &> /dev/null; then
      apt-get update -qq && apt-get install -y -qq haproxy
    fi

    # Read Akash deployment IP from instance metadata (updatable via gcloud CLI)
    AKASH_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/akash-deployment-ip" \
      -H "Metadata-Flavor: Google" 2>/dev/null || echo "AKASH_IP_NOT_SET")

    # Generate HAProxy configuration
    cat > /etc/haproxy/haproxy.cfg << HAPROXY_CFG
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# ----- TCP 80 (HTTP) → Akash -----
frontend http_in
    bind *:80
    mode tcp
    default_backend akash_http

backend akash_http
    mode tcp
    server akash1 $AKASH_IP:80 check

# ----- TCP 443 (HTTPS) → Akash -----
frontend https_in
    bind *:443
    mode tcp
    default_backend akash_https

backend akash_https
    mode tcp
    server akash1 $AKASH_IP:443 check

# ----- UDP 5683 (CoAP) → Akash -----
# HAProxy does not natively support UDP. For CoAP forwarding, we use
# socat as a lightweight UDP relay alongside HAProxy.
HAPROXY_CFG

    systemctl restart haproxy || true

    # UDP relay for CoAP (port 5683) via socat
    apt-get install -y -qq socat 2>/dev/null || true
    # Kill existing socat relay if running
    pkill -f "socat.*UDP4-LISTEN:5683" 2>/dev/null || true
    # Start UDP relay in background (survives via nohup)
    if [ "$AKASH_IP" != "AKASH_IP_NOT_SET" ]; then
      nohup socat UDP4-LISTEN:5683,reuseaddr,fork UDP4:$AKASH_IP:5683 &
      logger -t ingress-anchor "CoAP UDP relay started: :5683 → $AKASH_IP:5683"
    fi

    logger -t ingress-anchor "HAProxy configured: HTTP/HTTPS/CoAP → $AKASH_IP"
  EOF

  metadata = {
    enable-oslogin       = "TRUE"
    # Update this value after Akash deployment to route traffic:
    #   gcloud compute instances add-metadata silken-net-ingress \
    #     --metadata akash-deployment-ip=<NEW_AKASH_IP> --zone europe-west1-b
    #   gcloud compute instances reset silken-net-ingress --zone europe-west1-b
    akash-deployment-ip = "AKASH_IP_NOT_SET"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.deploy.email
    scopes = ["logging-write", "monitoring-write"]
  }

  allow_stopping_for_update = true

  depends_on = [google_project_service.compute]
}
