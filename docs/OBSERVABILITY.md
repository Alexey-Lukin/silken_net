# 📊 Observability — Prometheus Metrics for Gaia 2.0

## Why Observability Matters

Gaia 2.0 is a **cyber-physical financial system** that processes:
- **IoT telemetry** from millions of tree-mounted sensors (21-byte binary packets via CoAP/UDP)
- **12 blockchain networks** (Polygon, Ethereum, Solana, Celo, IoTeX, Chainlink, etc.)
- **Real money** — SCC/SFC token minting, slashing, and insurance payouts

Without observability, we are **blind** to:

| Failure Mode | Business Impact | What Metrics Catch It |
|---|---|---|
| Sidekiq `web3` queue growing unboundedly | Minting transactions pile up → investors don't receive tokens | `web3_queue_size`, `web3_queue_latency_seconds` |
| Alchemy/Infura RPC timeouts spike | All blockchain operations halt silently | `rpc_errors_total{network, error_type}` |
| Sensor noise / DID spoofing attacks | Fraudulent telemetry → unearned token minting | `telemetry_fraud_detected_total` |
| CoAP ingestion rate drops to zero | Forest is offline — no data, no alerts, no insurance triggers | `telemetry_processed_total` |
| Slashing events spike | Ecosystem is under stress — potential mass token burn | `scc_slashed_total` |

In a system that scales to **billions of trees** and manages **real financial assets on-chain**, silent failures cost money. Prometheus metrics give us the numbers; Grafana dashboards give us the visualization; alerting rules give us the early warning.

## Architecture Decision: Why `prometheus-client`

### Options Evaluated

| Tool | Gems Required | Pros | Cons |
|---|---|---|---|
| **Yabeda** (`yabeda-prometheus`, `yabeda-sidekiq`, `yabeda-rails`) | 4–5 gems | Nice DSL, auto-instruments Rails/Sidekiq | Adds transitive dependencies, magic auto-instrumentation we don't need, slower maintenance cadence |
| **OpenTelemetry** (`opentelemetry-sdk`, `opentelemetry-exporter-otlp`, adapters) | 6–10 gems | Industry standard for traces/spans/logs | Massive overhead for our use case (we need counters/gauges, not distributed tracing), complex setup, vendor-oriented |
| **`prometheus-client`** (single gem) | **1 gem** | Official Prometheus Ruby client, thread-safe, zero magic, works perfectly with custom business metrics | No auto-instrumentation (which is fine — we instrument exactly what matters) |

### Why We Chose `prometheus-client`

1. **Lean** — One gem, zero transitive dependency bloat. The Gemfile stays clean.
2. **Official** — Maintained by the Prometheus organization itself (not a community wrapper).
3. **Thread-safe** — Critical for Sidekiq workers (16 threads × 7 queues).
4. **Custom metrics** — We need domain-specific counters (`scc_minted_total`, `rpc_errors_total`), not generic Rails request histograms. Yabeda's auto-instrumentation adds noise.
5. **Rails 8.1 native** — Works with `ActiveSupport::Notifications` (already used by Rack::Attack). No framework conflict.
6. **No Redis dependency** — Metrics live in-process memory. No extra infrastructure.

### What We Already Had

The `SystemHealthController` (`/api/v1/system_health`) provides a JSON health check for the dashboard. It uses `Sidekiq::Stats` to show queue sizes. However, it:
- Requires authentication (not suitable for Prometheus scraping)
- Returns JSON snapshots (not Prometheus text format)
- Cannot define counters/gauges that accumulate over time

The new `/metrics` endpoint **complements** the existing health check — it's designed for machine consumption (Prometheus), not human consumption (dashboard).

## Metrics Reference

### Counters (monotonically increasing)

| Metric | Labels | Instrumented In | What It Tracks |
|---|---|---|---|
| `silkennet_scc_minted_total` | `token_type` (carbon_coin, forest_coin) | `BlockchainMintingService` | Every successful token mint sent to Polygon mempool |
| `silkennet_scc_slashed_total` | — | `BlockchainBurningService` | Token amount burned during slashing events |
| `silkennet_rpc_errors_total` | `network`, `error_type` (timeout, connection) | `ApplicationWeb3Worker` | Every RPC failure across all 12 blockchain networks |
| `silkennet_telemetry_processed_total` | — | `TelemetryUnpackerService` | Every successfully committed telemetry chunk |
| `silkennet_telemetry_fraud_detected_total` | — | `TelemetryUnpackerService` | Rejected packets (sensor noise, unknown DID) |

### Gauges (point-in-time values, refreshed on scrape)

| Metric | Labels | Refreshed By | What It Tracks |
|---|---|---|---|
| `silkennet_web3_queue_size` | `queue` (web3, web3_critical) | `PrometheusCollector` middleware | Current number of jobs in Sidekiq Web3 queues |
| `silkennet_web3_queue_latency_seconds` | `queue` | `PrometheusCollector` middleware | Age of the oldest job in the queue (seconds) |

## Endpoint Security

The `/metrics` endpoint exposes **internal financial metrics** (minted tokens, slashing, RPC errors). It **must not** be publicly accessible.

### Protection Layers

```
Internet Request → /metrics
        │
        ├─ IP Allowlist ──→ 403 Forbidden (if public IP)
        │   ✓ 127.0.0.0/8 (localhost)
        │   ✓ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 (RFC 1918)
        │   ✓ fc00::/7 (RFC 4193 IPv6)
        │   ✓ PROMETHEUS_ALLOWED_IPS env (custom CIDR list)
        │
        └─ HTTP Basic Auth ──→ 403 Forbidden (if credentials wrong)
            Only enforced when PROMETHEUS_AUTH_USER +
            PROMETHEUS_AUTH_PASSWORD env vars are set
```

### Configuration

| ENV Variable | Required | Example | Purpose |
|---|---|---|---|
| `PROMETHEUS_ALLOWED_IPS` | No | `203.0.113.0/24,10.5.0.0/16` | Extra IPs/CIDRs allowed to scrape `/metrics` |
| `PROMETHEUS_AUTH_USER` | No | `prometheus` | HTTP Basic Auth username |
| `PROMETHEUS_AUTH_PASSWORD` | No | `s3cr3t` | HTTP Basic Auth password |

### Prometheus Scrape Config Example

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'silkennet'
    scrape_interval: 15s
    metrics_path: '/metrics'
    basic_auth:
      username: 'prometheus'
      password: 's3cr3t'
    static_configs:
      - targets: ['rails-app:3000']
```

## File Map

| File | Purpose |
|---|---|
| `Gemfile` | Added `prometheus-client` gem |
| `config/initializers/prometheus.rb` | Defines `SilkenNet::Metrics` module with all counters/gauges |
| `app/middleware/prometheus_collector.rb` | Rack middleware for secured `/metrics` endpoint |
| `config/application.rb` | Wires `PrometheusCollector` into middleware stack |
| `app/services/blockchain_minting_service.rb` | Increments `scc_minted_total` on successful mint |
| `app/services/blockchain_burning_service.rb` | Increments `scc_slashed_total` on successful slash |
| `app/services/telemetry_unpacker_service.rb` | Increments `telemetry_processed_total` and `telemetry_fraud_detected_total` |
| `app/workers/application_web3_worker.rb` | Increments `rpc_errors_total` on RPC failures |
| `spec/initializers/prometheus_spec.rb` | Tests for metrics registration |
| `spec/middleware/prometheus_collector_spec.rb` | Tests for endpoint security (IP allowlist, Basic Auth) |
