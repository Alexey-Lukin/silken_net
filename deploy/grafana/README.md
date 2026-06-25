# Grafana IaC — SilkenNet

Infrastructure-as-Code конфіги для Grafana Cloud. Замінюють ручне налаштування в UI (S2.2/S2.3).

## Структура

```
deploy/grafana/
├── dashboards/
│   └── silkennet-overview.json   # Головний дашборд (5 секцій)
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
| Telemetry Ingest + Fraud | processed_total, fraud_total, acoustic_overflow, panic_replay, cluster_entropy, tinyml_threshold_invalid_reports (FW.18b) | Telemetry ingest rate + fraud detection |
| Sidekiq Queues | queue_size × 9, queue_latency × 9 | Sidekiq queues (9 черг, size + latency) |
| Web3 RPC | rpc_errors by network/type, circuit_breaker_open, scc_minted, oracle_dispatch latency | Web3 RPC errors by network |
| Treasury / Oracle | oracle_balance_ratio, oracle_balance by network | Treasury / Oracle balance monitoring |
| Database Pool | db_pool_connections / db_pool_size, db_pool_waiting | Database connection pool stats |

## Alerts: зведення

| ID | Rule | Severity | Поріг |
|----|------|----------|-------|
| sn-alert-partition-maintenance-failed | partition maintenance failures > 0 за 24h | critical | 0m |
| sn-alert-web3-queue-critical | web3_critical queue > 100 jobs | critical | 5m |
| sn-alert-fraud-detected | fraud rate > 0/s | critical | 2m |
| sn-alert-oracle-balance-critical | oracle_balance_ratio < 0.2 | critical | 5m |
| sn-alert-panic-replay | panic replay > 0.1/s | critical | 2m |
| sn-alert-rpc-errors | rpc_errors > 10/хв | warning | 2m |
| sn-alert-sidekiq-latency | queue latency > 300s | warning | 5m |
| sn-alert-circuit-breaker | circuit_breaker_open == 1 | warning | 2m |
| sn-alert-cluster-entropy | cluster_entropy < 0.65 | warning | 30m |
| sn-alert-acoustic-overflow | acoustic_overflow rate > 0 | warning | 5m |
| sn-alert-tinyml-threshold-invalid | tinyml_threshold_invalid_reports rate(15m) > 0 (FW.18b) | warning | 5m |
| sn-alert-oracle-balance-warning | oracle_balance_ratio < 1.0 | info | 15m |
| sn-alert-db-pool-saturation | db_pool_waiting > 5 | info | 2m |
| sn-alert-w3bstream-fallback | w3bstream SHA256 fallback > 0 | info | 5m |

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
