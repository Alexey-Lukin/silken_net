# =============================================================================
# Akash SDL Template — rendered by Terraform with injected variables.
# Do not deploy this file directly. Use terraform/akash/ or the static
# deploy/akash/deploy.yaml instead.
# =============================================================================
---
version: "2.0"

services:
  web:
    image: ${docker_image}
    env:
      - PORT=80
      - RAILS_MASTER_KEY=${rails_master_key}
      - DATABASE_URL=${database_url}
      - CLOUD_SQL_INSTANCE_CONNECTION_NAME=${cloud_sql_instance_connection_name}
      - GCP_SA_KEY_BASE64=${gcp_sa_key_base64}
      - REDIS_URL=${redis_url}
      - KREDIS_REDIS_URL=${kredis_redis_url}
      - RAILS_ENV=production
      - RAILS_MAX_THREADS=${rails_max_threads}
      - WEB_CONCURRENCY=${web_concurrency}
      - PROMETHEUS_AUTH_USER=${prometheus_auth_user}
      - PROMETHEUS_AUTH_PASSWORD=${prometheus_auth_password}
    expose:
      - port: 80
        as: 80
        to:
          - global: true
      - port: 443
        as: 443
        to:
          - global: true
      - port: 5683
        as: 5683
        proto: udp
        to:
          - global: true
    params:
      storage:
        data:
          mount: /rails/storage
          readOnly: false

  job:
    image: ${docker_image}
    command:
      - "/rails/bin/docker-entrypoint"
      - "bundle"
      - "exec"
      - "sidekiq"
      - "-C"
      - "config/sidekiq.yml"
    env:
      - RAILS_MASTER_KEY=${rails_master_key}
      - DATABASE_URL=${database_url}
      - CLOUD_SQL_INSTANCE_CONNECTION_NAME=${cloud_sql_instance_connection_name}
      - GCP_SA_KEY_BASE64=${gcp_sa_key_base64}
      - REDIS_URL=${redis_url}
      - KREDIS_REDIS_URL=${kredis_redis_url}
      - RAILS_ENV=production
      - RAILS_MAX_THREADS=${rails_max_threads}

  alloy:
    image: grafana/alloy:latest
    env:
      - GRAFANA_REMOTE_WRITE_URL=${grafana_remote_write_url}
      - GRAFANA_REMOTE_WRITE_USERNAME=${grafana_remote_write_username}
      - GRAFANA_REMOTE_WRITE_TOKEN=${grafana_remote_write_token}
      - PROMETHEUS_AUTH_USER=${prometheus_auth_user}
      - PROMETHEUS_AUTH_PASSWORD=${prometheus_auth_password}
      - ALLOY_CONFIG_BASE64=${alloy_config_base64}
    command:
      - "/bin/sh"
      - "-c"
    args:
      - "mkdir -p /etc/alloy && echo $ALLOY_CONFIG_BASE64 | base64 -d > /etc/alloy/config.alloy && alloy run --server.http.listen-addr=0.0.0.0:12345 --storage.path=/var/lib/alloy/data /etc/alloy/config.alloy"

profiles:
  compute:
    web:
      resources:
        cpu:
          units: ${web_cpu_units}
        memory:
          size: ${web_memory_size}
        storage:
          - size: ${web_storage_size}
          - name: data
            size: ${persistent_storage}
            attributes:
              persistent: true
              class: beta3
    job:
      resources:
        cpu:
          units: 2
        memory:
          size: 4Gi
        storage:
          - size: 20Gi
    alloy:
      resources:
        cpu:
          units: 0.5
        memory:
          size: 512Mi
        storage:
          - size: 1Gi
  placement:
    silken-dcloud:
      attributes:
        host: akash
      signedBy:
        anyOf:
          - ${akash_auditor}
      pricing:
        web:
          denom: uakt
          amount: ${max_price_uakt}
        job:
          denom: uakt
          amount: 5000
        alloy:
          denom: uakt
          amount: 1000

deployment:
  web:
    silken-dcloud:
      profile: web
      count: ${web_replicas}
  job:
    silken-dcloud:
      profile: job
      count: 1
  alloy:
    silken-dcloud:
      profile: alloy
      count: 1
