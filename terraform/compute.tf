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

  # HAProxy + socat configuration for forwarding traffic to Akash deployment.
  # AKASH_DEPLOYMENT_IP is read from instance metadata — update after each
  # Akash deployment via:
  #   gcloud compute instances add-metadata silken-net-ingress \
  #     --metadata akash-deployment-ip=<NEW_IP> --zone europe-west1-b
  #   gcloud compute instances reset silken-net-ingress --zone europe-west1-b
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e

    # =========================================================================
    # 1. Kernel tuning for planetary-scale CoAP/UDP (conntrack + rate limiting)
    # =========================================================================
    # At planetary scale (millions of Queens), UDP conntrack entries accumulate
    # and can overflow the default 65K table. We raise the limit to 2M and
    # shorten UDP timeout to 30s (from default 180s).
    # See: docs/06_01 Risk-1 (Conntrack Table Overflow)

    sysctl -w net.netfilter.nf_conntrack_max=2000000
    sysctl -w net.netfilter.nf_conntrack_udp_timeout=30
    grep -q "nf_conntrack_max" /etc/sysctl.conf || \
      echo "net.netfilter.nf_conntrack_max=2000000" >> /etc/sysctl.conf
    grep -q "nf_conntrack_udp_timeout" /etc/sysctl.conf || \
      echo "net.netfilter.nf_conntrack_udp_timeout=30" >> /etc/sysctl.conf

    # CoAP UDP rate limiting — 100 packets/sec per source IP, burst 200.
    # Protects against UDP DDoS amplification while allowing legitimate Queens.
    # See: docs/06_01 Risk-2 (UDP Rate Limiting)
    apt-get install -y -qq iptables-persistent 2>/dev/null || true

    iptables -C INPUT -p udp --dport 5683 -m hashlimit --hashlimit-name coap \
      --hashlimit-upto 100/sec --hashlimit-burst 200 --hashlimit-mode srcip \
      -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 5683 -m hashlimit --hashlimit-name coap \
      --hashlimit-upto 100/sec --hashlimit-burst 200 --hashlimit-mode srcip \
      -j ACCEPT

    iptables -C INPUT -p udp --dport 5683 -m limit --limit 10/min \
      -j LOG --log-prefix "CoAP-RATELIMIT-DROP: " 2>/dev/null || \
    iptables -A INPUT -p udp --dport 5683 -m limit --limit 10/min \
      -j LOG --log-prefix "CoAP-RATELIMIT-DROP: "

    iptables -C INPUT -p udp --dport 5683 -j DROP 2>/dev/null || \
    iptables -A INPUT -p udp --dport 5683 -j DROP

    netfilter-persistent save 2>/dev/null || true

    # =========================================================================
    # 2. Install HAProxy + socat
    # =========================================================================
    if ! command -v haproxy &> /dev/null || ! command -v socat &> /dev/null; then
      apt-get update -qq && apt-get install -y -qq haproxy socat
    fi

    # =========================================================================
    # 3. Read Akash deployment IP from instance metadata
    # =========================================================================
    AKASH_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/akash-deployment-ip" \
      -H "Metadata-Flavor: Google" 2>/dev/null || echo "AKASH_IP_NOT_SET")

    # =========================================================================
    # 4. Generate HAProxy configuration (TCP 80/443 → Akash)
    # =========================================================================
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
HAPROXY_CFG

    systemctl restart haproxy || true

    # =========================================================================
    # 5. UDP relay for CoAP (port 5683) via socat
    # =========================================================================
    # HAProxy does not natively support UDP. socat provides a lightweight
    # UDP4 relay. We use a systemd service for reliability instead of nohup.
    # The unit file is always created so that updating AKASH_IP via metadata
    # and resetting the instance immediately activates the relay.

    cat > /etc/systemd/system/coap-relay.service << SYSTEMD_UNIT
[Unit]
Description=CoAP UDP relay to Akash deployment
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat UDP4-LISTEN:5683,reuseaddr,fork UDP4:$AKASH_IP:5683
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD_UNIT

    if [ "$AKASH_IP" != "AKASH_IP_NOT_SET" ]; then
      systemctl daemon-reload
      systemctl enable coap-relay
      systemctl restart coap-relay
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
