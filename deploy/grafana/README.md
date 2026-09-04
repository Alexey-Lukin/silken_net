# Grafana IaC — SilkenNet

Infrastructure-as-Code конфіги для Grafana Cloud. Замінюють ручне налаштування в UI (S2.2/S2.3).

## Структура

```
deploy/grafana/
├── dashboards/
│   └── silkennet-overview.json   # Головний дашборд (склад — таблиця нижче, не число тут)
├── alerts/
│   └── silkennet-alerts.yaml     # alert rules (P0/P1/P2)
└── import.rb                     # one-command імпорт обох артефактів
```

## Імпорт — одна команда

```bash
# Перевірка артефактів без credentials (нічого не шле):
ruby deploy/grafana/import.rb --dry-run

# Імпорт (service-account token із роллю Editor+). Живий SA — `silkennet-import-rb`,
# Editor, expiry 2026-11-28 (заведено 2026-08-30): годинник, що цокає без нашого коміту —
# після строку --verify і імпорт мовчки віддадуть 401; перевидати токен ДО того.
GRAFANA_URL=https://<stack>.grafana.net \
GRAFANA_API_TOKEN=<token> \
  ruby deploy/grafana/import.rb

# Звірка живого стека проти IaC — READ-ONLY, жодного запису:
GRAFANA_URL=https://<stack>.grafana.net \
GRAFANA_API_TOKEN=<token> \
  ruby deploy/grafana/import.rb --verify
```

`--verify` відповідає на питання, яке доти адресувалось ОКУ: чи всі правила
справді сіли, чи привʼязався datasource (плейсхолдер, що доїхав живим, дає
правило, яке не спрацює НІКОЛИ), і чи немає в стеку правил, **створених повз
репо** — зворотний дрейф, якого наступний імпорт не чіпає, бо upsert іде
per-uid. Оголошені стелі режиму (він не судить ПРАВИЛЬНІСТЬ порогів, не читає
silences і не перевіряє contact point) стоять у шапці самої гілки в `import.rb`;
read-only тримає не обіцянка, а спека `spec/deploy/grafana_alerts_spec.rb`.

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
| Treasury / Oracle | oracle_balance_ratio, oracle_balance by network+signer (INF.22 per-signer: Polygon minter/slasher + activation-gated aux) | Treasury / Oracle balance monitoring |
| Database Pool | db_pool_connections / db_pool_size, db_pool_waiting | Database connection pool stats |
| 🗂️ Partition Growth [ARCH.70] | partitions by table, partitioned_table_bytes by table, partition_sample_timestamp_seconds (свіжість), partition_default_occupied (поломка, не ріст) | Крива росту, на якій ухвалюється ⚖️ ширини вікна дропу — читати з поправкою 06_03 §2.8 |
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
| sn-alert-insurance-reserve-hold | insurance_reserve_hold increase[1h] > 0 (INS.2 gate спинив емісію; ЄДИНИЙ канал — алерт безкластерний) | critical | 0m |
| sn-alert-panic-replay | panic replay > 0.1/s | critical | 2m |
| sn-alert-scrape-target-down | min by (slot, process) up{job="silken_net_scraper"} < 1 (5 таргетів: 3 production + 2 canopy; NoData→Alerting = Alloy впав) | critical | 5m |
| sn-alert-gateway-faulty | gateways_faulty > 0 (dead-man switch ARCH.54) | critical | 5m |
| sn-alert-chain-audit-drift | chain_audit_delta > 0.0001 (DB vs on-chain SCC drift [G2]) | critical | 15m |
| sn-alert-trees-silent | trees_silent > 0 (дерево замовкло — per-tree field_audit) | warning | 30m |
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
| sn-alert-hadron-kyc-backlog | hadron_kyc_pending_depth sustained[6h] (бенефіціари, яких мінт скіпає щоцикл — KYC-провайдера не обрано; ARCH.118 / BIZ.20 — auto-heal НЕМОЖЛИВИЙ) | warning | 30m |
| sn-alert-m2m-nonce-fallback | m2m_nonce_fallback increase[1h] > 0 (Redis→DB, S6.1) | info | 0m |
| sn-alert-qatt-nonce-fallback | qatt_nonce_fallback increase[1h] > 0 (Redis→DB на батч-стрімі, S6.1) | info | 0m |
| sn-alert-telemetry-volume-approaching | telemetry_processed increase[30d] > 30M (scale-двигун ⚖️ E.37) | info | 1h |
| sn-alert-partition-count-unbounded | max(partitions) > 24 ЛИСТІВ (⚠️ НЕ місяців: серед листів DEFAULT + створений наперед наступний місяць, тобто на 1-2 менше — 06_03 §2.8); механізму дропу немає — ⚖️ ARCH.70 | info | 1h |
| sn-alert-partitioned-table-growth | sum(partitioned_table_bytes) > 30 ГБ (60% початкового `db_disk_size_gb`; ціна, не crash — autoresize) | info | 1h |
| sn-alert-partition-sampler-stale | time() − partition_sample_timestamp > 48h (два ARCH.70-алерти читають ЗАМЕРЗЛЕ значення) | info | 1h |
| sn-alert-partition-default-occupied | max(partition_default_occupied) > 0 — DEFAULT-лист непорожній, створення партиції його місяця заблоковано НАЗАВЖДИ; ретраї не лікують → рунбук 06_06 §5.5 | warning | 1h |

> Повний SSOT правил — сам `alerts/silkennet-alerts.yaml`; ця таблиця — людська шпаргалка, і `import.rb` рахує з yaml, не звідси. Числа правил тут свідомо немає: воно протухало б тихо при кожному додаванні, а єдиний, хто його реально знає, друкує його на імпорті.

## Notification channel

**Кодифіковано в `import.rb` (крок 5)** — той самий захід, off-by-default через ENV.
Без цього alert rules firing-ять у нікуди (O3-MUST), тож канал — частина One-Command,
а не ручний хвіст. Задай канал (email / Telegram / обидва) і перезапусти import:

```bash
# Email:
GRAFANA_URL=… GRAFANA_API_TOKEN=… \
ALERT_CONTACT_EMAIL=ops@silkennet.com \
  ruby deploy/grafana/import.rb

# Telegram (обидва обов'язкові — half-config → fail-fast):
… ALERT_CONTACT_TELEGRAM_TOKEN=<bot-token> ALERT_CONTACT_TELEGRAM_CHATID=<chat-id> \
  ruby deploy/grafana/import.rb
```

Скрипт створює contact point `silkennet-oncall` (ідемпотентно, per-(name,type) upsert) і
маршрутизує **root notification policy** на нього (`GET → mutate receiver+timing → PUT` —
наявні дочірні routes зберігаються). Timing з дефолтами (overridable ENV):
`ALERT_GROUP_WAIT=30s` · `ALERT_GROUP_INTERVAL=5m` · `ALERT_REPEAT_INTERVAL=4h`.
Ім'я — `ALERT_CONTACT_NAME` (дефолт `silkennet-oncall`).

Без жодного `ALERT_CONTACT_*` крок 5 пропускається (warn), решта імпорту без змін —
`--dry-run` показує, який канал буде провіжнено (і ловить half-Telegram ще до live).
