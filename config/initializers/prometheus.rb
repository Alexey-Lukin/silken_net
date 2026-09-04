# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 📊 PROMETHEUS METRICS (Observability for Grafana/Prometheus)
# = ===================================================================
# Lightweight metrics exporter using the official prometheus-client gem.
# Exposes custom business metrics for the SilkenNet platform:
#
# - Sidekiq web3 queue size and latency
# - Web3 RPC error rates (by network/type)
# - Financial: SCC minted, locked funds, slashed tokens
# - IoT: CoAP telemetry ingest rate and fraud detection
#
# The /metrics endpoint is secured via PrometheusCollector middleware
# (IP allowlist + HTTP Basic Auth). See app/middleware/prometheus_collector.rb.

require "prometheus/client"

module SilkenNet
  module Metrics
    REGISTRY = Prometheus::Client::Registry.new

    # -----------------------------------------------------------------------
    # 💎 FINANCIAL METRICS (Web3 / Tokenomics)
    # -----------------------------------------------------------------------

    # Total SCC tokens minted (monotonic counter)
    SCC_MINTED_TOTAL = REGISTRY.counter(
      :silkennet_scc_minted_total,
      docstring: "Total SCC (SilkenCarbonCoin) tokens minted",
      labels: [ :token_type ]
    )

    # Mint attempts vs successes → the "≥80% mint success during a single
    # chain outage" SLO (docs/06_08 §2.4) becomes measurable as
    # silkennet_mint_success_total / silkennet_mint_attempts_total (per token_type).
    MINT_ATTEMPTS_TOTAL = REGISTRY.counter(
      :silkennet_mint_attempts_total,
      docstring: "Mint transactions attempted by BlockchainMintingService (SLO denominator)",
      labels: [ :token_type ]
    )

    MINT_SUCCESS_TOTAL = REGISTRY.counter(
      :silkennet_mint_success_total,
      docstring: "Mint transactions successfully broadcast to mempool — status→sent (SLO numerator)",
      labels: [ :token_type ]
    )

    # [DOC-T.89] Ефективна ставка Dynamic Tax ≠ оголошені 2%: податок стягується
    # ЛИШЕ в `batchMint`, а одиночний `mint()` його не застосовує — і в одинака
    # веде щонайменше вісім детермінованих каналів (urgent-група розміром 1,
    # хвостовий слайс, KYC-зріз батча, poisoned-одинаки бінарного пошуку,
    # pre-broadcast fallback, страхова виплата через `call(id)`, existing-група
    # після ретраю, fail-open при RPC-збої). Знаменник уже стоїть:
    # `SCC_MINTED_TOTAL` інкрементується СУМОЮ, не штуками [INF.26], тож
    # `tax_collected / scc_minted` є готовим відношенням в одних одиницях.
    # ⚠️ Інкремент — ТІЛЬКИ після успішного broadcast: `build_batch_arrays`
    # рахує `tax_total` заново на КОЖНОМУ рівні бінарного пошуку, тож інкремент
    # усередині нього дав би 2–14× на тому самому наборі при жодній реальній
    # відправці.
    TAX_COLLECTED_TOTAL = REGISTRY.counter(
      :silkennet_dynamic_tax_collected_total,
      docstring: "Dynamic Tax actually broadcast to DAO_TREASURY (SCC) — numerator of the EFFECTIVE tax rate " \
                 "[DOC-T.89; diagnostic tier: no consumer until the first live batchMint — its denominator scc_minted_total is ALREADY on a panel, so only the ratio waits, and taxing? gates the increment to underfunded-pool carbon_coin batches]",
      labels: [ :token_type ]
    )

    # [ARCH.94] Дві метрики проти класу «емісія зупинилась, і ніхто не дізнався».
    # Обидві потрібні, бо відповідають на РІЗНІ питання й ловлять протилежні
    # режими відмови:
    #
    # (1) COUNTER — «чи падали спроби на рівні гаманця». `EvaluateTreeBatchWorker`
    #     ловить виняток кожного гаманця в `rescue StandardError`, рахує в
    #     `stats[:errors]` і викидає в лог-рядок; джоба вертає успіх, retry нема,
    #     DeadSet порожній. Саме так P1-дефект (сайзинг від gross-балансу проти
    #     гарда по net) прожив непоміченим.
    #
    # (2) GAUGE — «чи є гаманці, які МАЛИ Б мінтити й не мінтять». Він несучий
    #     окремо від лічильника: відмова, що не кидає винятку ЗОВСІМ (порожній
    #     селектор, знятий cron, помилковий фільтр), лишає лічильник у нулі —
    #     нуль спроб для SLO-відношення невідрізненний від спокою, бо алерт
    #     `sn-alert-mint-slo-breach` несе гард `and attempts > 0`. Форма —
    #     глибина застряглої популяції, за прецедентом `hadron_kyc_pending_depth`
    #     [ARCH.65]: «нуль подій» лікується лічильником СТАНУ, не подій.
    MINT_CHUNK_ERRORS_TOTAL = REGISTRY.counter(
      :silkennet_mint_chunk_errors_total,
      docstring: "Per-wallet mint failures swallowed by EvaluateTreeBatchWorker (job still reports success)"
    )

    MINT_ELIGIBLE_UNMINTED_DEPTH = REGISTRY.gauge(
      :silkennet_mint_eligible_unminted_depth,
      docstring: "Wallets over the emission threshold that produced no mint in the last cycle (stall detector)"
    )

    # Total tokens slashed (monotonic counter)
    SCC_SLASHED_TOTAL = REGISTRY.counter(
      :silkennet_scc_slashed_total,
      docstring: "Total tokens slashed (burned due to cluster stress)"
    )

    # [ARCH.45] Slash attempts vs successes → slash success-rate SLO (06_03 §2.8),
    # вимірюване як silkennet_slash_success_total / silkennet_slash_attempts_total.
    SLASH_ATTEMPTS_TOTAL = REGISTRY.counter(
      :silkennet_slash_attempts_total,
      docstring: "Slash transactions attempted by BlockchainBurningService (SLO denominator)"
    )

    SLASH_SUCCESS_TOTAL = REGISTRY.counter(
      :silkennet_slash_success_total,
      docstring: "Slash transactions successfully broadcast — status→sent (SLO numerator)"
    )

    # [ARCH.45] Solana batch payout attempts vs successes → payout success-rate SLO (06_03 §2.8).
    SOLANA_PAYOUT_ATTEMPTS_TOTAL = REGISTRY.counter(
      :silkennet_solana_payout_attempts_total,
      docstring: "Solana batch payouts attempted by BatchPayoutService (SLO denominator)"
    )

    SOLANA_PAYOUT_SUCCESS_TOTAL = REGISTRY.counter(
      :silkennet_solana_payout_success_total,
      docstring: "Solana batch payouts successfully broadcast — status→sent (SLO numerator)"
    )

    # [INS.1] Insurance payout attempts vs successes → insurance payout success-rate SLO (06_03 §2.8).
    # Закриває observability-діру: на відміну від slash/Solana, страхова виплата раніше SLO не мала.
    INSURANCE_PAYOUT_ATTEMPTS_TOTAL = REGISTRY.counter(
      :silkennet_insurance_payout_attempts_total,
      docstring: "Parametric insurance payouts attempted by InsurancePayoutWorker (SLO denominator)"
    )

    INSURANCE_PAYOUT_SUCCESS_TOTAL = REGISTRY.counter(
      :silkennet_insurance_payout_success_total,
      docstring: "Parametric insurance payouts BROADCAST — Etherisc claim sent / internal mint status→sent (SLO numerator)"
    )

    # [INS.2/ARCH.82] Reserve-gate HOLD — виплату зупинено казначейською політикою.
    # ⚖️ founder 2026-08-14: цьому родові алертів дається Grafana-канал (не орг-поверхня) —
    # HOLD означає «емісія зупинена», і читач цього оператор, не лісник.
    #
    # 🔴 Чому окрема метрика, хоча HOLD і так додає рядок у `manual_review`: той gauge
    # НЕ РОЗРІЗНЯЄ причин, а відповіді на них протилежні — reserve-hold це нормальна
    # робота політики (звірити подію, можливо підняти поріг), а double-spend-лімбо
    # (ARCH.45) це підозра на втрачені кошти. Один сигнал на два питання = підміна виміру.
    #
    # ⚠️ Тракт сьогодні інертний (обидва пороги `SystemParameter` default 0 → gate завжди
    # `:ok`), тож лічильник лишатиметься нулем до калібрування [INS.2] у деплой-день SEC.1.
    # Канал заводиться ПЕРЕД озброєнням навмисно: інакше перший же HOLD став би невидимим
    # і незакриваним одночасно.
    INSURANCE_RESERVE_HOLD_TOTAL = REGISTRY.counter(
      :silkennet_insurance_reserve_hold_total,
      docstring: "Internal-mode insurance payouts held by the INS.2 reserve gate, by breach reason",
      labels: [ :reason ]
    )

    # Web3 RPC errors (labeled by network and error type)
    RPC_ERRORS_TOTAL = REGISTRY.counter(
      :silkennet_rpc_errors_total,
      docstring: "Total Web3 RPC errors",
      labels: [ :network, :error_type ]
    )

    # -----------------------------------------------------------------------
    # 📡 IoT / TELEMETRY METRICS
    # -----------------------------------------------------------------------

    # Total telemetry chunks processed (monotonic counter)
    TELEMETRY_PROCESSED_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_processed_total,
      docstring: "Total telemetry chunks processed by TelemetryUnpackerService"
    )

    # Telemetry fraud/anomaly detections (monotonic counter)
    TELEMETRY_FRAUD_DETECTED_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_fraud_detected_total,
      docstring: "Total telemetry packets rejected (sensor noise, unknown DID, tamper)"
    )

    # [SEC.10] Panic packets rejected as replay (Frame Counter nonce collision).
    # Сторожовий пес панічного каналу — кожен сплеск тут означає або
    # legitimate retransmission (LoRa mesh duplicate) або replay-attack.
    # Grafana alert при різкому стрибку → можливий attacker injection.
    PANIC_REPLAY_REJECTED_TOTAL = REGISTRY.counter(
      :silkennet_panic_replay_rejected_total,
      docstring: "Panic packets rejected as replay via SEC.10 Frame Counter SETNX nonce"
    )

    # [FW.2] AES-128-CCM packet decrypted and MIC verified successfully.
    # Should track ~1:1 with TELEMETRY_PROCESSED_TOTAL on the CCM code path
    # once `TELEMETRY_CCM_ENABLED=true` ships fleet-wide.
    TELEMETRY_CCM_DECRYPT_OK_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_ccm_decrypt_ok_total,
      docstring: "FW.2 CCM packets successfully decrypted with valid MIC " \
                 "[FW.2; diagnostic tier: no alert until TELEMETRY_CCM_ENABLED ships fleet-wide — the consumer is its ~1:1 ratio against telemetry_processed_total]"
    )

    # [FW.2] CCM MIC verification failed — wrong key, tampered ciphertext,
    # mutilated AAD, or wrong DID/FrameCounter pairing. Any nonzero rate
    # in production is a security signal worth paging on.
    TELEMETRY_CCM_MIC_FAIL_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_ccm_mic_fail_total,
      docstring: "FW.2 CCM packets rejected due to MIC verification failure"
    )

    # [FW.2] Per-DID Frame Counter not strictly monotonic — either replay
    # of an already-seen FC or out-of-order delivery beyond what mesh
    # buffering should produce. Grafana alert: rising rate > 0.1% of all
    # CCM packets/min → attacker injection or device clock reset event.
    TELEMETRY_CCM_FC_REPLAY_REJECTED_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_ccm_fc_replay_rejected_total,
      docstring: "FW.2 CCM packets rejected because per-DID Frame Counter was not strictly increasing"
    )

    # [FW.18b] Telemetry packets whose TTL-byte high bits carry a nonzero
    # rejected-OTA-thresholds counter (firmware/common/ttl_byte.h).
    # БЕЗ per-DID мітки свідомо: cardinality budget (06_03 §2.9) тримає
    # реєстр bounded — per-tree атрибуція йде warn-логом (патерн FW.22
    # acoustic overflow). rate() > 0 = на якомусь дереві корумпований RTC
    # або зловмисний OTA-payload; конкретний DID — у логах поруч.
    TINYML_THRESHOLD_INVALID_REPORTS_TOTAL = REGISTRY.counter(
      :silkennet_tinyml_threshold_invalid_reports_total,
      docstring: "FW.18b telemetry packets reporting a nonzero rejected-OTA-thresholds counter (per-DID attribution in logs)"
    )

    # [FW.42] CCM diag-байт (wire-rev2 byte 18, fauna_skip bit): Солдат
    # пропустив fauna-сесію через низький Vcap (брауноут-захист,
    # 03_03 §10.4). Без per-DID мітки — той самий cardinality-патерн, що
    # TINYML_THRESHOLD_INVALID: дерево атрибутується warn-логом. Стійкий
    # rate() > 0 = енергодефіцит кластера (зима / деградація EDLC).
    FAUNA_SKIP_REPORTS_TOTAL = REGISTRY.counter(
      :silkennet_fauna_skip_reports_total,
      docstring: "FW.42 telemetry packets reporting a fauna session skipped on low Vcap (per-DID attribution in logs)"
    )

    # [FW.2] CCM diag-байт (fc_degraded bit): інваріант I-HW (Flash
    # high-water > усіх переданих FC) тимчасово втрачено — Flash відмовляв
    # багато КЕНОЗИСІВ поспіль. Будь-який ненульовий rate() — деградація
    # nonce-гарантії конкретного вузла (DID у warn-лозі поруч).
    FW2_FC_DEGRADED_REPORTS_TOTAL = REGISTRY.counter(
      :silkennet_fw2_fc_degraded_reports_total,
      docstring: "FW.2 telemetry packets reporting a lost FC high-water invariant (Flash refusing writes; per-DID attribution in logs)"
    )

    # -----------------------------------------------------------------------
    # ⚙️ SIDEKIQ QUEUE METRICS (Gauges — sampled at scrape time)
    # -----------------------------------------------------------------------
    # [PLAN 1.3]: Renamed from WEB3_QUEUE_* to SIDEKIQ_QUEUE_* to reflect
    # monitoring ALL 9 queues (uplink, alerts, critical, downlink, default,
    # web3_critical, web3, web3_low, low), not just web3.

    # Sidekiq queue size (gauge — set on each scrape via collector callback)
    SIDEKIQ_QUEUE_SIZE = REGISTRY.gauge(
      :silkennet_sidekiq_queue_size,
      docstring: "Current size of a Sidekiq queue",
      labels: [ :queue ]
    )

    # Sidekiq queue latency in seconds (gauge — oldest job age)
    SIDEKIQ_QUEUE_LATENCY = REGISTRY.gauge(
      :silkennet_sidekiq_queue_latency_seconds,
      docstring: "Latency (age of oldest job) in a Sidekiq queue",
      labels: [ :queue ]
    )

    # [ARCH.45] Sidekiq DeadSet size — money-path job, що вичерпав retry, осідає тут зі
    # stranded-станом (locked funds / pending tx) і потребує операторської уваги. Без цього
    # сигналу застрягла виплата/burn лишалися б непоміченими (06_03 §2.8 — money-path SLO).
    SIDEKIQ_DEAD_SET_SIZE = REGISTRY.gauge(
      :silkennet_sidekiq_dead_set_size,
      docstring: "Current size of the Sidekiq DeadSet (jobs that exhausted all retries)"
    )

    # [G1] Money-path limbo видимість. `manual_review` = double-spend guard (кошти заблоковані,
    # on-chain-стан невідомий — потребує людської звірки); `locked_limbo` = growth_points у
    # locked_balance під незавершеними :sent/:manual_review tx старше 1h. Обидва невидимі без
    # цих gauge — перша ж грошова аномалія приземлюється у manual_review тихо. Семплить лише
    # TreasuryMonitorWorker (15-хв прохід). 06_03 §2.8 money-path SLO.
    BLOCKCHAIN_MANUAL_REVIEW_DEPTH = REGISTRY.gauge(
      :silkennet_blockchain_manual_review_depth,
      docstring: "Count of BlockchainTransaction rows stuck in :manual_review (double-spend guard queue)"
    )
    BLOCKCHAIN_LIMBO_LOCKED_TOTAL = REGISTRY.gauge(
      :silkennet_blockchain_limbo_locked_total,
      docstring: "Sum of locked_points on unsettled (:sent/:manual_review) tx older than 1h (funds in limbo)"
    )
    # [ARCH.65] Hadron-KYC backlog видимість. `HadronKycVerificationWorker` exhaust →
    # `hadron_kyc_status` "pending" назавжди → тихий mint-skip бенефіціара. Без gauge
    # оператор не бачить, скільки KYC застрягло під час Hadron-простою. Семплить
    # `HadronKycReverifyWorker` (:50 щогодини). 06_03 §2.8 money-path SLO.
    HADRON_KYC_PENDING_DEPTH = REGISTRY.gauge(
      :silkennet_hadron_kyc_pending_depth,
      docstring: "Count of Wallet+Organization rows with hadron_kyc_status=pending (KYC backlog gating mint)"
    )
    # [G2] db↔on-chain drift — ChainAuditService рахує |Σmints−Σburns − totalSupply|; без gauge
    # drift невидимий, поки хтось не відкриє сторінку аудиту.
    CHAIN_AUDIT_DELTA = REGISTRY.gauge(
      :silkennet_chain_audit_delta,
      docstring: "Absolute delta between DB SCC total (mints−burns) and on-chain totalSupply"
    )

    # [ARCH.62] Rolling-1h заминчений обсяг SCC/SFC (money-path defense-in-depth). Per-tx
    # guards + `MAX_SUPPLY`-стеля ловлять поодинокі аномалії, але АГРЕГАТНИЙ сплеск обсягу
    # (firmware/pipeline-баг чи тихо-зловжитий MINTER-ключ) не ловить ніщо — `chain_audit_delta`
    # мовчить, коли DB і chain згодні на аномальному числі. Семплить Treasury::MonitorService
    # (15-хв money-path прохід). Детектор алертить лише коли SystemParameter-поріг увімкнено —
    # gauge завжди живий для видимості обсягу. 05_02 §Модель довіри / 06_03 §2.8.
    MINT_VOLUME_WINDOW_SCC = REGISTRY.gauge(
      :silkennet_mint_volume_window_scc,
      docstring: "SCC/SFC BROADCAST (sent_at) in the trailing 1h window (ARCH.62 volume-anomaly detector input)",
      labels: [ :token_type ]
    )

    # [ARCH.54 Шар 0] Dead-man switch Королеви (GatewayStalenessSweepWorker):
    # переходи offline→faulty (counter) + поточний стан флоту (gauges).
    GATEWAYS_OFFLINE_TOTAL = REGISTRY.counter(
      :silkennet_gateways_offline_total,
      docstring: "Total gateway offline transitions detected by the staleness sweeper (queen_offline alerts)"
    )

    GATEWAYS_FAULTY = REGISTRY.gauge(
      :silkennet_gateways_faulty,
      docstring: "Current number of gateways in the faulty state (set on each staleness sweep)"
    )

    GATEWAY_ATTEST_LAPSED = REGISTRY.gauge(
      :silkennet_gateway_attest_lapsed,
      docstring: "Online QATT-capable gateways whose last Ed25519-attested batch is older than the lapse window"
    )

    # [SILENCE-1] Dead-man switch Солдата (TreeStalenessSweepWorker):
    # переходи в аномальну тишу (counter) + поточний стан флоту (gauge).
    TREE_SILENCE_TOTAL = REGISTRY.counter(
      :silkennet_tree_silence_total,
      docstring: "Total tree silence transitions detected by the staleness sweeper (per-tree field_audit escalations) " \
                 "[SILENCE-1; diagnostic tier: no alert until a fleet gives flapping a baseline — the INF.26 verdict (2026-08-30) closed half (a): " \
                 "this counter means NEW silence escalations (dedup'd by the unresolved-field_audit scope), i.e. the future flapping signal; " \
                 "standing silence is already read by sn-alert-trees-silent (gauge), and sn-alert-gateway-flapping is the shape to copy]"
    )

    TREES_SILENT = REGISTRY.gauge(
      :silkennet_trees_silent,
      docstring: "Current number of active trees silent beyond the silence threshold (set on each staleness sweep)"
    )

    # [ARCH.58] Safety-sweep актуаторів (ActuatorSafetySweepWorker). СВІДОМО
    # лише counter, без gauge-двійника сусідів вище: цей sweep стан УСУВАЄ
    # (повертає актуатор у `idle` тим самим проходом), тож «скільки зараз
    # залипло» читалось би вічним нулем — на відміну від `gateways_faulty`,
    # де faulty-стан персистентний. Сліпе копіювання сусіда дало б мертву
    # метрику.
    ACTUATOR_STUCK_RECOVERED_TOTAL = REGISTRY.counter(
      :silkennet_actuator_stuck_recovered_total,
      docstring: "Actuators found recorded active past their command window and reset by the safety sweep " \
                 "[ARCH.58; diagnostic tier: no alert until a physical actuator layer exists (ARCH.58 residual — no actuator firmware today). " \
                 "INF.26 verdict 2026-08-30: the «recovered when deactivate! fails» suspicion is CLOSED by code — the increment sits AFTER " \
                 "the recover! transaction, so a failed deactivate! rolls back and never counts; may_deactivate? is formal on the sweep's active-only scope]",
      labels: [ :device_type ]
    )

    # [ARCH.34 L3] Helium SOS intake (HeliumSosWorker):
    # accepted / unknown_dev_eui / did_mismatch / malformed.
    HELIUM_SOS_RECEIVED_TOTAL = REGISTRY.counter(
      :silkennet_helium_sos_received_total,
      docstring: "Queen SOS frames received via the Helium webhook, by processing outcome " \
                 "(worker: accepted/unknown_dev_eui/did_mismatch/malformed; controller: rejected_auth/rejected_params — " \
                 "the controller pair added 2026-08-30 [INF.26]: a rotated HELIUM_WEBHOOK_SECRET otherwise silenced the SOS channel invisibly)",
      labels: [ :outcome ]
    )

    # Legacy aliases for backward compatibility with existing Grafana dashboards.
    WEB3_QUEUE_SIZE = SIDEKIQ_QUEUE_SIZE
    WEB3_QUEUE_LATENCY = SIDEKIQ_QUEUE_LATENCY

    # -----------------------------------------------------------------------
    # 🔗 DATABASE CONNECTION POOL METRICS (Gauges — Wiki 04_01 Blocker Fix)
    # -----------------------------------------------------------------------
    # Моніторинг Connection Pool для виявлення насичення під час масової
    # телеметрії. Критично при Sidekiq concurrency=15 та pessimistic locks.

    # Total pool size (max connections per database)
    DB_POOL_SIZE = REGISTRY.gauge(
      :silkennet_db_pool_size,
      docstring: "Maximum number of connections in the database pool",
      labels: [ :database ]
    )

    # Currently active (checked out) connections
    DB_POOL_CONNECTIONS = REGISTRY.gauge(
      :silkennet_db_pool_connections,
      docstring: "Number of active (checked out) database connections",
      labels: [ :database ]
    )

    # Idle connections available in the pool
    DB_POOL_IDLE = REGISTRY.gauge(
      :silkennet_db_pool_idle,
      docstring: "Number of idle database connections in the pool",
      labels: [ :database ]
    )

    # Threads waiting for a connection checkout
    DB_POOL_WAITING = REGISTRY.gauge(
      :silkennet_db_pool_waiting,
      docstring: "Number of threads waiting for a database connection",
      labels: [ :database ]
    )

    # -----------------------------------------------------------------------
    # 💰 TREASURY / ORACLE WALLET METRICS (Multi-chain balance monitoring)
    # -----------------------------------------------------------------------
    # Відстежує баланси Oracle wallets на всіх мережах.
    # Критично для масштабування: при мільйонах дерев витрати газу зростають пропорційно.

    # Oracle wallet balance in native currency (MATIC, SOL, CELO, ETH).
    # `signer`-вимір [INF.22]: на одній мережі кілька dedicated-підписантів (Polygon:
    # minter/slasher/aux) — без нього два записи колізять на спільному network-лейблі.
    ORACLE_BALANCE = REGISTRY.gauge(
      :silkennet_oracle_balance,
      docstring: "Oracle wallet balance in native currency (wei/lamports)",
      labels: [ :network, :signer ]
    )

    # Oracle wallet balance as ratio to minimum threshold (< 1.0 = critical)
    ORACLE_BALANCE_RATIO = REGISTRY.gauge(
      :silkennet_oracle_balance_ratio,
      docstring: "Oracle balance as ratio to minimum threshold (below 1.0 = critical)",
      labels: [ :network, :signer ]
    )

    # 🔴 [SEC.22] ФЛОАТ ВИПЛАТ — окрема метрика, і окремість тут НЕСУЧА, не стильова.
    # `ORACLE_BALANCE` оголошений «in native currency (wei/lamports)», а це SPL-токен
    # із власними decimals (USDC = 6): покласти їх на одну серію означало б змішати дві
    # шкали під спільним іменем — рівно клас «один токен, два домени».
    #
    # 🔑 Чому вона взагалі існує: присуд SEC.22 прийняв Solana-ключ як bounded-blast
    # («вибух дорівнює ФЛОАТУ гаманця, а не емісії»), але саме ФЛОАТ ніхто не міряв —
    # монітор стежив лише SOL-баланс, тобто ГАЗ. Тобто підстава присуду не мала
    # вимірювача, а «bounded» без числа є твердженням про надію.
    #
    # ⚠️ ЯРУС — ДІАГНОСТИЧНИЙ, і це ОГОЛОШЕНО, а не пропущено [INF.26, ⚖️ 2026-08-29]:
    # алерт-правила тут свідомо немає, бо ПОРІГ («скільки флоату прийнятно тримати»)
    # є deploy-day присудом разом із сусідніми INS.2-числами. Прилад мусить стояти
    # РАНІШЕ за число — інакше присуд про поріг ухвалюватимуть без величини, яку він
    # обмежує. Дротування правила = момент, коли число ратифіковано.
    PAYOUT_FLOAT_BALANCE = REGISTRY.gauge(
      :silkennet_payout_float_balance,
      docstring: "Hot-wallet payout float in token units (SPL/ERC-20) — the actual blast ceiling of a compromised payout key, NOT gas [SEC.22; diagnostic tier: no alert until the threshold is ratified]",
      labels: [ :network, :token ]
    )

    # Treasury monitor errors (network unreachable, RPC timeout)
    TREASURY_CHECK_ERRORS_TOTAL = REGISTRY.counter(
      :silkennet_treasury_check_errors_total,
      docstring: "Total treasury monitoring RPC errors",
      labels: [ :network, :signer, :error_type ]
    )

    # -----------------------------------------------------------------------
    # 🔥 WORKER-SPECIFIC METRICS (Gap Analysis — S2.4)
    # -----------------------------------------------------------------------

    # Slashing events by reason (fraud, cluster_stress, contract_breach)
    SLASHING_EVENTS_TOTAL = REGISTRY.counter(
      :silkennet_slashing_events_total,
      docstring: "Total slashing (burn) events by reason",
      labels: [ :reason ]
    )

    # [INF.26] Супутниковий вердикт dClimate за ТЕРМІНАЛЬНИМ результатом. Вісь
    # грошова обабіч: `verified` веде в `InsurancePayoutWorker`, `rejected_fraud`
    # ставить у чергу НЕЗВОРОТНЕ спалення (`BurnCarbonTokensWorker`), а
    # `inconclusive` паркує рішення на людину/DAO. До 2026-08-29 у неї не було
    # ані метрики, ані алерту, ані панелі.
    # 🔴 Дім — `EwsAlert.after_update_commit`, НЕ сайт у сервісі: термінальних
    # писачів `satellite_status` чотири, і один із них (`sidekiq_retries_exhausted`)
    # живе у воркері, тобто поза сервісом узагалі. Попередня спроба лічити цю вісь
    # стояла в `DclimateVerificationWorker` і саме тому рахувала ПІДМНОЖИНУ.
    DCLIMATE_VERIFICATION_TOTAL = REGISTRY.counter(
      :silkennet_dclimate_verification_total,
      docstring: "Total dClimate satellite verdicts by terminal result",
      labels: [ :result ]
    )

    # OTA firmware chunks sent to field devices
    OTA_CHUNKS_SENT_TOTAL = REGISTRY.counter(
      :silkennet_ota_chunks_sent_total,
      docstring: "OTA firmware chunk DELIVERIES served to polling gateways — re-polled chunks count again by design " \
                 "(stateless chunk-server), so this measures downlink traffic, never unique-chunk progress " \
                 "[INF.26 verdict 2026-08-30; diagnostic tier: no alert until the first field OTA campaign — the flow is episodic, " \
                 "a threshold over an episodic series is noise; failure-side alerting would hang off handle_chunk_failure, not off sends. " \
                 "The dead push-era write site leaves with OtaTransmissionWorker itself (FW.60 superseded, bench:coap-gated removal)]",
      labels: [ :firmware_version ]
    )

    # [INF.26] «created», а НЕ «dispatched»: дім інкременту — `EwsAlert.after_create_commit`,
    # тобто лічиться СТВОРЕННЯ, один сайт на застосунок; доти сайт стояв у dClimate-воркері
    # під `if result` і лічив одну підмножину з тринадцяти сайтів створення.
    # ⚠️ Доставка (ARCH.60 — пошта, Telegram) реальна й лічильника НЕ має, тож ім'я мусить
    # називати рівно ту подію, яку воно рахує: сплутати їх тепер значить вигадати число.
    EWS_ALERTS_TOTAL = REGISTRY.counter(
      :silkennet_ews_alerts_total,
      docstring: "Total EWS alerts created (fire, drought, pest, storm) " \
                 "[INF.26; diagnostic tier: no alert until a fleet establishes a baseline rate — «spike» has no threshold over a zero baseline, and each alert kind already carries its own rule]",
      labels: [ :alert_type ]
    )

    # Chainlink oracle dispatch latency (histogram for percentile analysis)
    ORACLE_DISPATCH_DURATION = REGISTRY.histogram(
      :silkennet_oracle_dispatch_duration_seconds,
      docstring: "Chainlink oracle dispatch ATTEMPT latency in seconds — successful and failed alike [INF.26]; circuit-open refusals are excluded on purpose (our own breaker answers in microseconds and would drag p99 down)",
      buckets: [ 0.5, 1, 2.5, 5, 10, 30, 60 ]
    )

    # CoAP UDP packets received by the daemon. Status values split by owner
    # process and never overlap: daemon-level (coap container — enqueued /
    # malformed / unknown_route / oversized) vs worker-level (job container —
    # success / decrypt_error / unknown_device / attest_*). The exhaustive
    # list lives at the call sites (coap_listener + UnpackTelemetryWorker);
    # sum by (status) across scrape targets is the honest full picture.
    # 🔴 `oversized` IS A BOUNDARY COUNTER, AND MISREADING IT COSTS AN INVESTIGATION [INF.17]:
    # it means the KERNEL truncated an oversized UDP datagram before we ever saw it. Without
    # this status the same event surfaces one layer up as a MIC verification failure — i.e. it
    # masquerades as FRAUD, and an operator would hunt an attacker for what is a size limit.
    # The pair is the point: a rise in `oversized` with flat `attest_*` is a sender/MTU problem;
    # a rise in `attest_*` with flat `oversized` is the security signal. Never fold them.
    COAP_PACKETS_RECEIVED_TOTAL = REGISTRY.counter(
      :silkennet_coap_packets_received_total,
      docstring: "Total CoAP UDP packets received by the telemetry daemon",
      labels: [ :status ]
    )

    # Lorenz attractor computation duration (BigDecimal, 250 iterations)
    LORENZ_COMPUTATION_DURATION = REGISTRY.histogram(
      :silkennet_lorenz_computation_duration_seconds,
      docstring: "Lorenz attractor server-side computation time (Float IEEE-754, 250 iterations) " \
                 "[INF.23; diagnostic tier: no alert until a real load profile exists — dev numbers are not capacity (bottleneck-class inversion, 06_08 §2.4)]",
      buckets: [ 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5 ]
    )

    # [S6.6] Missed Ethereum L1 anchor weeks detected
    ANCHOR_MISSED_WEEKS_TOTAL = REGISTRY.counter(
      :silkennet_anchor_missed_weeks_total,
      docstring: "Total missed Ethereum L1 anchor weeks detected (gap > 8 days)"
    )

    # [ARCH.66] Anchor confirmation-lifecycle видимість. stuck_sent_depth закриває сліпу пляму
    # sn-alert-anchor-stalled (той бачить лише «чи БУВ спробуваний broadcast за 8д», НЕ «чи хоч
    # один підтвердився»). Рахує stuck-предикат (EthereumAnchor.stuck_sent), НЕ весь :sent —
    # інакше здоровий anchor у вікні підтвердження тримав би gauge>0 і пейджив щотижня.
    # Семплить Treasury::MonitorService (15-хв — freshness проти restart-обнулення in-process
    # gauge; sweeper-repair окремо hourly). reverted = storeStateRoot revert on-chain
    # (детермінований contract-revert «фінальної печатки» = аномалія, інакше видима лише
    # через 8-денний missed-weeks-лаг).
    ETHEREUM_ANCHOR_STUCK_SENT_DEPTH = REGISTRY.gauge(
      :silkennet_ethereum_anchor_stuck_sent_depth,
      docstring: "Count of EthereumAnchor rows stuck in :sent past the confirmation-poll SLA (ARCH.66)"
    )
    # [ARCH.66] Anchor у :manual_review = «фінальна печатка» broadcast'нута, але не досягла
    # :confirmed за poll-SLA (людська звірка на etherscan). Термінальний, поза sweeper/detect_missed
    # → без цього gauge невидимий (лише 8-денний missed-weeks-лаг ловив би, і то з :confirmed-baseline).
    ETHEREUM_ANCHOR_MANUAL_REVIEW_DEPTH = REGISTRY.gauge(
      :silkennet_ethereum_anchor_manual_review_depth,
      docstring: "Count of EthereumAnchor rows escalated to :manual_review (unconfirmed seal awaiting human check, ARCH.66)"
    )
    ETHEREUM_ANCHOR_REVERTED_TOTAL = REGISTRY.counter(
      :silkennet_ethereum_anchor_reverted_total,
      docstring: "EthereumAnchor storeStateRoot txs that reverted on-chain (ARCH.66)"
    )

    # [GOV.1] Governance-параметр відхилено bounds-валідацією sync-воркера
    # (мис-скейл / нонсенс-голос). Ненульове = DAO проголосував значення поза
    # safety-межами → чинним лишилось попереднє, потрібен коригувальний голос.
    GOVERNANCE_PARAM_REJECTED_TOTAL = REGISTRY.counter(
      :silkennet_governance_param_rejected_total,
      docstring: "Governance parameter syncs rejected by bounds validation",
      labels: [ :parameter ]
    )

    # [E.60] Провал звірки archive-цілісності Filecoin/IPFS (sweep-воркер):
    # cid_mismatch = ex-post підміна вмісту; chain_hash_mismatch = розбіжність
    # з локальним hash-ланцюгом. Ненульове = MRV-докази під загрозою → Grafana-алерт.
    FILECOIN_VERIFICATION_FAILURES_TOTAL = REGISTRY.counter(
      :silkennet_filecoin_verification_failures_total,
      docstring: "Filecoin archive integrity verification failures (E.60 sweep)",
      labels: [ :reason ]
    )

    # [MRV.1/ARCH.12] Fail-open обчислення mint-lineage кореня впало (мінт пройшов,
    # telemetry_merkle_root лишився NULL) — witness-фіча ніколи не блокує money-path,
    # але тихо-порожній root = діра в credit→measurements трейсі → видимість тут.
    LINEAGE_ROOT_FAILURES_TOTAL = REGISTRY.counter(
      :silkennet_lineage_root_failures_total,
      docstring: "Mint lineage Merkle-root computation failures (fail-open, root left NULL)"
    )

    # [INF.22 крок 11] Filecoin archive-outbox backlog + recovery видимість.
    # unarchived_depth = archive-requested AuditLog'и без ipfs_cid (money/MRV, які ще не на
    # IPFS) — семплить Treasury::MonitorService (15-хв, freshness проти restart-обнулення
    # in-process gauge; daily-семпл reconcile'а давав би ~24h сліпе вікно).
    # exhausted = FilecoinArchiveWorker вичерпав retry (Pinata down) → архів у Dead Set, ipfs_cid
    # NULL до reconcile-re-pin (без цього тонув у generic DeadSet — self-masking клас ARCH.64/65).
    # repin = скільки reconcile re-enqueue'їв за прогін.
    FILECOIN_UNARCHIVED_DEPTH = REGISTRY.gauge(
      :silkennet_filecoin_unarchived_depth,
      docstring: "Count of archive-requested AuditLog rows still missing ipfs_cid (Filecoin archive backlog)"
    )
    FILECOIN_ARCHIVE_EXHAUSTED_TOTAL = REGISTRY.counter(
      :silkennet_filecoin_archive_exhausted_total,
      docstring: "FilecoinArchiveWorker jobs that exhausted all retries (archive landed in Dead Set) " \
                 "[E.60; diagnostic tier: no alert while sn-alert-sidekiq-deadset and sn-alert-filecoin-unarchived-backlog already read this same exhaustion]"
    )
    FILECOIN_REPIN_TOTAL = REGISTRY.counter(
      :silkennet_filecoin_repin_total,
      docstring: "AuditLog archive re-enqueues issued by FilecoinReconcileWorker " \
                 "[E.60; diagnostic tier: no alert while filecoin_unarchived_depth carries the state question — repin is the VOLUME of self-healing, and a healthy tract repins]"
    )

    # [INF.22] Скільки логів ре-армовано backfill-проходом. ⚠️ Рахує ЛОГИ (`by:`),
    # не проходи — прецедент `FILECOIN_REPIN_TOTAL` вище, де батч подій теж лічиться
    # величиною. Стійке ненульове = sustained IoTeX-outage, а не разовий блип: у
    # здоровому тракті per-uplink enqueue не лишає роботи цьому воркеру.
    IOTEX_BACKFILL_REARMED_TOTAL = REGISTRY.counter(
      :silkennet_iotex_backfill_rearmed_total,
      docstring: "TelemetryLogs re-armed for IoTeX verification by the backfill sweep (sustained-outage recovery; a healthy tract leaves this at zero)"
    )

    # [ARCH.119] Скільки дерев ре-армовано peaq-backfill'ом. Рахує ДЕРЕВА (`by:`),
    # не проходи — прецедент `FILECOIN_REPIN_TOTAL`. ⚠️ Стійке ненульове тут читається
    # ІНАКШЕ, ніж у сусідів: у здоровому тракті реєстрація стається раз на провіжн, тож
    # ненульове = або пізня активація ноги (одноразовий сплеск), або peaq стійко лежить.
    # Порогу немає свідомо — на TRL-3 (нуль вузлів у лісі) він калібрувався б на порожнечі.
    PEAQ_BACKFILL_REARMED_TOTAL = REGISTRY.counter(
      :silkennet_peaq_backfill_rearmed_total,
      docstring: "Trees re-armed for peaq DID registration by the backfill sweep (a healthy tract registers at provisioning and leaves this at zero) " \
                 "[ARCH.119; diagnostic tier: споживача дротуємо, коли `PEAQ_NODE_URL`+`PEAQ_SIGNING_KEY` стануть на деплой-поверхню — доти лічильник нуль ЗА ПОБУДОВОЮ (нога activation-gated, ре-арм не робиться), тож поріг калібрувався б на порожнечі]"
    )

    # [E.60 Фаза 1б] Mint-anchored телеметрія-батч-архівація: збої тракту по фазах.
    # reason: build (fail-open → мінт із zero32 при непорожніх вікнах = кандидат-інцидент) ·
    # pin (Pinata-вичерпання, retries_exhausted-hook) · mismatch (rebuild ≠ stored root при
    # живих логах = integrity-сигнал, runbook 06_08 §4) · retention_expired (листя зникли з
    # дропнутими партиціями — НЕ tamper) · dispatch_drift (advisory: size-1 root ≠
    # telemetry_merkle_root = мутація між lock_and_mint! і диспатчем) · leaf_stamp_drift
    # (sweeper-семпл: перерахований CID ≠ стемп merkle_leaf — raw-SQL мутація).
    TELEMETRY_ARCHIVE_FAILURES_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_archive_batch_failures_total,
      docstring: "Telemetry archive-batch tract failures by phase (build/pin/mismatch/retention_expired/dispatch_drift/leaf_stamp_drift)",
      labels: [ :reason ]
    )
    # Глибина незапінених батчів (pending/build_failed) — семплить Treasury::MonitorService
    # (15-хв). SLO: unpinned age < retention-горизонт партицій (інакше rebuild втратить листя).
    TELEMETRY_ARCHIVE_UNPINNED_DEPTH = REGISTRY.gauge(
      :silkennet_telemetry_archive_unpinned_depth,
      docstring: "Count of telemetry archive batches not yet pinned (pending/build_failed)"
    )

    # [S6.13]: W3bstream Ed25519 → SHA256 hardware-signature fallback counter.
    # `Iotex::W3bstreamVerificationService#hardware_signature` падає з Ed25519
    # (provisioned hardware key) на SHA256 fallback коли HardwareKey відсутній.
    # SHA256 НЕ підтверджує апаратне походження. У production / WEB3_STRICT_MODE=true
    # сервіс fail-closed: інкрементує counter та одразу raise VerificationError
    # (counter все одно інкрементується для observability). Поза production —
    # warn-and-continue (legacy/dev). Grafana alert: > 0 у production = bug
    # (бо raise вже спрацював) АБО legacy fallback використовується у не-prod.
    W3BSTREAM_SIGNATURE_FALLBACK_TOTAL = REGISTRY.counter(
      :silkennet_w3bstream_signature_fallback_total,
      # [INF.26] Рахує ПЕРЕДУМОВУ — telemetry без придатного `HardwareKey`, — а не
      # результат: інкремент стоїть ДО розвилки prod/dev, тож у dev за ним справді йде
      # SHA256-fallback, а в production / WEB3_STRICT_MODE той самий рядок означає
      # ВІДМОВУ (fail-closed raise). Так і має бути: перенести інкремент у dev-гілку
      # означало б осліпнути на проді саме там, де сигнал найпотрібніший. Тому докстрінг
      # називає подію, а не наслідок — ім'я метрики (`_fallback_`) лишається вужчим за
      # неї, і перейменування тут коштувало б дорожче за уточнення (алерт+серії).
      docstring: "Telemetry with no usable HardwareKey — SHA256 fallback in dev, fail-closed rejection in production",
      labels: [ :reason ]
    )

    # [S6.19]: M2M nonce Redis → DB fallback counter.
    # `Api::V1::M2mAuthController#create` падає з Redis SET NX на DB-backed
    # nonce cache коли Redis недоступний (Upstash outage / network blip).
    # Fallback path має малий TOCTOU window (acceptable у degraded mode).
    # Counter дозволяє виміряти actual outage frequency; alert-правило
    # sn-alert-m2m-nonce-fallback (семантика — 04_03 §5.15).
    M2M_NONCE_FALLBACK_TOTAL = REGISTRY.counter(
      :silkennet_m2m_nonce_fallback_total,
      docstring: "Total M2M nonce checks falling back from Redis to DB-backed cache (Redis outage indicator)"
    )

    # [L1 QATT]: Queen-attestation batch nonce Redis → DB fallback counter.
    # `UnpackTelemetryWorker#qatt_nonce_unique?` падає з Redis SET NX на
    # Solid-Cache nonce коли Redis недоступний — той самий S6.1/S6.19 патерн,
    # що й M2M, але окремий counter: змішування шляхів зробило б M2M-алерт
    # сліпим до батч-стріму (різні частоти: auth ~1/30д vs батчі щогодини).
    QATT_NONCE_FALLBACK_TOTAL = REGISTRY.counter(
      :silkennet_qatt_nonce_fallback_total,
      docstring: "Total Queen-attestation batch nonce checks falling back from Redis to DB-backed cache (Redis outage indicator)"
    )

    # 🔴 [INF.22] Rate-limit store failures. The two nonce counters above exist
    # because their fallback is VISIBLE — the request still completes, and the
    # counter says which path served it. Rack::Attack has no fallback: its store
    # is `ActiveSupport::Cache::RedisCacheStore`, whose failsafe swallows every
    # `Redis::BaseError` and returns nil. A nil read is indistinguishable from
    # "this IP has no strikes", so a broken store does not degrade the shield —
    # it silently REMOVES it: throttle counters never increment and the fail2ban
    # threshold is never reached, on a public surface, with an empty log.
    # Measured 2026-08-30 against our own Upstash instance: write/read/increment
    # all returned nil with no exception raised.
    # ⛔ This counter is NOT diagnostic-tier and must never be demoted to one:
    # rate limiting is a security path, and [INF.26] rules that a declared
    # diagnostic tier there legalises the hole instead of closing it. Its
    # consumer is `sn-alert-rate-limit-store-errors`.
    RATE_LIMIT_STORE_ERRORS_TOTAL = REGISTRY.counter(
      :silkennet_rate_limit_store_errors_total,
      docstring: "Rack::Attack cache-store operations that failed and were swallowed by the RedisCacheStore failsafe (rate limiting is silently OFF while this climbs)"
    )

    # [FW.22 / S2.3]: Acoustic events overflow counter.
    # Firmware saturates acoustic_events at uint8 max (255).
    # Value 255 indicates real count may be higher — sensor data loss.
    # Enables Grafana alerting on acoustic overflow events.
    TELEMETRY_ACOUSTIC_OVERFLOW_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_acoustic_overflow_total,
      docstring: "Total telemetry packets with acoustic_events=255 (uint8 saturation)"
    )

    # [S2.2]: Web3 RPC circuit breaker state gauge.
    # Tracks which RPC providers are currently in circuit-open (disabled) state.
    # 1.0 = circuit open (provider disabled), 0.0 = circuit closed (provider healthy).
    RPC_CIRCUIT_BREAKER_OPEN = REGISTRY.gauge(
      :silkennet_rpc_circuit_breaker_open,
      docstring: "Whether RPC provider circuit breaker is open (1=open/disabled, 0=closed/healthy)",
      labels: [ :provider ]
    )

    # [S2.2 fix 2026-05-29]: Web3 circuit-breaker fast-fail rejections.
    # `Web3CircuitBreaker` already increments this (guarded `if defined?`), but the
    # metric was never registered → the increment was a silent no-op (rejections
    # invisible). Defining it activates that existing instrumentation.
    CIRCUIT_BREAKER_REJECTIONS = REGISTRY.counter(
      :silkennet_circuit_breaker_rejections_total,
      docstring: "Web3 requests fast-failed because a provider circuit breaker was open " \
                 "[S2.2; diagnostic tier: no alert while sn-alert-circuit-breaker pages on the STATE — this counter is the VOLUME behind the same event, read during triage]",
      labels: [ :service ]
    )

    # [S6.16]: TelemetryLog lookup without partition pruning (degraded path).
    # Incremented when a caller looks up a TelemetryLog without supplying
    # `created_at_iso`. Without it, PostgreSQL must scan ALL monthly partitions
    # (Global Partition Scan) — O(P × log N) instead of O(log N). At billions
    # of rows this becomes a multi-second query that blocks the request thread.
    # Acceptable in cold paths (admin tools, manual rollback); ALERT if seen
    # in hot path (oracle callbacks, web3 workers) — indicates upstream worker
    # forgot to pass `created_at_iso`. Grafana rule:
    #     rate(silkennet_telemetry_log_unpruned_lookups_total{caller=~"oracle.*|.*Worker"}[5m]) > 0
    TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_log_unpruned_lookups_total,
      docstring: "Total TelemetryLog lookups without partition pruning (degraded path; missing or invalid ISO8601 created_at_iso)",
      labels: [ :caller ]
    )

    # [S6.16 / 00_07 PERF.1]: the money-model twin of the counter above.
    # `BlockchainTransaction` degraded exactly like `TelemetryLog` but did so
    # SILENTLY — so the one event the telemetry counter exists to surface was
    # invisible on the model where a full scan is most expensive. Two callers
    # feed it straight from a URL parameter (`wallets#transaction_status`,
    # `blockchain_transactions#show`), so a malformed client string is a real
    # trigger, not only a forgotten worker argument. Same shape, same alerting
    # posture: cold paths acceptable, hot paths page.
    #     rate(silkennet_blockchain_transaction_unpruned_lookups_total[5m]) > 0
    BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL = REGISTRY.counter(
      :silkennet_blockchain_transaction_unpruned_lookups_total,
      docstring: "Total BlockchainTransaction lookups without partition pruning (degraded path; missing or invalid created_at)",
      labels: [ :caller ]
    )

    # [06_03 §2.8 / 00_07 S2.5]: PartitionMaintenanceWorker run failures.
    # Each failure = a monthly partition may be missing. ⚠️ The rationale here was
    # DISPROVED 2026-08-28 (00_07 ARCH.70): day-1 INSERT does NOT crash — every RANGE
    # table carries a `_default` leaf, so the row lands there silently. The cost is
    # worse: from that moment `CREATE ... PARTITION OF` for that month fails
    # `PG::CheckViolation` FOREVER and retries cannot heal it (runbook 06_06 §5.5).
    # Alert (silkennet-alerts.yaml, P0): increase>0 → page.
    PARTITION_MAINTENANCE_FAILURES_TOTAL = REGISTRY.counter(
      :silkennet_partition_maintenance_failures_total,
      docstring: "PartitionMaintenanceWorker run failures (missing partition → rows silently land in the _default leaf, which then blocks CREATE PARTITION for that month permanently)"
    )

    # [00_07 ARCH.70]: прилад РОСТУ партиційних таблиць. Сусід згори стереже
    # СТВОРЕННЯ партицій, цей — їх накопичення: доти алерту на ріст не існувало
    # взагалі, тож поріг «пора дропати» був невидимий, а ⚖️ про ширину вікна
    # ухвалювався б наосліп (та сама сліпота, яку E.37 уже оплатив: метрика
    # per-row існувала, дивитись на неї проти порога не було кому).
    #
    # Дві осі, бо питання РІЗНІ. `partitions` = скільки МІСЯЦІВ сирої історії
    # накопичено: автоматичного дропу в `app/`/`lib/` немає, тож лічильник монотонний
    # ЗА ПОБУДОВОЮ і фактично дорівнює наявному вікну ретеншну. `bytes` = чого це
    # коштує (PD_SSD + розмір бекапів + час DR-відновлення — `06_06`).
    # ⚠️ Диск межею НЕ є: `disk_autoresize = true` (`terraform/database.tf`), тож
    # режим відмови тут не crash, а тиха ціна й план-латентність на зайвих
    # партиціях — саме тому обидва алерти `info`, а не `critical`.
    #
    # 🔴 Писач ОДИН — `PartitionMaintenanceWorker` (той самий дім, що й лічильник
    # збоїв вище). Факт ГЛОБАЛЬНИЙ (одна БД на всі процеси), тож семплить job-
    # процес, а не кожен скрейп: інакше три scrape-таргети (web/job/coap, §2.9)
    # віддали б три ІДЕНТИЧНІ серії — та сама причина, з якої `refresh_sidekiq_gauges`
    # гейтований `Sidekiq.server?`.
    # ⚠️ Оголошена стеля: гейджі живуть у памʼяті job-процесу й наповнюються раз на
    # добу (cron `30 0 * * *`), тож між рестартом процесу і найближчим прогоном
    # серії немає. Тому `noDataState: OK` — ВІДСУТНІСТЬ виміру не є ростом, і
    # мертвий scrape-таргет має власний дім (`sn-alert-scrape-target-down`).
    # ⊥ ЗАМЕРЗЛИЙ вимір — інша річ, і його ловить третій гейдж нижче.
    PARTITIONS_PRESENT = REGISTRY.gauge(
      :silkennet_partitions,
      docstring: "Leaf partitions currently attached to a RANGE-partitioned table (monotonic — no DROP mechanism exists yet)",
      labels: [ :table ]
    )

    PARTITIONED_TABLE_BYTES = REGISTRY.gauge(
      :silkennet_partitioned_table_bytes,
      docstring: "On-disk bytes of a RANGE-partitioned table including every partition, index and TOAST",
      labels: [ :table ]
    )

    # 🔴 Третя вісь — ЖИВІСТЬ самого приладу, і без неї дві вищі вакуумні за
    # побудовою. Обидва гейджі наповнює добовий cron у живому процесі, тож
    # «воркер перестав бігти» НЕ прибирає серію — вона ЗАМЕРЗАЄ на останньому
    # значенні. А партиції лише накопичуються, тобто замерзлий гейдж
    # НЕДООЦІНЮЄ, і алерт лишається зеленим рівно тоді, коли має кричати.
    # Це той самий клас «конфіг повний, шлях мертвий», що вже кусав §06, і він
    # найімовірніший там, де cron-планувальник переїжджає на нову платформу.
    # ⚠️ Межа: ВІДСУТНЯ серія (свіжий процес до найближчих 00:30 UTC) цим не
    # ловиться свідомо — мертвий scrape-таргет має власний дім
    # (`sn-alert-scrape-target-down`), і дублювати його тут означало б пейджити
    # на кожному деплої.
    PARTITION_SAMPLE_TIMESTAMP = REGISTRY.gauge(
      :silkennet_partition_sample_timestamp_seconds,
      docstring: "Unix time of the last successful partition growth sample (freshness witness for the two gauges above)"
    )

    # 🔴 Четверта вісь, і вона НЕ про ріст: DEFAULT-партиція є єдиною, чия
    # непорожність ламає обслуговування НЕЗВОРОТНО. Механізм виміряно, не
    # виведено: щойно в DEFAULT осів рядок місяця N, `CREATE TABLE ... PARTITION
    # OF ... FOR VALUES` для місяця N падає з `PG::CheckViolation` («updated
    # partition constraint for default partition would be violated by some
    # row»), і повідомлення НЕ містить `already exists`, тож
    # `PartitionMaintenanceWorker#ensure_partition` re-raise'ить. Далі каскад:
    # прохід падає на першій таблиці, партиції НАСТУПНОГО місяця для решти двох
    # не створюються, а `sample_growth_gauges!` стоїть ПІСЛЯ циклу — тобто два
    # гейджі вище замерзають рівно тоді, коли мали б кричати. Ретраї не лікують:
    # стан сам не змінюється, потрібен ручний DETACH/переливання/ATTACH.
    # ⚠️ Величина СВІДОМО бінарна (`EXISTS`, не `count`): рішення оператора не
    # залежить від кількості рядків — будь-який один уже блокує місяць, — а
    # `count(*)` над розрослим DEFAULT коштував би сканування саме тоді, коли
    # прилад найпотрібніший. 0 тут = здоровʼя, і воно ОЧІКУВАНЕ значення.
    # 🔴 [ARCH.70] ТРЕТІЙ ВИМІР РЕТЕНШНУ — РЯДКИ. Реєстр мав місяці (`silkennet_partitions`)
    # і байти (`silkennet_partitioned_table_bytes`), а скільки РЯДКІВ ми тримаємо — ні,
    # і саме рядки визначають, що саме зітре майбутнє вікно ретеншну.
    #
    # ⛔⛔ ПІДПИС ТУТ І Є ПРИСУДОМ, І ВІН НАВМИСНО НЕ КАЖЕ «БЕКЛОГ». Спокуса назвати це
    # «скільки рядків чекає на callback» вигадала б число: `ChainlinkDispatchWorker`
    # ставить `dispatched` як ЛОКАЛЬНИЙ маркер без RPC, callback unwired, PATH 1
    # демоутовано ([ARCH.53]) — тобто закривача не існує ЗА ПОБУДОВОЮ, і популяція
    # монотонна не через затор, а через відсутність другої половини тракту. Величина
    # чесно означає «скільки верифікованих рядків ми ТРИМАЄМО», і рівно в цьому вона
    # корисна: вона є ціною майбутнього вікна ретеншну, а не сигналом інциденту.
    # ⚠️ Тому й алерт-порога тут бути НЕ МОЖЕ у звичайній формі: «скільки прийнятно»
    # для монотонної-за-побудовою величини не визначене. Законна форма — операторська
    # стеля-дедлайн (як `> 24` у сусіда), і вона ратифікується РАЗОМ із шириною вікна.
    # 🔒 Ярус — ДІАГНОСТИЧНИЙ (оголошено, [INF.26]): правила немає, доки немає вікна.
    # ⊕ Ціна лічби виміряна, не припущена: партіальний `idx_telemetry_logs_oracle_dispatched`
    # дає `Index Only Scan` по кожній партиції (EXPLAIN, 2026-08-29) — тобто це не скан
    # партицій, і важіль [ARCH.52] на місці. ⛔ Не розширювати на `group(:oracle_status)`:
    # решта станів партіального індексу не має, і розбивка перетворила б дешеву лічбу
    # на seq scan усіх партицій.
    TELEMETRY_ORACLE_DISPATCHED_ROWS = REGISTRY.gauge(
      :silkennet_telemetry_oracle_dispatched_rows,
      docstring: "Retained telemetry rows carrying oracle_status=dispatched — the RETENTION cost of verified rows, NOT a backlog: the callback closing this state is unwired by construction (PATH 1 demoted, ARCH.53), so the population is monotonic by design [ARCH.70; diagnostic tier: no alert until the retention window is ratified]"
    )

    PARTITION_DEFAULT_OCCUPIED = REGISTRY.gauge(
      :silkennet_partition_default_occupied,
      docstring: "1 when a table's DEFAULT partition holds any row — that row permanently blocks CREATE PARTITION for its month (no self-heal)",
      labels: [ :table ]
    )

    # [ENTROPY MONITOR]: Shannon entropy of Z-value distribution per cluster.
    # Healthy forest: ≈ 0.75-0.95 (diverse Z-values). Pre-stress: < 0.65.
    # Updated by ClusterEntropyAnalyzerWorker (queue: alerts, hourly).
    CLUSTER_ENTROPY_SCORE = REGISTRY.gauge(
      :silkennet_cluster_entropy_score,
      docstring: "Normalized Shannon entropy of Z-value distribution per cluster (0.0-1.0). " \
                 "LAST COMPUTED value [INF.26 verdict 2026-08-30]: the gauge FREEZES when the 24h window " \
                 "holds <30 samples or the cluster stops reporting (worker skips without touching it) — " \
                 "freshness is deliberately NOT this gauge's axis; cluster liveness is alerted elsewhere " \
                 "(sn-alert-gateway-faulty P0, sn-alert-trees-silent). A freshness stamp is fleet-gated: " \
                 "per-cluster staleness pairs before any live fleet would alert on nothing",
      labels: [ :cluster_id ]
    )

    # [SLASH-1] Розходження денормалізованого active_trees_count із живим COUNT
    # (live − cached). Ненульове означає, що ЗНАМЕННИК тригера слешингу хибний:
    # поріг `> N × slash_fraction` і межа виродження `N < 1/slash_fraction` міряють
    # вигадану популяцію. Нуль тут — стан за побудовою (писачів в обхід колбеків не
    # існує), тож будь-яке відхилення є подією, а не шумом.
    CLUSTER_TREE_COUNT_DRIFT = REGISTRY.gauge(
      :silkennet_cluster_tree_count_drift,
      docstring: "Live active-tree COUNT minus the denormalized active_trees_count (0 = in sync; nonzero means the slashing trigger measures a fabricated denominator)",
      labels: [ :cluster_id ]
    )

    # -----------------------------------------------------------------------
    # [06_03 §2.9 Process / runtime health] Ruby VM, GC, memory + Puma pool.
    # Refreshed on each scrape (sample_process_runtime!) — gives prod visibility
    # into memory leaks, GC pressure, and thread/worker saturation that business
    # metrics cannot. Pure Ruby stdlib (GC.stat / Thread.list / /proc / Puma.stats),
    # no extra gems (consistent with §"Чому prometheus-client").
    # -----------------------------------------------------------------------
    PROCESS_RESIDENT_MEMORY_BYTES = REGISTRY.gauge(
      :silkennet_process_resident_memory_bytes,
      docstring: "Resident set size (RSS) of the scraped process in bytes (Linux /proc; 0 elsewhere)"
    )

    RUBY_GC_COUNT = REGISTRY.gauge(
      :silkennet_ruby_gc_count,
      docstring: "Total Ruby GC runs since process start (GC.stat[:count])"
    )

    RUBY_GC_MAJOR_COUNT = REGISTRY.gauge(
      :silkennet_ruby_gc_major_count,
      docstring: "Major Ruby GC runs since process start (GC.stat[:major_gc_count])"
    )

    RUBY_GC_HEAP_LIVE_SLOTS = REGISTRY.gauge(
      :silkennet_ruby_gc_heap_live_slots,
      docstring: "Live objects on the Ruby heap (GC.stat[:heap_live_slots]); sustained growth = leak"
    )

    RUBY_THREADS = REGISTRY.gauge(
      :silkennet_ruby_threads,
      docstring: "Live Ruby threads in the process (Thread.list.size); sustained growth = thread leak"
    )

    PUMA_RUNNING_THREADS = REGISTRY.gauge(
      :silkennet_puma_running_threads,
      docstring: "Puma worker threads currently spawned (busy + idle)"
    )

    PUMA_MAX_THREADS = REGISTRY.gauge(
      :silkennet_puma_max_threads,
      docstring: "Puma configured max threads (pool ceiling)"
    )

    PUMA_POOL_CAPACITY = REGISTRY.gauge(
      :silkennet_puma_pool_capacity,
      docstring: "Puma free thread-pool capacity (0 = saturated → requests queue in backlog)"
    )

    PUMA_BACKLOG = REGISTRY.gauge(
      :silkennet_puma_backlog,
      docstring: "Puma requests waiting for a free thread (backlog; sustained >0 = under-provisioned)"
    )

    # Snapshot connection pool stats for Prometheus scraping.
    # Called from PrometheusCollector middleware or a periodic job.
    #
    # 🔴 `each_connection_pool`, НЕ `all_connection_pools` — останнього на Rails 8.1 не
    # існує, і виміряно це лише 2026-09-03, з ЖИВОГО стека: чотири ґейджі пулу не мали
    # жодної серії НІКОЛИ, тоді як сусід `sample_process_runtime!` (рядком нижче в тому
    # самому колекторі) віддавав свої. Причина тиші — `rescue` внизу: `NoMethodError`
    # є `StandardError`, тож кожен скрейп ловив його у `logger.warn`. Покриття лишалось
    # зеленим, бо request-спека на `/metrics` ці рядки ВИКОНУВАЛА — включно з `rescue`.
    # ⚠️ Оголошена ціна `rescue`: він тримає ендпоінт живим (це його призначення) і тим
    # самим робить зламаний семплер НІМИМ. Носій проти рецидиву — не він, а спека
    # `spec/middleware/prometheus_collector_spec.rb` §«DB-pool gauge refresh», що пінить
    # ЗНАЧЕННЯ в тілі відповіді: пін на «не кинуло» тут вакуумний за побудовою.
    def self.sample_connection_pool!
      ActiveRecord::Base.connection_handler.each_connection_pool do |pool|
        db_name = pool.db_config.name.to_s

        conns = pool.connections
        in_use = conns.count(&:in_use?)

        DB_POOL_SIZE.set(pool.size, labels: { database: db_name })
        DB_POOL_CONNECTIONS.set(in_use, labels: { database: db_name })
        DB_POOL_IDLE.set(conns.size - in_use, labels: { database: db_name })
        DB_POOL_WAITING.set(pool.num_waiting_in_queue, labels: { database: db_name })
      end
    rescue StandardError => e
      Rails.logger.warn "⚠️ [Prometheus] Connection pool sampling failed: #{e.message}"
    end

    # Snapshot Ruby VM / GC / memory + Puma pool stats for Prometheus scraping.
    # Called from PrometheusCollector on each scrape (cheap: GC.stat is O(1)).
    def self.sample_process_runtime!
      gc = GC.stat
      RUBY_GC_COUNT.set(gc[:count].to_i)
      RUBY_GC_MAJOR_COUNT.set(gc[:major_gc_count].to_i)
      RUBY_GC_HEAP_LIVE_SLOTS.set(gc[:heap_live_slots].to_i)
      RUBY_THREADS.set(Thread.list.size)
      PROCESS_RESIDENT_MEMORY_BYTES.set(process_rss_bytes)
      sample_puma_pool!
    rescue StandardError => e
      Rails.logger.warn "⚠️ [Prometheus] Process runtime sampling failed: #{e.message}"
    end

    # Resident set size in bytes from Linux /proc/self/status (VmRSS, kB → bytes).
    # Returns 0 on non-Linux (dev/test macOS) or if unreadable — gauge stays 0.
    def self.process_rss_bytes
      kb = File.read("/proc/self/status")[/^VmRSS:\s+(\d+)\s+kB/, 1]
      kb ? kb.to_i * 1024 : 0
    rescue StandardError
      0
    end

    # Puma thread-pool stats (web process only). Handles single + clustered modes.
    # No-op when Puma is absent or stats unparseable (e.g. the Sidekiq process).
    def self.sample_puma_pool!
      return unless defined?(::Puma) && ::Puma.respond_to?(:stats)

      raw = ::Puma.stats
      stats = raw.is_a?(String) ? JSON.parse(raw) : raw
      return unless stats.is_a?(Hash)

      if (workers = stats["worker_status"])
        running = capacity = backlog = max = 0
        workers.each do |w|
          ls = w["last_status"] || {}
          running  += ls["running"].to_i
          capacity += ls["pool_capacity"].to_i
          backlog  += ls["backlog"].to_i
          max      += ls["max_threads"].to_i
        end
        PUMA_RUNNING_THREADS.set(running)
        PUMA_POOL_CAPACITY.set(capacity)
        PUMA_BACKLOG.set(backlog)
        PUMA_MAX_THREADS.set(max)
      else
        PUMA_RUNNING_THREADS.set(stats["running"].to_i)
        PUMA_POOL_CAPACITY.set(stats["pool_capacity"].to_i)
        PUMA_BACKLOG.set(stats["backlog"].to_i)
        PUMA_MAX_THREADS.set(stats["max_threads"].to_i)
      end
    rescue StandardError => e
      Rails.logger.warn "⚠️ [Prometheus] Puma stats sampling failed: #{e.message}"
    end
  end
end
