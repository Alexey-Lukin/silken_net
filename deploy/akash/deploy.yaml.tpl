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
      # --- Application core ---
      - PORT=80
      - RAILS_ENV=production
      - RAILS_MASTER_KEY=${rails_master_key}
      - POSTGRES_HOST=127.0.0.1
      - POSTGRES_USER=silken_net
      - POSTGRES_PASSWORD=${db_password}
      # DB SET selector (config/database.yml; defaults to silken_net_production if unset).
      # Explicit so a canopy-on-Akash render just overrides to silken_net_canopy. [INF.16]
      - POSTGRES_DATABASE=${postgres_database}
      - CLOUD_SQL_INSTANCE_CONNECTION_NAME=${cloud_sql_instance_connection_name}
      - GCP_SA_KEY_BASE64=${gcp_sa_key_base64}
      - REDIS_URL=${redis_url}
      # KREDIS_REDIS_URL omitted — auto-derives from REDIS_URL (config/redis/shared.yml). [B1]
      - RAILS_MAX_THREADS=${rails_max_threads}
      - WEB_CONCURRENCY=${web_concurrency}
      # Mailer link host (production.rb) — the host INSIDE the body; transport below.
      - APP_HOST=silkennet.com
      # --- 🛑 BOOT-CRITICAL: mail_transport_check.rb raises without MAIL_FROM + SMTP_ADDRESS.
      #     Plain SMTP, no vendor SDK — swapping ESP is these values and nothing else. ---
      - MAIL_FROM=${mail_from}
      - SMTP_ADDRESS=${smtp_address}
      - SMTP_USER_NAME=${smtp_user_name}
      - SMTP_PASSWORD=${smtp_password}
      # Telegram bot token [ARCH.60] — optional: transport no-ops when unset.
      - TELEGRAM_BOT_TOKEN=${telegram_bot_token}
      # [ARCH.81] CoAP intake address for the admin health probe — the same host
      # a Queen dials; unset means the panel reports "not configured", never "dead".
      - COAP_HOST=api.silkennet.com
%{ if release_version != "" }      - RELEASE_VERSION=${release_version}
%{ endif ~}
      # --- 🛑 BOOT-CRITICAL: master_key_strength_check.rb ---
      - PROVISIONING_MASTER_KEY=${provisioning_master_key}
      # --- 🛑 BOOT-CRITICAL: active_record_encryption_keys_check.rb ---
      - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${active_record_encryption_primary_key}
      - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${active_record_encryption_deterministic_key}
      - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${active_record_encryption_key_derivation_salt}
      # --- Observability ---
      - SENTRY_DSN=${sentry_dsn}
      - PROMETHEUS_AUTH_USER=${prometheus_auth_user}
      - PROMETHEUS_AUTH_PASSWORD=${prometheus_auth_password}
      # --- Web3 money/signing keys DELIBERATELY ABSENT (job-only; Akash ENV is
      #     plaintext to the provider — the internet-facing web surface must not
      #     carry them; guard scoped via signer_process: Sidekiq.server?) ---
      # --- RPC endpoints (Web3::RpcConnectionPool) ---
      - ALCHEMY_POLYGON_RPC_URL=${alchemy_polygon_rpc_url}
      - ALCHEMY_ETHEREUM_RPC_URL=${alchemy_ethereum_rpc_url}
      - SOLANA_RPC_URL=${solana_rpc_url}
      # Separate from ALCHEMY_*: Celo rewards (CELO_RPC_URL).
      - CELO_RPC_URL=${celo_rpc_url}
      # --- Solana public identifiers (signing keypair is job-only) ---
      - SOLANA_FEE_PAYER_PUBKEY=${solana_fee_payer_pubkey}
      - SOLANA_FEE_PAYER_TOKEN_ACCOUNT=${solana_fee_payer_token_account}
      - SOLANA_USDC_MINT_ADDRESS=${solana_usdc_mint_address}
      # --- Webhook HMACs: Chainlink callback (dispatch removed — ARCH.53) +
      #     Helium SOS (ARCH.34; strict mode raises per-request without it) ---
      - CHAINLINK_HMAC_SECRET=${chainlink_hmac_secret}
      - HELIUM_WEBHOOK_SECRET=${helium_webhook_secret}
      # Web3 fail-closed: Hadron KYC raises on missing creds + callback HMAC fail-fast (INF.11/SEC.5).
      - WEB3_STRICT_MODE=true
      # --- Web3 contract addresses (post-`forge deploy`; fill before first mint) ---
      # Public on-chain addresses (not secrets) but unknown until contracts deploy, so
      # NOT terraform-managed (deploy-order). Placeholder → fail-loud on use. docs/06_04 §2.1.
      - CARBON_COIN_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - FOREST_COIN_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - DAO_TREASURY_ADDRESS=REQUIRED_SECRET_NOT_SET
      - ETHEREUM_ANCHOR_CONTRACT=REQUIRED_SECRET_NOT_SET
      - PROTOCOL_PARAMETERS_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - CELO_CUSD_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - KLIMA_RETIREMENT_CONTRACT=REQUIRED_SECRET_NOT_SET
      - ETHERISC_DIP_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - PURO_EARTH_REGISTRY_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
    expose:
      # `service: alloy` = internal route for the /metrics scrape (INF.14) —
      # via the public ingress it would die on the IP-allowlist 403.
      - port: 80
        as: 80
        to:
          - global: true
          - service: alloy
      - port: 443
        as: 443
        to:
          - global: true
      # CoAP UDP 5683 lives on the dedicated `coap` service below (INF.17).
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
      # --- Application core ---
      - RAILS_ENV=production
      - RAILS_MASTER_KEY=${rails_master_key}
      - POSTGRES_HOST=127.0.0.1
      - POSTGRES_USER=silken_net
      - POSTGRES_PASSWORD=${db_password}
      # DB SET selector (config/database.yml; defaults to silken_net_production if unset).
      # Explicit so a canopy-on-Akash render just overrides to silken_net_canopy. [INF.16]
      - POSTGRES_DATABASE=${postgres_database}
      - CLOUD_SQL_INSTANCE_CONNECTION_NAME=${cloud_sql_instance_connection_name}
      - GCP_SA_KEY_BASE64=${gcp_sa_key_base64}
      - REDIS_URL=${redis_url}
      # KREDIS_REDIS_URL omitted — auto-derives from REDIS_URL (config/redis/shared.yml). [B1]
      - RAILS_MAX_THREADS=${rails_max_threads}
      # Sidekiq concurrency=15 → DB pool must match + headroom (config/sidekiq.yml).
      - DB_POOL=17
      # Mailer link host (production.rb — deliver_later runs here).
      - APP_HOST=silkennet.com
      # --- 🛑 BOOT-CRITICAL: mail_transport_check.rb. This is the service that ACTUALLY
      #     delivers (deliver_later ⇒ Sidekiq); web only enqueues but is gated too, so a
      #     misconfiguration is visible on the surface an operator looks at. ---
      - MAIL_FROM=${mail_from}
      - SMTP_ADDRESS=${smtp_address}
      - SMTP_USER_NAME=${smtp_user_name}
      - SMTP_PASSWORD=${smtp_password}
      # Telegram bot token [ARCH.60] — optional: transport no-ops when unset.
      - TELEGRAM_BOT_TOKEN=${telegram_bot_token}
%{ if release_version != "" }      - RELEASE_VERSION=${release_version}
%{ endif ~}
      # --- 🛑 BOOT-CRITICAL: master_key_strength_check.rb ---
      - PROVISIONING_MASTER_KEY=${provisioning_master_key}
      # --- 🛑 BOOT-CRITICAL: active_record_encryption_keys_check.rb ---
      - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${active_record_encryption_primary_key}
      - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${active_record_encryption_deterministic_key}
      - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${active_record_encryption_key_derivation_salt}
      # --- Observability ---
      - SENTRY_DSN=${sentry_dsn}
      # --- Web3 oracle keys (BlockchainMintingService, BlockchainBurningService,
      #     Ethereum::StateAnchorService — all Sidekiq workers). Legacy shared
      #     ORACLE_PRIVATE_KEY RETIRED [INF.22]; aux signers (ETHERISC/PURO/KLIMA)
      #     are activation-gated — Console-injected, never rendered here. ---
      # Dedicated Celo cUSD signer (ARCH.50).
      - ORACLE_CELO_PRIVATE_KEY=${oracle_celo_private_key}
      - ORACLE_MINTER_PRIVATE_KEY=${oracle_minter_private_key}
      - ORACLE_SLASHER_PRIVATE_KEY=${oracle_slasher_private_key}
      - ETHEREUM_ANCHOR_PRIVATE_KEY=${ethereum_anchor_private_key}
      # --- RPC endpoints ---
      - ALCHEMY_POLYGON_RPC_URL=${alchemy_polygon_rpc_url}
      - ALCHEMY_ETHEREUM_RPC_URL=${alchemy_ethereum_rpc_url}
      - SOLANA_RPC_URL=${solana_rpc_url}
      # Separate from ALCHEMY_*: Celo rewards (CELO_RPC_URL).
      - CELO_RPC_URL=${celo_rpc_url}
      # --- Solana minting (SolanaMicroRewardWorker) ---
      - SOLANA_WALLET_KEYPAIR=${solana_wallet_keypair}
      - SOLANA_FEE_PAYER_PUBKEY=${solana_fee_payer_pubkey}
      - SOLANA_FEE_PAYER_TOKEN_ACCOUNT=${solana_fee_payer_token_account}
      - SOLANA_USDC_MINT_ADDRESS=${solana_usdc_mint_address}
      # CHAINLINK_HMAC_SECRET is WEB-ONLY (oracle_callbacks_controller ingress) —
      # deliberately absent from job: zero worker/service consumers (verified).
      # Web3 fail-closed: Hadron KYC raises on missing creds (INF.11/SEC.5).
      - WEB3_STRICT_MODE=true
      # --- Web3 contract addresses (post-`forge deploy`; fill before first mint) ---
      # Public on-chain addresses (not secrets) but unknown until contracts deploy, so
      # NOT terraform-managed (deploy-order). Placeholder → fail-loud on use. docs/06_04 §2.1.
      - CARBON_COIN_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - FOREST_COIN_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - DAO_TREASURY_ADDRESS=REQUIRED_SECRET_NOT_SET
      - ETHEREUM_ANCHOR_CONTRACT=REQUIRED_SECRET_NOT_SET
      - PROTOCOL_PARAMETERS_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - CELO_CUSD_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - KLIMA_RETIREMENT_CONTRACT=REQUIRED_SECRET_NOT_SET
      - ETHERISC_DIP_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
      - PURO_EARTH_REGISTRY_CONTRACT_ADDRESS=REQUIRED_SECRET_NOT_SET
    # Embedded /metrics exporter — internal-only route for the Alloy scrape.
    expose:
      - port: 9394
        as: 9394
        to:
          - service: alloy

  # CoAP/UDP telemetry intake daemon (INF.17) — mirrors deploy/akash/deploy.yaml.
  coap:
    image: ${docker_image}
    command:
      - "/rails/bin/docker-entrypoint"
      - "bundle"
      - "exec"
      - "ruby"
      - "lib/daemons/coap_listener"
    env:
      # Boot-critical subset only: loads config/environment, parses PDUs,
      # enqueues to Redis — no Web3 workers here.
      - RAILS_ENV=production
      - RAILS_MASTER_KEY=${rails_master_key}
      - POSTGRES_HOST=127.0.0.1
      - POSTGRES_USER=silken_net
      - POSTGRES_PASSWORD=${db_password}
      - POSTGRES_DATABASE=${postgres_database}
      - CLOUD_SQL_INSTANCE_CONNECTION_NAME=${cloud_sql_instance_connection_name}
      - GCP_SA_KEY_BASE64=${gcp_sa_key_base64}
      - REDIS_URL=${redis_url}
      # KREDIS_REDIS_URL omitted — auto-derives from REDIS_URL (config/redis/shared.yml). [B1]
      # No PROVISIONING_MASTER_KEY — master_key_strength_check skips coap_listener
      # (code-proven $PROGRAM_NAME guard): coap only enqueues. Keep the HKDF root off
      # coap's plaintext env [SEC.22]. Web/job carry the shared var; coap must not.
      # --- 🛑 BOOT-CRITICAL: active_record_encryption_keys_check.rb ---
      - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${active_record_encryption_primary_key}
      - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${active_record_encryption_deterministic_key}
      - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${active_record_encryption_key_derivation_salt}
      # --- Observability ---
      - SENTRY_DSN=${sentry_dsn}
%{ if release_version != "" }      - RELEASE_VERSION=${release_version}
%{ endif ~}
      # Consistency with web/job (INF.11) — the flag must never differ across surfaces.
      - WEB3_STRICT_MODE=true
    expose:
      - port: 5683
        as: 5683
        proto: udp
        to:
          - global: true
      # Embedded /metrics exporter — internal-only route for the Alloy scrape.
      - port: 9395
        as: 9395
        to:
          - service: alloy

  alloy:
    image: grafana/alloy:v1.16.3
    env:
      # Slot label for external_labels (canopy vs production — config.alloy).
      - DEPLOYMENT_SLOT=${deployment_slot}
%{ if release_version != "" }      - RELEASE_VERSION=${release_version}
%{ endif ~}
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
    coap:
      resources:
        cpu:
          units: 0.5
        memory:
          size: 1Gi
        storage:
          - size: 10Gi
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
%{ if akash_region != "" }        region: ${akash_region}
%{ endif ~}
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
        coap:
          denom: uakt
          amount: 2000
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
  coap:
    silken-dcloud:
      profile: coap
      count: 1
  alloy:
    silken-dcloud:
      profile: alloy
      count: 1
