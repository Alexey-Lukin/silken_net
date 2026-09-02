# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# Ingress Anchor — Static IP entry + PRIMARY CoAP intake host (INF.17)
# =============================================================================
#
# This e2-small instance is the fixed IP that IoT Queen gateways (SIM7070G /
# Starlink) reach — firmware freezes COAP_SERVER_HOST at flash time, so this
# address must never move — and, since the founder decision of 2026-07-04, it
# RUNS the CoAP intake daemon itself:
#
#   - UDP 5683: CoAP daemon (docker, lib/daemons/coap_listener) — PRIMARY.
#       Same VPC as Cloud SQL → private IP, no Auth Proxy; Upstash over TLS.
#       Removes one hop from the hot path.
#       FALLBACK = socat relay → the dormant Kamal `coap` role on the app host;
#       switch: systemctl stop coap-daemon && systemctl start coap-relay.
#   - TCP 80/443: HAProxy → the Rails app host (Kamal). [OPS.37] That host is
#       `google_compute_instance.app` at the bottom of THIS file since 2026-08-30.
#       Until the first `terraform apply` + step 10 of the runbook sets
#       `app-host-ip`, the metadata stays the sentinel and HAProxy deliberately
#       does NOT start (see the guard below); the anchor's CoAP half is
#       independent of it and comes up on its own.
#
# Cost: ~$13/month e2-small in europe-west1 (Always Free e2-micro is US-only;
# micro's 1 GB cannot hold the Rails daemon ~0.5 GB + HAProxy + OS headroom)
# Purpose: one address the field never has to re-learn.
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
  # TERMINATED = зупинено: vCPU/RAM не тарифікуються, диск лишається (variables.tf)
  desired_status = var.compute_desired_status
  tags           = ["web-nodes"]

  # 🔴 API-РІВНЕВИЙ захист від видалення, і на `google_compute_instance` цей аргумент
  # мапиться ПРЯМО в поле GCP — тобто спиняє і `gcloud compute instances delete`, і
  # консоль, і `terraform destroy`. Виміряно 2026-08-31: обидві VM стояли на дефолтному
  # `false`, тобто анкер — єдина зовнішня адреса й дім `coap.env` — знімався однією
  # командою. ⚠️ Із Фазою ∅ не конфліктує: та ЗУПИНЯЄ (`desired_status = TERMINATED`),
  # а не видаляє. Вимикати — лише через `enable_deletion_protection = false`, свідомо.
  deletion_protection = var.enable_deletion_protection

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

  # ⚠️ The startup script below is `set -e` and SERIAL: a script that never reached line N
  #    says NOTHING about N+1. Its three 2026-09-02 fixes (modprobe · DEBIAN_FRONTEND ·
  #    dpkg repair) were three LINKS found one per boot, not three oversights — after any
  #    fix, measure to the END of the script, never to the first green line.
  # HAProxy + socat forward traffic to the Rails app host. Its IP is read from
  # instance metadata (operator-set, out-of-band) — after provisioning the host:
  #   gcloud compute instances add-metadata silken-net-ingress \
  #     --metadata app-host-ip=<APP_HOST_IP> --zone europe-west1-d
  #   gcloud compute instances reset silken-net-ingress --zone europe-west1-d
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e
    # 🔴 Every apt-get below runs with NO terminal: without this, the first package that asks
    # a debconf question (iptables-persistent: "Save current IPv4 rules?") opens a whiptail
    # dialog on a non-existent tty and the script hangs there FOREVER — measured on the live
    # anchor 2026-09-02 (pid tree: apt-get → dpkg --configure → iptables-persistent.config →
    # whiptail, startup unit `activating` for 10+ minutes, HAProxy never reached). The
    # `|| true` on that line cannot help: nothing exits. Non-interactive takes the defaults.
    export DEBIAN_FRONTEND=noninteractive
    # A VM reset in the middle of a package configure (a normal cloud event — and exactly how
    # the 2026-09-02 whiptail hang above was cleared) leaves dpkg "interrupted", after which
    # EVERY apt-get refuses with exit 100 (`E: dpkg was interrupted, you must manually run
    # 'dpkg --configure -a'`) and `set -e` kills the script on its first unguarded install.
    # Measured on the anchor's third boot that day. Repair first, always; harmless when clean.
    dpkg --configure -a || true

    # =========================================================================
    # 1. Kernel tuning for planetary-scale CoAP/UDP (conntrack + rate limiting)
    # =========================================================================
    # At planetary scale (millions of Queens), UDP conntrack entries accumulate
    # and can overflow the default 65K table. We raise the limit to 2M and
    # shorten UDP timeout to 30s (from default 180s).
    # See: docs/06_01 Risk-1 (Conntrack Table Overflow)

    # 🔴 nf_conntrack is a MODULE, and on a fresh boot nothing has loaded it yet (the first
    # conntrack iptables rule below is what would) — so the sysctl key does not exist, the
    # write exits 1, and under `set -e` the whole script dies right here. Measured on the
    # live anchor 2026-08-31 16:44: `sysctl: cannot stat /proc/sys/net/netfilter/
    # nf_conntrack_max`, exit status 1, HAProxy never installed, Cloudflare answered 521
    # for two days behind a GREEN startup-script unit. Load it first and persist the load
    # so the /etc/sysctl.conf lines below apply on every reboot, not only on this run.
    modprobe nf_conntrack
    echo "nf_conntrack" > /etc/modules-load.d/nf_conntrack.conf
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
    # 3. Read the app-host IP from instance metadata
    # =========================================================================
    APP_HOST_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/app-host-ip" \
      -H "Metadata-Flavor: Google" 2>/dev/null || echo "APP_HOST_IP_NOT_SET")

    # =========================================================================
    # 4. Generate HAProxy configuration (TCP 80/443 → app host)
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

# ----- TCP 80 (HTTP) → app host -----
frontend http_in
    bind *:80
    mode tcp
    default_backend app_http

backend app_http
    mode tcp
    server app1 $APP_HOST_IP:80 check

# ----- TCP 443 (HTTPS) → app host -----
frontend https_in
    bind *:443
    mode tcp
    default_backend app_https

backend app_https
    mode tcp
    server app1 $APP_HOST_IP:443 check
HAPROXY_CFG

    # Same sentinel guard as the socat unit below: with the placeholder IP
    # HAProxy cannot parse the backend address and would fail to start —
    # a swallowed `|| true` here once hid that as a green startup-script.
    if [ "$APP_HOST_IP" != "APP_HOST_IP_NOT_SET" ]; then
      systemctl restart haproxy
    else
      logger -t ingress-anchor "HAProxy NOT started: app-host-ip metadata is unset (APP_HOST_IP_NOT_SET)"
    fi

    # =========================================================================
    # 5. UDP relay for CoAP (port 5683) via socat
    # =========================================================================
    # HAProxy does not natively support UDP. socat provides a lightweight
    # UDP4 relay. We use a systemd service for reliability instead of nohup.
    # The unit file is always created so that updating APP_HOST_IP via metadata
    # and resetting the instance immediately activates the relay.

    cat > /etc/systemd/system/coap-relay.service << SYSTEMD_UNIT
[Unit]
Description=CoAP UDP relay to the app host
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat UDP4-LISTEN:5683,reuseaddr,fork UDP4:$APP_HOST_IP:5683
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
    # Upstash over public TLS. The dormant Kamal `coap` role is the documented
    # FALLBACK behind the socat relay above.
    # Secrets NEVER live in this startup script (instance metadata is world-
    # readable to the project): /etc/silkennet/coap.env is created once as a
    # 0600 placeholder — the operator fills real values; until then the daemon
    # does not start and the script falls back to socat (if app-host-ip is set).

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
    # Bring-up priority: daemon (env filled) > socat fallback (APP_HOST_IP set)
    # > loud warn. Both units always exist; exactly one binds UDP 5683.
    # ------------------------------------------------------------------------
    if ! grep -q REQUIRED_SECRET_NOT_SET /etc/silkennet/coap.env; then
      docker pull ${var.coap_daemon_image} || true
      # `|| true` above is right — a transient registry failure must not kill the
      # boot when the image is already cached. But then the question that decides
      # the log line is PRESENCE, not whether the pull succeeded, and until
      # 2026-08-31 the script measured neither: a bad tag (the var defaults to the
      # fail-closed `:PIN_ME` sentinel, and Фаза 0 is where an operator pins it)
      # made the unit crash-loop under `Restart=always` while the anchor logged
      # "CoAP daemon (PRIMARY) started on :5683". The pull is the one step here
      # that fails silently, and its failure wore the success message.
      if docker image inspect ${var.coap_daemon_image} > /dev/null 2>&1; then
        systemctl disable coap-relay 2>/dev/null || true
        systemctl stop coap-relay 2>/dev/null || true
        systemctl enable coap-daemon
        systemctl restart coap-daemon
        logger -t ingress-anchor "CoAP daemon (PRIMARY) started on :5683; socat fallback disabled"
      else
        logger -t ingress-anchor "CoAP daemon NOT started: image ${var.coap_daemon_image} ABSENT after pull (unpinned tag, or registry refused) — coap.env is filled, so this is the image, not the secrets; relay state left untouched"
      fi
    elif [ "$APP_HOST_IP" != "APP_HOST_IP_NOT_SET" ]; then
      systemctl enable coap-relay
      systemctl restart coap-relay
      logger -t ingress-anchor "CoAP socat FALLBACK started: :5683 → $APP_HOST_IP:5683 (coap.env not filled)"
    else
      logger -t ingress-anchor "CoAP intake NOT started: coap.env has placeholders AND app-host-ip unset"
    fi

    logger -t ingress-anchor "Anchor configured: HTTP/HTTPS → $APP_HOST_IP; CoAP per bring-up priority above"
  EOF

  metadata = {
    enable-oslogin = "TRUE"
    # OS Login already ignores project-wide SSH keys; block them explicitly too
    # (defense-in-depth, satisfies AVD-GCP-0030 — no metadata-key SSH path at all).
    block-project-ssh-keys = "TRUE"
    # Set this once the app host exists, to route HTTP/HTTPS through the anchor:
    #   gcloud compute instances add-metadata silken-net-ingress \
    #     --metadata app-host-ip=<APP_HOST_IP> --zone europe-west1-d
    #   gcloud compute instances reset silken-net-ingress --zone europe-west1-d
    app-host-ip = "APP_HOST_IP_NOT_SET"
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

  # app-host-ip is operator-mutated out-of-band (see the add-metadata command
  # above), so the live value ≠ the committed "APP_HOST_IP_NOT_SET" the moment
  # the Anchor routes traffic. Without this,
  # `terraform plan -detailed-exitcode` (Ops · TF Drift) would report permanent
  # drift on this one field forever → red every run → alert fatigue that trains
  # the owner to ignore a REAL future drift. Ignore just this key so drift stays
  # a real signal; the live value is read by the startup script above (S1.5).
  lifecycle {
    ignore_changes = [metadata["app-host-ip"]]
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

# =============================================================================
# App host — the machine Kamal deploys onto (roles web + job + coap) [OPS.37]
# =============================================================================
#
# Returned 2026-08-30 as the named 🤖 leg of the OPS.37 verdict. It was deleted
# by `5236104a` (2026-04-19, "infrastructure pivot") together with the canopy VM
# and Memorystore, because the real compute was meant to move to a platform that
# was itself cut on 2026-08-29. The cut restored the Kamal path but not the host,
# so `config/deploy.yml` pointed its three roles at a placeholder IP and
# `06_01` had to carry "⚠️ ще НЕ провіжений" in its own architecture diagram.
#
# ⛔ THIS RESOURCE DOES NOT ANSWER THE CANOPY QUESTION, and that silence is
# deliberate. Whether canopy gets its OWN host (and its own keys) is an OPEN ⚖️
# in OPS.37 — canopy today maps the SAME mainnet RPC secrets as production, so a
# `job` role there would sign on mainnet from staging. Provisioning ONE host is
# not a vote for "canopy shares this one": production needs a host under either
# answer. Do not read the absence of a second instance as the decision — that is
# precisely the mistake `c604ac19` made when it wrote "same host as production"
# into the canopy config as if it were a design.
#
# SIZE — 2 vCPU / 8 GB, and the binding constraint is the ROLLING DEPLOY, not
# steady state. Steady state fits in ~3.5 GB (2 Puma workers + Sidekiq 15 threads
# + the coap daemon, each a full Rails boot ~0.5 GB, plus kamal-proxy and the OS).
# But `Kamal::Cli::App::Boot#run` starts the NEW version BEFORE stopping the old
# one, so peak is roughly steady-state + one more web container — a 4 GB machine
# would fit the first deploy and OOM on the second. 8 GB is the honest floor, and
# it matches the "2 vCPU / 8 GB / 30 GB SSD" the (now-removed) deploy doc promised
# for months while terraform carried nothing (class DOC-T.50).
# Connection budget for this shape is computed in `06_01 §max_connections`
# (WEB_CONCURRENCY=2 → 126 + job 51 + admin 8 ≈ 185 of 400).
#
# NO PUBLIC IP, on purpose. The Ingress Anchor is the single public entry: it
# TCP-proxies 80/443 here via HAProxy and relays UDP 5683 via socat, and its
# address is the one frozen into Queen firmware. Egress (Artifact Registry pulls,
# Upstash TLS) goes through Cloud NAT, which already covers every subnet range.
# Inbound from the anchor rides `allow_internal` (subnet CIDR, no target tags).
# The `web-nodes` tag is here for ONE reason — `allow_iap_ssh` targets it — and
# the two internet-facing rules that share the tag (`allow_web`, `allow_coap`)
# are inert against an instance with no external address.
#
# 🔴 DOCKER IS PRE-INSTALLED, and this is a requirement rather than a courtesy —
# verified against kamal 2.12 source (lib/kamal/cli/server.rb#bootstrap): if
# `docker -v` fails, kamal tries `sudo -n true` and, without passwordless root,
# RAISES "Docker is not installed … and can't be automatically installed". Our
# deploy SA holds `roles/compute.osLogin` (iam.tf), NOT `osAdminLogin` — sudo is
# reserved for the human `iap_admin_members` — so `kamal server bootstrap` cannot
# provision this host by design. Pre-installing also keeps an unpinned
# `curl -fsSL https://get.docker.com | sh` off the boot path of the machine that
# holds the money keys.
# ⚠️ RESIDUAL, named rather than discovered on deploy day: kamal's other bootstrap
# step, `sudo -n usermod -aG docker`, needs the same sudo. So the OS Login
# identity still has to reach the docker socket somehow, and HOW is part of the
# INF.20 (б) glue (ssh.proxy_command over an IAP tunnel + the SSH user, which
# under OS Login is `sa_<numeric>`, not the `deploy` in config/deploy.yml). This
# host is the blueprint; the CI kamal leg stays honestly non-functional until
# that glue lands.
resource "google_compute_instance" "app" {
  name = "silken-net-app"
  # See SIZE above: sized by the rolling-deploy overlap, not steady state.
  machine_type = "e2-standard-2"
  zone         = var.zone
  # TERMINATED = зупинено: vCPU/RAM не тарифікуються, диск лишається (variables.tf)
  desired_status = var.compute_desired_status
  # Only for allow_iap_ssh — see NO PUBLIC IP above.
  tags = ["web-nodes"]

  # Same API-level guard as the anchor above (see its note): the flag maps straight to
  # GCP, so it blocks `gcloud`/console deletion, not only `terraform destroy`.
  deletion_protection = var.enable_deletion_protection

  boot_disk {
    initialize_params {
      # debian-12 to match the Anchor: one OS to operate, one apt idiom in both
      # startup scripts. (The pre-pivot host was ubuntu-24.04; nothing depends on it.)
      image = "debian-cloud/debian-12"
      # 30 GB: docker + several Kamal-retained versions of the Rails image
      # (~2 GB unpacked each) + logs. Matches the long-standing doc promise.
      size = 30
      type = "pd-ssd"
    }
    # CMEK — the disk holds the money quintet in plaintext under
    # .kamal/…/env/roles/job.env (kamal uploads it 0600 at boot). Rationale and
    # the source citation live on the key itself, terraform/kms.tf.
    kms_key_self_link = google_kms_crypto_key.app_boot.id
  }

  network_interface {
    network    = google_compute_network.silken_net_vpc.name
    subnetwork = google_compute_subnetwork.web.name
    # No access_config → no external IP. Deliberate; see the header.
  }

  metadata = {
    enable-oslogin = "TRUE"
    # OS Login already ignores project-wide keys; block them explicitly too
    # (defense-in-depth, AVD-GCP-0030) — same posture as the Anchor.
    block-project-ssh-keys = "TRUE"
  }

  # Docker only. Everything above the daemon is Kamal's job — this host must NOT
  # grow a second deploy mechanism, or `kamal deploy` and the startup script
  # would both claim ownership of the same containers.
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e
    if ! command -v docker &> /dev/null; then
      apt-get update -qq && apt-get install -y -qq docker.io
    fi
    systemctl enable --now docker

    # ---- INF.20 (б) move (3): docker socket for the deploy SA -----------------
    # kamal runs `docker` over SSH as the deploy SA's OS Login identity, whose posix
    # name is `sa_<numeric unique_id>`. `kamal server bootstrap` cannot grant it —
    # its `sudo -n usermod -aG docker` needs root, and the SA deliberately holds
    # compute.osLogin, NOT osAdminLogin (sudo stays with iap_admin_members). That is
    # also why docker is pre-installed above rather than curl|sh'd on the boot path
    # of the machine that holds the money keys.
    # 🔑 The account does NOT exist yet — the guest agent mints it on FIRST OS Login,
    # and both usermod and gpasswd refuse an unknown user. /etc/group is keyed by
    # NAME, so the membership can be written ahead of the account and is honoured
    # the moment it appears. ⚠️ `sa_<unique_id>` is a claim about GOOGLE's naming,
    # not about our config: verify once in Фаза 1 with
    #   gcloud compute os-login describe-profile --format='value(posixAccounts[0].username)'
    # run AS the impersonated SA — that same value also fills `ssh.user` (move 1).
    DEPLOY_SA_POSIX="sa_${google_service_account.deploy.unique_id}"
    DOCKER_MEMBERS="$(getent group docker | cut -d: -f4)"
    case ",$DOCKER_MEMBERS," in
      *",$DEPLOY_SA_POSIX,"*)
        logger -t silken-app "docker group already carries $DEPLOY_SA_POSIX" ;;
      *)
        if [ -z "$DOCKER_MEMBERS" ]; then
          NEW_MEMBERS="$DEPLOY_SA_POSIX"
        else
          NEW_MEMBERS="$DOCKER_MEMBERS,$DEPLOY_SA_POSIX"
        fi
        sed -i "s|^docker:\([^:]*\):\([^:]*\):.*|docker:\1:\2:$NEW_MEMBERS|" /etc/group
        logger -t silken-app "docker group: added $DEPLOY_SA_POSIX (deploy SA OS Login identity, INF.20 move 3)" ;;
    esac

    logger -t silken-app "app host ready: docker $(docker -v 2>/dev/null || echo MISSING); docker group = $(getent group docker | cut -d: -f4)"
  EOF

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email = google_service_account.deploy.email
    # Same two scopes as the Anchor. Artifact Registry pulls authenticate with
    # the registry password in config/deploy.yml (a short-lived WIF token), not
    # with instance scopes, so `storage-ro` earns nothing here.
    scopes = ["logging-write", "monitoring-write"]
  }

  allow_stopping_for_update = true

  depends_on = [
    google_project_service.compute,
    # Same ordering constraint as the Anchor: the compute service agent must hold
    # encrypter/decrypter on the boot key BEFORE the encrypted disk is created,
    # and the VM references the KEY, not the binding.
    google_kms_crypto_key_iam_member.app_boot_agent,
  ]
}
