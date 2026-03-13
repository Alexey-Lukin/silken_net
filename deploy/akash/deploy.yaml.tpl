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
      - REDIS_URL=${redis_url}
      - KREDIS_REDIS_URL=${kredis_redis_url}
      - SOLID_QUEUE_IN_PUMA=true
      - RAILS_ENV=production
      - WEB_CONCURRENCY=${web_concurrency}
    expose:
      - port: 80
        as: 80
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

deployment:
  web:
    silken-dcloud:
      profile: web
      count: ${web_replicas}
