# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# Ingress Anchor — Static IP entry + PRIMARY CoAP intake host (INF.17)
# =============================================================================
#
# With Rails and Sidekiq running on Akash Network (decentralized compute),
# GCP hosts no heavy application servers. This e2-small instance is the fixed
# IP that IoT Queen gateways (SIM7070G / Starlink) reach, and — since the
# founder decision of 2026-07-04 — it RUNS the CoAP intake daemon itself:
#
#   - UDP 5683: CoAP daemon (docker, lib/daemons/coap_listener) — PRIMARY.
#       Same VPC as Cloud SQL → private IP, no Auth Proxy; Upstash over TLS.
#       Removes one hop + the socat/Akash-IP chase from the hot path.
#       FALLBACK = socat relay → Akash `coap` service (kept deployed, idle);
#       switch: systemctl stop coap-daemon && systemctl start coap-relay.
#   - TCP 80/443: HAProxy → Akash deployment (web stays decentralized —
#       money-path/web remain on Akash by design). ⚠️ Підстава «censorship-resistance»
#       знята 2026-08-29 як клас СЛОВО (мітка без вимірювача) — 06_02 §5, ARCH.114.
#
# Cost: ~$13/month e2-small in europe-west1 (Always Free e2-micro is US-only;
# micro's 1 GB cannot hold the Rails daemon ~0.5 GB + HAProxy + OS headroom)
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
  name = "silken-net-ingress"
  # e2-small (2 GB): the CoAP daemon is a full Rails boot (~0.5 GB RSS) next
  # to HAProxy + OS — e2-micro's 1 GB has no headroom (INF.17 anchor-primary).
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["web-nodes"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      # 20 GB: docker + the ghcr Rails image (~2 GB unpacked) + logs.
      size = 20
      type = "pd-standard"
    }
    # CMEK for the boot disk (holds /etc/silkennet/coap.env secrets). This is
    # ForceNew — adding it to a LIVE instance replaces the VM; done here
    # pre-first-deploy the disk is simply created encrypted (zero replacement).
    # Accepts the key .id (provider diff-suppresses relative-path vs self_link).
    kms_key_self_link = google_kms_crypto_key.anchor_boot.id
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

    # Same sentinel guard as the socat unit below: with the placeholder IP
    # HAProxy cannot parse the backend address and would fail to start —
    # a swallowed `|| true` here once hid that as a green startup-script.
    if [ "$AKASH_IP" != "AKASH_IP_NOT_SET" ]; then
      systemctl restart haproxy
    else
      logger -t ingress-anchor "HAProxy NOT started: akash-deployment-ip metadata is unset (AKASH_IP_NOT_SET)"
    fi

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

    # (enable/start of coap-relay moved to the bring-up priority block below —
    # the unit stays created so the FALLBACK activates by a single systemctl.)

    # =========================================================================
    # 6. CoAP daemon on the Anchor — PRIMARY intake path (INF.17, 2026-07-04)
    # =========================================================================
    # The daemon runs HERE: same VPC as Cloud SQL (private IP, NO Auth Proxy),
    # Upstash over public TLS. The Akash `coap` service stays deployed as the
    # documented FALLBACK behind the socat relay above.
    # Secrets NEVER live in this startup script (instance metadata is world-
    # readable to the project): /etc/silkennet/coap.env is created once as a
    # 0600 placeholder — the operator fills real values; until then the daemon
    # does not start and the script falls back to socat (if AKASH_IP is set).

    if ! command -v docker &> /dev/null; then
      apt-get update -qq && apt-get install -y -qq docker.io
    fi

    mkdir -p /etc/silkennet
    if [ ! -f /etc/silkennet/coap.env ]; then
      cat > /etc/silkennet/coap.env << 'COAP_ENV'
RAILS_ENV=production
# Cloud SQL over the VPC private IP — no Auth Proxy on the Anchor.
POSTGRES_HOST=${google_sql_database_instance.silken_db.private_ip_address}
POSTGRES_USER=silken_net
POSTGRES_PASSWORD=REQUIRED_SECRET_NOT_SET
POSTGRES_DATABASE=silken_net_production
# Upstash Redis (TLS) — Sidekiq enqueue target (UnpackTelemetryWorker).
REDIS_URL=REQUIRED_SECRET_NOT_SET
RAILS_MASTER_KEY=REQUIRED_SECRET_NOT_SET
# No PROVISIONING_MASTER_KEY — coap_listener is pure UDP glue (enqueue only); key
# derivation lives in the workers, master_key_strength_check skips this process, so
# provisioning the fleet-wide-forge crown-jewel here would expose it for nothing (SEC.22). Do not re-add.
# 🛑 BOOT-CRITICAL: active_record_encryption_keys_check.rb is production-wide (NOT
# coap-skipped — these are narrow column keys, not the vault key) → the daemon raises
# without them. A <32-char placeholder also fails the guard closed; fill real values (SEC.22).
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=REQUIRED_SECRET_NOT_SET
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=REQUIRED_SECRET_NOT_SET
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=REQUIRED_SECRET_NOT_SET
SENTRY_DSN=REQUIRED_SECRET_NOT_SET
WEB3_STRICT_MODE=true
COAP_ENV
      chmod 600 /etc/silkennet/coap.env
    fi

    cat > /etc/systemd/system/coap-daemon.service << 'SYSTEMD_DAEMON'
[Unit]
Description=SilkenNet CoAP intake daemon (primary path — INF.17)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/docker rm -f silkennet-coap
# The image already declares ENTRYPOINT /rails/bin/docker-entrypoint (Dockerfile) —
# repeating it as the first CMD arg made the entrypoint re-exec itself (double
# schema_migrations wait, tripled cold start). Pass only the daemon command.
# Image comes from var.coap_daemon_image (INF.21) — pin sha-/semver for deploys.
ExecStart=/usr/bin/docker run --name silkennet-coap --network host \
  --env-file /etc/silkennet/coap.env \
  ${var.coap_daemon_image} \
  bundle exec ruby lib/daemons/coap_listener
ExecStop=/usr/bin/docker stop silkennet-coap
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD_DAEMON

    systemctl daemon-reload

    # ------------------------------------------------------------------------
    # Bring-up priority: daemon (env filled) > socat fallback (AKASH_IP set)
    # > loud warn. Both units always exist; exactly one binds UDP 5683.
    # ------------------------------------------------------------------------
    if ! grep -q REQUIRED_SECRET_NOT_SET /etc/silkennet/coap.env; then
      docker pull ${var.coap_daemon_image} || true
      systemctl disable coap-relay 2>/dev/null || true
      systemctl stop coap-relay 2>/dev/null || true
      systemctl enable coap-daemon
      systemctl restart coap-daemon
      logger -t ingress-anchor "CoAP daemon (PRIMARY) started on :5683; socat fallback disabled"
    elif [ "$AKASH_IP" != "AKASH_IP_NOT_SET" ]; then
      systemctl enable coap-relay
      systemctl restart coap-relay
      logger -t ingress-anchor "CoAP socat FALLBACK started: :5683 → $AKASH_IP:5683 (coap.env not filled)"
    else
      logger -t ingress-anchor "CoAP intake NOT started: coap.env has placeholders AND akash-deployment-ip unset"
    fi

    logger -t ingress-anchor "Anchor configured: HTTP/HTTPS → $AKASH_IP; CoAP per bring-up priority above"
  EOF

  metadata = {
    enable-oslogin = "TRUE"
    # OS Login already ignores project-wide SSH keys; block them explicitly too
    # (defense-in-depth, satisfies AVD-GCP-0030 — no metadata-key SSH path at all).
    block-project-ssh-keys = "TRUE"
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

  # akash-deployment-ip is operator-mutated out-of-band on every Akash re-deploy
  # (see the add-metadata command above), so the live value ≠ the committed
  # "AKASH_IP_NOT_SET" the moment the Anchor routes traffic. Without this,
  # `terraform plan -detailed-exitcode` (Ops · TF Drift) would report permanent
  # drift on this one field forever → red every run → alert fatigue that trains
  # the owner to ignore a REAL future drift. Ignore just this key so drift stays
  # a real signal; the live value is read by the startup script above (S1.5).
  lifecycle {
    ignore_changes = [metadata["akash-deployment-ip"]]
  }

  depends_on = [
    google_project_service.compute,
    # The compute service agent must hold cryptoKeyEncrypterDecrypter on the
    # boot-disk KMS key BEFORE the encrypted disk is created, else
    # instances.insert fails with a KMS permission error. The VM references the
    # KEY, not the binding — no implicit ordering exists, so make it explicit.
    google_kms_crypto_key_iam_member.anchor_boot_agent,
  ]
}
