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
      - DATABASE_URL=${database_url}
      - CLOUD_SQL_INSTANCE_CONNECTION_NAME=${cloud_sql_instance_connection_name}
      - GCP_SA_KEY_BASE64=${gcp_sa_key_base64}
      - REDIS_URL=${redis_url}
      - KREDIS_REDIS_URL=${kredis_redis_url}
      - RAILS_MAX_THREADS=${rails_max_threads}
      - WEB_CONCURRENCY=${web_concurrency}
      # --- 🛑 BOOT-CRITICAL: master_key_strength_check.rb ---
      - PROVISIONING_MASTER_KEY=${provisioning_master_key}
      # --- Observability ---
      - SENTRY_DSN=${sentry_dsn}
      - PROMETHEUS_AUTH_USER=${prometheus_auth_user}
      - PROMETHEUS_AUTH_PASSWORD=${prometheus_auth_password}
      # --- Web3 oracle keys (dual-key split) ---
      - ORACLE_PRIVATE_KEY=${oracle_private_key}
      - ORACLE_MINTER_PRIVATE_KEY=${oracle_minter_private_key}
      - ORACLE_SLASHER_PRIVATE_KEY=${oracle_slasher_private_key}
      - ETHEREUM_ANCHOR_PRIVATE_KEY=${ethereum_anchor_private_key}
      # --- RPC endpoints (Web3::RpcConnectionPool) ---
      - ALCHEMY_POLYGON_RPC_URL=${alchemy_polygon_rpc_url}
      - ALCHEMY_ETHEREUM_RPC_URL=${alchemy_ethereum_rpc_url}
      - SOLANA_RPC_URL=${solana_rpc_url}
      # --- Solana minting ---
      - SOLANA_WALLET_KEYPAIR=${solana_wallet_keypair}
      - SOLANA_FEE_PAYER_PUBKEY=${solana_fee_payer_pubkey}
      - SOLANA_FEE_PAYER_TOKEN_ACCOUNT=${solana_fee_payer_token_account}
      - SOLANA_USDC_MINT_ADDRESS=${solana_usdc_mint_address}
      # --- Chainlink Functions Router v1 ---
      - CHAINLINK_FUNCTIONS_ROUTER=${chainlink_functions_router}
      - CHAINLINK_SUBSCRIPTION_ID=${chainlink_subscription_id}
      - CHAINLINK_DON_ID=${chainlink_don_id}
      - CHAINLINK_HMAC_SECRET=${chainlink_hmac_secret}
      - CHAINLINK_DATA_VERSION=1
      - CHAINLINK_CALLBACK_GAS_LIMIT=300000
      # Web3 fail-closed: Hadron KYC / Chainlink raise on missing creds (INF.11).
      - WEB3_STRICT_MODE=true
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
      # --- Application core ---
      - RAILS_ENV=production
      - RAILS_MASTER_KEY=${rails_master_key}
      - DATABASE_URL=${database_url}
      - CLOUD_SQL_INSTANCE_CONNECTION_NAME=${cloud_sql_instance_connection_name}
      - GCP_SA_KEY_BASE64=${gcp_sa_key_base64}
      - REDIS_URL=${redis_url}
      - KREDIS_REDIS_URL=${kredis_redis_url}
      - RAILS_MAX_THREADS=${rails_max_threads}
      # --- 🛑 BOOT-CRITICAL: master_key_strength_check.rb ---
      - PROVISIONING_MASTER_KEY=${provisioning_master_key}
      # --- Observability ---
      - SENTRY_DSN=${sentry_dsn}
      # --- Web3 oracle keys (BlockchainMintingService, BlockchainBurningService,
      #     Ethereum::StateAnchorService — all Sidekiq workers) ---
      - ORACLE_PRIVATE_KEY=${oracle_private_key}
      - ORACLE_MINTER_PRIVATE_KEY=${oracle_minter_private_key}
      - ORACLE_SLASHER_PRIVATE_KEY=${oracle_slasher_private_key}
      - ETHEREUM_ANCHOR_PRIVATE_KEY=${ethereum_anchor_private_key}
      # --- RPC endpoints ---
      - ALCHEMY_POLYGON_RPC_URL=${alchemy_polygon_rpc_url}
      - ALCHEMY_ETHEREUM_RPC_URL=${alchemy_ethereum_rpc_url}
      - SOLANA_RPC_URL=${solana_rpc_url}
      # --- Solana minting (SolanaMicroRewardWorker) ---
      - SOLANA_WALLET_KEYPAIR=${solana_wallet_keypair}
      - SOLANA_FEE_PAYER_PUBKEY=${solana_fee_payer_pubkey}
      - SOLANA_FEE_PAYER_TOKEN_ACCOUNT=${solana_fee_payer_token_account}
      - SOLANA_USDC_MINT_ADDRESS=${solana_usdc_mint_address}
      # --- Chainlink Functions Router v1 (ChainlinkDispatchWorker) ---
      - CHAINLINK_FUNCTIONS_ROUTER=${chainlink_functions_router}
      - CHAINLINK_SUBSCRIPTION_ID=${chainlink_subscription_id}
      - CHAINLINK_DON_ID=${chainlink_don_id}
      - CHAINLINK_HMAC_SECRET=${chainlink_hmac_secret}
      - CHAINLINK_DATA_VERSION=1
      - CHAINLINK_CALLBACK_GAS_LIMIT=300000
      # Web3 fail-closed: Hadron KYC / Chainlink raise on missing creds (INF.11).
      - WEB3_STRICT_MODE=true

  alloy:
    image: grafana/alloy:v1.16.3
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
