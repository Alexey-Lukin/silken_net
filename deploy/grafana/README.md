# Grafana IaC — SilkenNet

Infrastructure-as-Code конфіги для Grafana Cloud. Замінюють ручне налаштування в UI (S2.2/S2.3).

## Структура

```
deploy/grafana/
├── dashboards/
│   └── silkennet-overview.json   # Головний дашборд (8 секцій)
├── alerts/
│   └── silkennet-alerts.yaml     # alert rules (P0/P1/P2)
└── import.rb                     # one-command імпорт обох артефактів
```

## Імпорт — одна команда

```bash
# Перевірка артефактів без credentials (нічого не шле):
ruby deploy/grafana/import.rb --dry-run

# Імпорт (service-account token із роллю Editor+):
GRAFANA_URL=https://<stack>.grafana.net \
GRAFANA_API_TOKEN=<token> \
  ruby deploy/grafana/import.rb
```

Скрипт сам: знаходить UID Prometheus datasource (або `DATASOURCE_UID` env),
створює folder «SilkenNet» (або `GRAFANA_FOLDER`), імпортує дашборд із
правильним `inputs`-wrapper'ом і робить ідемпотентний upsert усіх alert rules
(кількість — `rule_count`, import.rb рахує з yaml) через Alerting Provisioning API (`X-Disable-Provenance` — рулі лишаються
редагованими в UI). Плейсхолдер `${DATASOURCE_UID}` підставляється в
пам'яті — файл у репо не змінюється. Повторний запуск безпечний.

**Fallback через UI** (якщо токена нема): Dashboards → Import → upload
`dashboards/silkennet-overview.json` → select Prometheus datasource;
Alerting → Alert rules → Import → paste `alerts/silkennet-alerts.yaml`
(попередньо замінивши `${DATASOURCE_UID}` на UID datasource — у копії,
не в репо-файлі).

## Дашборд: секції

| Секція | Метрики | S2.2 item |
|--------|---------|-----------|
| Telemetry Ingest + Fraud | processed_total, fraud_total, acoustic_overflow, panic_replay, cluster_entropy, tinyml_threshold_invalid_reports (FW.18b), coap_packets by status | Telemetry ingest rate + fraud detection |
| Sidekiq Queues | queue_size × 9, queue_latency × 9 | Sidekiq queues (9 черг, size + latency) |
| Web3 RPC | rpc_errors by network/type, circuit_breaker_open, scc_minted, oracle_dispatch latency | Web3 RPC errors by network |
| Treasury / Oracle | oracle_balance_ratio, oracle_balance by network | Treasury / Oracle balance monitoring |
| Database Pool | db_pool_connections / db_pool_size, db_pool_waiting | Database connection pool stats |
| 💰 Money-Path Reliability [ARCH.45] | mint/slash/solana-payout/insurance-payout success-rate (SLO ratio), sidekiq_dead_set_size, manual_review_depth, limbo_locked_total, chain_audit_delta [G1/G2] | Money-path SLO + DeadSet + manual-review/limbo/chain-audit gauges |
| ⚙️ Process / Runtime Health | process_resident_memory_bytes (RSS), ruby_gc_count/major_count, ruby_gc_heap_live_slots, ruby_threads, puma_running/max/pool_capacity/backlog | Runtime observability gap (RSS/GC/Puma) |
| 👑 Gateway / Queen Fleet Health [ARCH.54] | gateways_faulty, gateway_attest_lapsed, helium_sos_received_total by outcome | Fleet-health dashboard-gap |

## Alerts: зведення

| ID | Rule | Severity | Поріг |
|----|------|----------|-------|
| sn-alert-partition-maintenance-failed | partition maintenance failures > 0 за 24h | critical | 0m |
| sn-alert-web3-queue-critical | web3_critical queue > 100 jobs | critical | 5m |
| sn-alert-fraud-detected | fraud rate > 0/s | critical | 2m |
| sn-alert-oracle-balance-critical | oracle_balance_ratio < 0.2 | critical | 5m |
| sn-alert-panic-replay | panic replay > 0.1/s | critical | 2m |
| sn-alert-scrape-target-down | min by(process) up{job="silken_net_scraper"} < 1 (3 таргети; NoData→Alerting = Alloy впав) | critical | 5m |
| sn-alert-gateway-faulty | gateways_faulty > 0 (dead-man switch ARCH.54) | critical | 5m |
| sn-alert-chain-audit-drift | chain_audit_delta > 0.0001 (DB vs on-chain SCC drift [G2]) | critical | 15m |
| sn-alert-rpc-errors | rpc_errors > 10/хв | warning | 2m |
| sn-alert-sidekiq-latency | queue latency > 300s | warning | 5m |
| sn-alert-sidekiq-deadset | sidekiq_dead_set_size > 0 (money-path = stranded tx) | warning | 5m |
| sn-alert-manual-review-depth | manual_review_depth > 0 (funds locked, double-spend guard [G1]) | warning | 15m |
| sn-alert-blockchain-limbo | limbo_locked_total > 0 за >1h unsettled tx [G1] | warning | 30m |
| sn-alert-circuit-breaker | circuit_breaker_open == 1 | warning | 2m |
| sn-alert-cluster-entropy | cluster_entropy < 0.65 | warning | 30m |
| sn-alert-acoustic-overflow | acoustic_overflow rate > 0 | warning | 5m |
| sn-alert-tinyml-threshold-invalid | tinyml_threshold_invalid_reports rate(15m) > 0 (FW.18b) | warning | 5m |
| sn-alert-mint-slo-breach | mint success/attempts < 0.8 за 1h (guard attempts>0) | warning | 10m |
| sn-alert-mint-volume-anomaly | mint_volume_window_scc > operator-ceiling (ARCH.62 агрегатний сплеск) | warning | 10m |
| sn-alert-anchor-stalled | anchor_missed_weeks increase[8d] > 0 (broadcast-liveness; 1 з 4 anchor-сигналів ARCH.66) | warning | 1h |
| sn-alert-ethereum-anchor-stuck-sent | ethereum_anchor_stuck_sent_depth min_over_time[2h] > 0 (:sent не досяг :confirmed; ARCH.66) | warning | 1h |
| sn-alert-ethereum-anchor-manual-review | ethereum_anchor_manual_review_depth > 0 (seal чекає людської звірки; ARCH.66) | warning | 1h |
| sn-alert-ethereum-anchor-reverted | ethereum_anchor_reverted_total increase[1w] > 0 (storeStateRoot revert on-chain; ARCH.66) | info | 5m |
| sn-alert-filecoin-verification-failed | filecoin_verification_failures increase[24h] > 0 (E.60 ex-post swap) | warning | 5m |
| sn-alert-oracle-balance-warning | oracle_balance_ratio < 1.0 | info | 15m |
| sn-alert-db-pool-saturation | db_pool_waiting > 5 | info | 2m |
| sn-alert-w3bstream-fallback | w3bstream SHA256 fallback > 0 | info | 5m |
| sn-alert-gateway-flapping | gateways_offline_total increase > 2 за 30хв (нестабільний зв'язок, ARCH.54) | info | 5m |
| sn-alert-filecoin-unarchived-backlog | filecoin_unarchived_depth sustained (Pinata-exhaustion backlog; INF.22 крок 11) | info | 1h |
| sn-alert-hadron-kyc-backlog | hadron_kyc_pending_depth sustained[6h] (KYC backlog; ARCH.65, auto-heal) | info | 30m |

> Повний SSOT правил (30) — сам `alerts/silkennet-alerts.yaml`; ця таблиця — людська шпаргалка, `import.rb` рахує з yaml.

## Notification channel

Налаштувати після першого deploy:
```
Grafana → Alerting → Contact points → New contact point
  Type: Slack / PagerDuty / Email
  Name: silkennet-oncall

Grafana → Alerting → Notification policies
  Default policy → Contact point: silkennet-oncall
  Group wait: 30s
  Group interval: 5m
  Repeat interval: 4h
```
