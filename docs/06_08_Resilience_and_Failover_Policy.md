# 06_08: Resilience and Failover Policy

## 🎯 Мета

Зафіксувати єдину політику резервування та відмовостійкості для двох найкритичніших ризик-векторів SilkenNet:

1. **Queen Gateway як Single Point of Failure** — фізичний шлюз між LoRa-мережею Солдатів і Akash/Rails.
2. **12-ланковий Web3-конвеєр як Lego Tower of Doom** — будь-яка зовнішня мережа (IoTeX, Streamr, Chainlink, Hadron, KlimaDAO, ...) може mute/cap/break.

Документ описує `Fallback / Retry / Buffer policy` для кожної ланки та механізм продовжувати Proof-of-Growth ([`05_02`](05_02_Proof_of_Growth_Pipeline)) навіть при тимчасовій відсутності окремих мостів.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — політика затверджена; реалізовані якорі — §3 (circuit breaker, CoAP retry, QATT-v2 пульс + dead-man switch, manual_review, money-path idempotency [ARCH.45], Celo multi-RPC). **⚠️ Чесність-пас 2026-07-04:** попередня редакція ✅-ила механізми, яких у коді НЕМАЄ (backfill/buffer-list/gas-defer-пули, `Web3::ChainlinkRouterVersion` — видалений ARCH.53-демоутом) — вони перепозначені **🟡 target** інлайн у §2.2/§2.3 і зібрані в [`00_07` INF.22](00_07_Action_Plan_Tracker). Залишаються 🟡 (→ [`00_07`](00_07_Action_Plan_Tracker)): Q2Q Backhaul Mesh + Flash overflow tier (ARCH.35), Helium Queen-side LoRaWAN (ARCH.34-firmware), TDMA/CAD sync (ARCH.26), Conductor L2 (ARCH.1). Production-rollout — Phase 2 ([`00_03`](00_03_TRL_Matrix_HIL_and_Beyond)).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_00` — SSOT Index](00_00_SSOT_Index) | Системна карта (8 рівнів) + 12-chain → 05_02 |
| [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) | Hardware Queen + Q2Q mesh + Helium fallback |
| [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) | Прошивка Queen (CoAP retry, CIFO) |
| [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) | Мультичейн архітектура |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Proof-of-Growth pipeline; §Dynamic Tax — `insurance_pool` fallback economics |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `Web3CircuitBreaker` concern; Celo multi-RPC fallback (E.49 — `RPC_FALLBACK_ENV_KEYS`) |
| [`06_02` — Akash Network Integration](06_02_Akash_Network_Integration) | Multi-provider SDL, fallback GCP/Kamal |
| [`06_03` — Prometheus Observability](06_03_Prometheus_Observability) | Метрики Resilience SLO |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** (SSOT): ARCH.26 TDMA/CAD, ARCH.34 Helium, ARCH.35 Flash, INF.4/INF.6 Ingress, ARCH.1 Conductor L2 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. ☂️ Queen Gateway Failover Protocol](#1--queen-gateway-failover-protocol)
- [2. 🪜 Web3 Chain Fallback Matrix (Anti-Lego Tower)](#2--web3-chain-fallback-matrix-anti-lego-tower)
- [3. 🧰 Реалізаційні Якорі (Implementation Anchors)](#3--реалізаційні-якорі-implementation-anchors)
- [4. 📖 Web3 Incident & Contract-Ops Runbooks](#4--web3-incident--contract-ops-runbooks)
<!-- TOC:AUTO:END -->

---

## 1. ☂️ Queen Gateway Failover Protocol

### 1.1 Чому це SPOF

У поточній архітектурі Queen — **єдиний always-on listener** і єдина точка виходу через Starlink/LTE для свого LoRa-кластера. Якщо Queen втрачає живлення, фізично знищена, втратила Starlink-зв'язок або переходить у `state: faulty` AASM — весь кластер (50–200 Soldier'ів) залишається без uplink.

### 1.2 Чотири рівні резервування

| Рівень | Механізм | Trigger | Latency | Реалізація |
|--------|----------|---------|---------|------------|
| **L1: Queen Local Buffer (Two-Tier)** | **Hot tier:** CIFO EdgeCache до 50 slots in-RAM (дедуплікація за DID + priority-aware eviction), flush на 1 год TTL або при ≥ 45 entries. **Overflow tier:** при `AT+CCOAPSEND` fail після N retry — drain CIFO у SPI NOR Flash Ring Buffer (W25Q32, 4 МБ; **sector-based** ring — 1024×4 KB сектори, 192 слоти×21 байт/сектор ≈ 197k слотів; NOR вимагає erase цілим сектором, тому ring обертається по секторах, не байтах — [`02_05 §2.1`](02_05_Queen_Hardware_and_Starlink); ARCH.35). Якщо Starlink/LTE недоступні — повторити flush експоненційно (1, 2, 4, 8, 16 хв cap = 60 хв). При відновленні uplink — спочатку drain Flash Ring Buffer (FIFO, через CIFO-refill), потім CIFO. | `AT+CCOAPSEND` timeout або UART fail | Seconds (RAM tier) / Hours-days (Flash tier) | `firmware/queen/main.c` CoAP retry loop (FW.9, `COAP_MAX_RETRIES`), host-tested: per-attempt conversation-fail (`test_at_engine.c`) + fail→retry→no-loss (`test_fw51_*`); Flash Ring Buffer — **драйвер ✅ host-tested** (`firmware/common/flash_ring.{h,c}`, NOR-мок + power-cut, at-least-once; Queen-глю gated `ARCH35_RING_ENABLED 0`); residual = W25Q32 розводка + bench (ARCH.35) |
| **L2: Queen-to-Queen LoRa Backhaul** | Сусідня Queen у радіусі 5–15 км (SF12 спред-фактор, **~0.25 кбіт/с / 250 bps на BW125** — не 6 кбіт/с) приймає `delegate_uplink_frame` від основної Queen. Дренаж кластера (200×21 Б ≈ 134 с **чистого TOA**) ⚠️ підлягає тому самому EU868 duty-cycle, що вбиває Helium-backhaul нижче: у стандартних суб-бендах g1/g2 (1%) wall-clock ≈ **години**; «хвилини» (~20 хв) досяжні лише в **g3 869.4–869.65 МГц** (10% duty, 500 мВт ERP) — вибір смуги відкритий ([`00_07` ARCH.10](00_07_Action_Plan_Tracker)). Якщо власний Starlink також впав — пересилає далі по LoRa-магістралі до Queen з активним uplink. | Local Starlink/LTE down >5 хв OR `coap_health = false` | Hours (1%-band) / ~20 хв (g3) — gated вибором смуги | `Queen → Queen` через `RELAY_QUEEN` фрейм (DEFAULT_TTL=4); планується [`02_05`](02_05_Queen_Hardware_and_Starlink) (Q2Q Mesh) |
| **L3: Helium SOS-маяк Королеви (Queen-side)** | Queen формує валідний **LoRaWAN** frame (DevEUI/AppEUI/AppKey, FCntUp, OTAA). **Лише SOS, НЕ телеметрія кластера** (див. ⚠️ нижче): один малий пакет (📐 **wire-freeze 12 Б, One-Home:** `[queen_did:4 BE][vcap_mv:2 BE][error_code:1][uptime_min:u24 BE][flags:1][rsv:1]`; error-codes 1=starlink_down 2=lte_down 3=q2q_unreachable 4=buffer_pressure — дзеркало `HeliumSosWorker::ERROR_CODES`) → Helium hotspot (~15 км, SF12) → Helium LNS → HTTP Integration → Rails `POST /api/v1/telemetry/helium` (HMAC `X-Helium-Signature`, патерн oracle_callbacks). **Backend-half ✅ (2026-07-03, ARCH.34):** `HeliumSosController` → `HeliumSosWorker` (черга alerts; dev_eui↔`gateways.helium_dev_eui` + cross-check `queen_did` проти hex-uid) → `EwsAlert(queen_uplink_lost)` + `report_fault!` → ескалація L4 (виїзд лісника). Телеметрія Солдатів тим часом буферизується у SPI Flash Королеви (ARCH.35). **NB:** Soldier лишається на raw LoRa P2P (**AES-128**; wire за ерою: 16B ECB → 30B CCM rev2.1 — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); LoRaWAN stack живе ТІЛЬКИ на Queen. | Власний Starlink/LTE-M down + Q2Q backhaul недоступний | Tens of seconds | Queen firmware `queen_helium_lorawan_uplink()` (ARCH.34: обв'язка+wire+MAC-adapter+host-цикл ✅, ефір = bench); деталі — [`02_05 §6.1 Helium Fallback`](02_05_Queen_Hardware_and_Starlink) |
| **L4: Field Operator Pull (Forester app)** | Лісник з мобільним пристроєм підходить до фізичної Queen, підключається через BLE (Forester app) і вручну дренує CIFO буфер на 4G/Wi-Fi. | Manual escalation коли L1-L3 fail >24 год | Hours-Days | Forester mobile app (UI заплановано Phase 2) |

> **⚠️ Фізика Helium: L3 — це SOS-маяк, а НЕ телеметрійний backhaul.** Queen агрегує 50–200 Солдатів; навіть 50 × 21 байт = ~1050 байт. Максимальний application-payload LoRaWAN на **SF12** (потрібен для добивання до Helium-вишок на ~15 км) у EU868 — лише **~51 байт**. Пропхнути телеметрію кластера через Helium означало б фрагментацію на десятки uplink'ів, що (а) спалює батарею Королеви і (б) порушує Helium Fair Use / EU868 1% duty-cycle. Тому Helium несе **лише один SOS-кадр самої Королеви** («я втратила uplink»), а телеметрія Солдатів чекає у Flash Ring Buffer (L1 overflow tier, ARCH.35) до відновлення Starlink/Q2Q або приходу лісника (L4).

### 1.3 Queen Health Heartbeat → Rails [ARCH.54 ✅ 2026-07-03]

Пульс Королеви — **health-блок у ПІДПИСАНОМУ QATT-v2 конверті** кожного flush (8 Б: `uptime_min/cifo_fill/lora_rx_drops/coap_fail/csq/flags`; wire — [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security), розкладка One-Home `firmware/common/queen_attest.h`). Порожній CIFO → **empty-flush heartbeat** (конверт без записів). Стара DID=0-псевдотелеметрія ВБИТА ([`03_02 §7`](03_02_Queen_Gateway_Firmware) — вона брехала полями і ламала CCM-stride); `vcap_mv`/`starlink_rssi` з попередньої редакції — чесно ВІДСУТНІ (Королева без ADC-тракту; CSQ модема — є). Backend: `UnpackTelemetryWorker#enqueue_envelope_health` → `GatewayTelemetryWorker` → `GatewayTelemetryLog`.

**Dead-man switch (первинний, Шар 0):** `GatewayStalenessSweepWorker` (cron */5 хв, черга alerts):

- `online?` = `last_seen_at >= (sleep_interval * 1.2).seconds.ago` (модель `Gateway`, [`04_01`](04_01_Data_Models_and_Entities))
- offline у робочому стані → AASM `report_fault!` + `EwsAlert(queen_offline)` (критичний, анти-спам по кластеру) → Forester Guild notify; повернення в ефір → `recover!` + auto-resolve алерту; attest-lapse спостереження (`last_attested_at` > 24h при online QATT-Королеві → метрика+warn). Grafana: `silkennet_gateways_faulty` P0-правило.
- 🔴 **[ARCH.75] Смерть Королеви термінує її недоставні накази** (`ActuatorCommand.pending` → `fail!`), і це не бухгалтерія: доти наказ від людини лежав `pending` вічно, бо TTL він не має взагалі, а `live_pending` тримає 409 — тобто один клік по Королеві, що потім померла, назавжди відрізав форестера від актуатора. Причина довголіття — спроєктований термінатор (`sidekiq_retries_exhausted`) став недосяжним, коли [`FW.60`](00_07_Action_Plan_Tracker) зняв push-тракт: механізм є, пускача немає. ⚠️ Ціна названа: Королева вміє повертатись, тож наказ, поданий за хвилину до обриву, згорить — свідомий обмін.

**Per-Soldier dead-man switch [SILENCE-1, sweeper-нога ✅ 2026-07-19]:** `TreeStalenessSweepWorker` (cron */5 хв, черга alerts) — дзеркало Шару 0 для дерев: без нього backend бачить зникнення лише cluster-wide (`DailyHealthRouter#blackout?`) → вкрадений/мертвий вузол «мінтить», доки сусіди цокочуть. Дві свідомі відмінності від Queen-половини:

- **Поріг НЕ виводиться з конфіга** (⊥ Queen `config_sleep_interval_s * 1.2`): Soldier спить між energy-sufficient циклами, `delta_t` навмисно варіативний (стрес → повільніший заряд → довша тиша = сам сигнал, [`00_07` E.63](00_07_Action_Plan_Tracker)) → `SystemParameter :tree_silence_threshold_hours`, а дефолт має ОДИН дім у коді — `Tree::SILENCE_THRESHOLD` **[transitional]** до bench-калібрування (значення тут свідомо не дублюємо: воно ще зрушить, і три прозові копії числа розійшлися б; [ARCH.99](00_07_Action_Plan_Tracker) вирівняв воркер, скоуп і в'ю на цю константу). Скоуп `Tree.silent(threshold)` = active + вже виходив в ефір (`last_seen_at` NOT NULL) + мовчить довше порога — dormant/removed/deceased легітимно мовчазні.
- **Носій = per-tree `EwsAlert(:field_audit)`, НЕ новий alert-тип:** новий critical-тип потрапив би у blacklist-предикат `critical_unmaintained?` за замовчуванням → тиша накручувала б slash-penalty оператору («тиша НІКОЛИ не slash», [`05_05 §3.2`](05_05_Slashing_and_Risk_Policy)). Dedup-скоупи взаємовиключні (partial-індекси `tree_id IS NULL` ⊥ `IS NOT NULL`): cluster-blackout і per-tree тиша співіснують, не конфлатяться.

**Dark-cluster suppression (анти-шторм, корельована тиша):** gateway на кластер один, дерев — тисячі; Queen падає → через поріг «мовчазним» стає УВЕСЬ кластер → без глушника один прохід породив би N critical-алертів + N notification-джобів. Per-tree тиша інформативна лише коли кластер ЧУЄ (сусіди цокочуть, це дерево — ні): кластер з активним `queen_offline`/`queen_uplink_lost` або cluster-level `field_audit` (blackout) = known-dark → його дерева скіпаються (cluster-рівень уже ескальований; Queen-sweeper детектить за хвилини — завжди випереджає tree-поріг у годинах). Свідома стеля: некорельований масовий перетин порога (глушилка при живій Королеві до daily-blackout-крона) глушником не покритий — розкид `delta_t` розмазує його в часі. ⊥-співіснування dedup-скоупів (cluster-blackout + per-tree одночасно активні) при цьому ЖИВЕ на рівні `escalate_field_audit!` — глушить саме воркер, не модель.

**Resolve — дві гілки:** (1) вузол знову в ефірі (спростовуючий факт = сам ефір); (2) вузол покинув `active` (dormant = людина приспала; removed/deceased = кейс веде slashing) — інакше критичний алерт висів би вічно (`last_seen_at` такого дерева більше не оновиться). Обидві — машинний resolve (`resolved_by` NULL — gap-E-дискримінатор `critical_unmaintained?`). Поріг-читання fail-safe: misconfig-значення `SystemParameter` (non-numeric/boolean) → дефолт 24h, НЕ `0` (нуль тихо флагнув би весь флот).

Статус дерева воркер НЕ чіпає (dormant = людське рішення, removed/deceased запускають slashing). Grafana: `silkennet_trees_silent` / `silkennet_tree_silence_total` ([`06_03 §2.8`](06_03_Prometheus_Observability)) + P1-правило `sn-alert-trees-silent` (warning, for 30m — масовий кейс несе P0 `sn-alert-gateway-faulty`, сюди не дублюється). ⚠️ Це sweeper-**нога** розрізнювача: «мовчазне здоров'я ↔ смерть/крадіжка» остаточно розділяє лише signed daily heartbeat (firmware-нога, bench-gated) — стан і ⚖️-пороги → [`00_07` SILENCE-1](00_07_Action_Plan_Tracker); ARCH.8 event-triggered TX лишається гейтованим до heartbeat-ноги.

**Третій сторож — актуаторний [ARCH.58, ✅ 2026-07-27]:** `ActuatorSafetySweepWorker` (cron `12,42`, черга `downlink`). Два перші стережуть **тишу пристрою**; цей — **загублений слід власної команди**: актуатор числиться `active` довше за вікно найновішої своєї команди (втрачена scheduled-джоба Reset у Redis, крах між комітом видачі та `perform_in`, вичерпані ретраї). Три свідомі відмінності від сусідів:

- **Черга `downlink`, не `alerts`** — продукт проходу є downlink-наказ (override-`STOP`), алерт побічний.
- **Counter без gauge-двійника** — sweep стан УСУВАЄ тим самим проходом, тож «скільки зараз залипло» читалось би вічним нулем (на відміну від `gateways_faulty`, де faulty персистентний).
- **Носій = ВЛАСНИЙ тип `actuator_stuck`, не `system_fault` і не `field_audit`** — дзеркало того самого міркування, що й у tree-половині вище, але обидва «очевидні» кандидати отруєні по-різному: `system_fault` сидить у whitelist `comms_no_ack?` **І** поза виключеннями `critical_unmaintained?` (при активації cause-uplift — ПОДВІЙНИЙ штраф операторові за наш bookkeeping-збій), а cluster-level `field_audit` входить у `dark_cluster_ids` ↑ і **осліпив би per-tree dead-man switch на весь кластер**. Класифікація нового типу — дзеркало `firmware_fault`: vendor-attributable, не A-сет, не `comms_no_ack?`, виключений з `critical_unmaintained?` ([`05_05 §3.2`](05_05_Slashing_and_Risk_Policy)).

Машинного resolve НЕМА свідомо (фізичний стан пристрою невідомий — закрити алерт може лише людина, що подивилась на залізо); дедуп — per-actuator, бо на кластері їх кілька. ⚠️ **Стеля:** фізичного закриття не дає — актуаторної прошивки не існує ([`03_02 §6`](03_02_Queen_Gateway_Firmware)), `CMD:STOP` = forward-контракт, як і `duration_seconds`. Клас «БД чиста, а фізики не було» (втрачена 2.05-відповідь) цей sweeper НЕ ловить — дім [`00_07` FW.63](00_07_Action_Plan_Tracker). Механіка картки → [`04_02 §11`](04_02_Business_Logic_and_Services).

### 1.4 Dynamic Mesh Rerouting (Soldier-side)

Soldier'и **не знають**, що "їх" Queen впала. Вони продовжують TX. Але mesh-relay алгоритм (DEFAULT_TTL=3) природно прокидує пакет до сусідньої Queen, якщо вона у радіусі. Конкретно:

- Soldier емітує свій стандартний payload (DID + сенсори + TTL) — жодного `last_rssi_to_queen` Soldier **НЕ** передає (firmware: байт 4 = Vcap, [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); RSSI вимірює Queen при RX і додає його у Queen→backend 21-байт-фрейм ([`03_01 §8`](03_01_Firmware_Lifecycle_and_DMA)).
- Сусідній Soldier (Phase 4.5 RX window) ловить, помічає чужий пакет — якщо TTL > 0, релєює.
- Через 1–3 хопи пакет дотягується до сусідньої Queen у іншому кластері.
- Queen "B" — **"тупа труба" (dumb pipe):** вона НЕ читає і НЕ може прочитати, чий це пакет. Будь-яка Queen, що зловила валідний LoRa-фрейм Silken Net (за magic-байтом), просто загортає сирий зашифрований payload у CoAP і шле на бекенд. Бекенд розшифровує AES-блок, читає `DID` і визначає: «Soldier з кластера A передав через Queen B». Атрибуцію «через яку Queen» дає `queen_uid`, який Queen B ставить на **власну CoAP-обгортку** (вона знає свій UID), а НЕ читає з payload Солдата.

> **🔐 Корекція E2EE:** Попередня редакція стверджувала, що «Queen B читає чужий `queen_uid` у payload-метадаті». Це архітектурно неможливо: 21-байтовий пакет має у відкритому вигляді лише `DID` (4 байти) + `RSSI` (1), а 16-байтовий блок зашифрований **per-device AES-128** ключем ([`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)). Поля `queen_uid` у payload Солдата немає взагалі, і Queen B не має ключа Солдата з чужого кластера, щоб щось дешифрувати. Розшифрування — виключно на бекенді (Zero-Trust: Queen не є точкою plaintext).

> **Передумова:** Для надійності цього шляху необхідні TDMA Sync Windows (ARCH.26) + CAD (SX1262) — інакше mesh relay стохастичний. Це не блокує політику в принципі, але обмежує її TRL до 4-5 поки FW.20 / ARCH.26 не закриті. **Друга передумова (addressing):** opaque multi-hop relay потребує cleartext TTL/address-шару на LoRa-фреймі. Post-FW.2 (в) demux-половина вже вирішена (CCM AAD несе cleartext DID; двоключова модель [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security): session KEYL ізолює uplink — mesh-key для телеметрії НЕ вводиться, cluster-KEYB покриває лише control-plane), але TTL лишається у ciphertext → relay-декремент неможливий, mesh у CCM-еру мертвий (star-only, ухвала FW.2 (а)) — mesh-вісь [`00_07` — ARCH.43](00_07_Action_Plan_Tracker).

> **🔬 Open Research (академічна валідація надійності mesh):** формальна модель надійності flood-relay — **ланцюги Маркова** для TTL-маршрутизації + **теорія перколяції** (критичний поріг `q_c` фазового переходу, за яким мережа розпадається на ізольовані від Queen кластери) — математично обґрунтовує `PANIC_TTL=5`/`DEFAULT_TTL=3` і постачає `q_c` як науковий параметр тригера параметричного страхування ([`05_05`](05_05_Slashing_and_Risk_Policy) / [`07_01`](07_01_Nature_as_a_Service_Contracts)). **Machine-половина (Monte-Carlo `P_delivery`-свіп → TTL-justification) = self-owned** ([`00_07` — ARCH.74](00_07_Action_Plan_Tracker), `tools/mesh/`, 07-20 — патерн ARCH.25); повна `q_c`/Markov-теорія лишається Open Research-темою — двері відкриті ЧНУ-ФОТІУС (профіль [`07_03 §1.1`](07_03_Academic_Integration_and_IP)).

---

## 2. 🪜 Web3 Chain Fallback Matrix (Anti-Lego Tower)

### 2.1 Загальна абстракція: Local Buffer + Circuit Breaker

Жодна Web3-операція (peaq registration, IoTeX verification, Hadron compliance, KlimaDAO retire, Filecoin pin, L1 anchor) не повинна виконуватись **синхронно** в hot path Rails. Всі вони — Sidekiq workers (retry 3–5 за критичністю); `Web3CircuitBreaker` concern включають RPC-обличчя (iotex/chainlink-callback/celo/solana/mint) — воркери без прямого transact-обличчя (peaq/streamr/klima/anchor/filecoin/treasury) свідомо без нього ([`04_02`](04_02_Business_Logic_and_Services)).

Політика resilience:

1. **Buffer-first.** Запис у `TelemetryLog` / `BlockchainTransaction` / `AuditLog` відбувається **до** першої спроби Web3-виклику. Стан AASM `pending` / `processing` / `sent` / `confirmed` / `failed` / `manual_review` (див. `BlockchainTransaction` partitioning + `find_with_partition_pruning`).
2. **Circuit Breaker.** При `FAILURE_THRESHOLD = 5` підряд помилках відповідного RPC — circuit `opens` на `OPEN_TIMEOUT = 300 s` (лічильник у **Rails.cache / Solid Cache** — durable крізь Redis-рестарт; `app/workers/concerns/web3_circuit_breaker.rb`). При відкритому circuit виклик **fail-fast** (`CircuitOpenError` → Sidekiq retry з backoff) — job не б'є мертвий RPC.
3. **Exponential backoff retry.** За межами circuit breaker — стандартний Sidekiq retry з jitter.
4. **Manual review terminal state.** Якщо `tx_hash` отримано, але стан невизначений (double-spend guard) — переходить у `manual_review` AASM, кошти заблоковані до ручної перевірки.
5. **Graceful degradation.** Pipeline продовжує працювати на кроках, які НЕ залежать від downed ланки. Залежні кроки чекають у `pending`.

### 2.2 Per-Chain Fallback Policy

| Крок | Залежна ланка | Тип ризику | Fallback | Що блокує далі |
|------|---------------|------------|----------|----------------|
| 2. Akash hosting | Akash | Provider eviction, oracle price spike, no bidders | Multi-provider deployment (`deploy.yaml` SDL з multiple providers); fallback на GCP via Kamal ([`06_01`](06_01_Deployment_Kamal_Terraform)) — `kamal redeploy --hosts canopy` **+ перемкнути upstream Ingress Anchor** (HAProxy/socat Akash→GCP, [`06_02`](06_02_Akash_Network_Integration) розділ «Ingress Anchor»). **Queens НЕ потрапляють у «чорну діру»:** CoAP йде на *статичний IP Ingress Anchor* (e2-small), де його приймає **демон прямо на анкорі** (PRIMARY — INF.17, 2026-07-04) → Akash-евікшн CoAP-інтейк взагалі НЕ зачіпає; при відмові самого демона fallback = `systemctl stop coap-daemon && systemctl start coap-relay` (socat → Akash `coap`-сервіс, який лишається задеплоєним idle). Endpoint Королев незмінний за будь-якого сценарію. DNS-рівень (зміна A-запису `api.silkennet.com`) як zero-infra глобальний failover host-shipped [FW.58]: після N=3 flush-провалів підряд Королева інвалідує CDNSGIP-кеш → re-resolve без ребута (механізм — [`03_02 §4`](03_02_Queen_Gateway_Firmware); bench-verify на живому SIM7070 → [`00_07`](00_07_Action_Plan_Tracker) FW.58). | Цілий backend (всі 12 наступних кроків) — тому Akash redundancy P0. |
| 3. Streamr P2P | Streamr Network | Streamr API rate-limit / outage | Non-blocking publish (`StreamrBroadcastWorker`, `queue: low`, retry: 3). При остаточному фейлі — лог + `silkennet_streamr_broadcast_failures_total` (🟡 target: buffer-list undelivered-payload'ів не реалізовано — [`00_07` INF.22](00_07_Action_Plan_Tracker)). Власний P2P через ActionCable websockets залишається активним. | Нічого. Streamr — спостерігач, не gate. |
| 4. peaq DID | peaq Network | peaq RPC down, registration revert | `PeaqRegistrationWorker` retry 5×; якщо все ще fail — `tree.peaq_did` залишається `nil`, telemetry **буферизується** у `TelemetryLog` (`oracle_status_pending`). Коли peaq оживає — реєстрація йде наступними retry/enqueue. 🟡 target: авто-backfill після довгого простою + alert `peaq_long_outage` — не реалізовані (INF.22). **`did:local:fallback` ВИДАЛЕНО** (див. ⚠️ нижче). | PATH 1-верифікації (IoTeX). Живий PATH 2-мінт НЕ гейтиться IoTeX/peaq (ARCH.53 — guard = KYC), Solana/Celo не блокуються. |
| 5. IoTeX W3bstream | IoTeX | API zaspamlena, ZK-proof generation failed | `IotexVerificationWorker` (web3_critical, retry 5); стан `verified_by_iotex=false` буферизується у `TelemetryLog`. 🟡 target: `IotexBackfillWorker`-cron НЕ реалізований — сам воркер чесно коментує «recovery-крони нема»; recovery = ручний re-enqueue (INF.22). НЕ money-блокер: PATH 2-мінт IoTeX не гейтиться (ARCH.53). | PATH 1 latent-ланцюг. |
| 6. Chainlink (callback-only) | Chainlink DON | — (on-chain dispatch ВИЛУЧЕНО — ARCH.53-демоут) | `Chainlink::OracleDispatchService` = **local correlation-marker без RPC** (dedup-ключ Solana ARCH.51 + idempotency); callback-endpoint (`/api/v1/oracle_callbacks`, HMAC) живий для майбутнього PATH 1 / manual fulfillment. LINK-баланс НЕ моніториться (Treasury дивиться MATIC/SOL/CELO/ETH) — moot: PATH 1 закривати відмовлено (founder 2026-07-19, ARCH.53 §🗄️). | Нічого (dispatch більше не в Critical-Path — [`05_01 §8`](05_01_Multichain_Architecture)). |
| 7. Solana micro-rewards | Solana | RPC eviction, ATA missing, low SOL у gas wallet | ✅ **fallback-каскад** `SOLANA_RPC_URL_FALLBACK_*` (INF.22) — `Solana::MintingService#execute_rpc_call` пробує primary→fallback по черзі, per-service circuit-breaker "Solana" (`Web3::HttpClient`, 3 збої/60с); skip-clean (порожні → single-RPC). Solana ≠ EVM, тож не `ResilientClient`. Додатковий durable-захист: intent-marker + hourly reconcile (`BatchPayoutService`), `:not_found` on-chain → `manual_review` (ARCH.45/ARCH.51) — RPC-фейл не губить кошти, лише затримує. | Нічого. ⚠️ Micro-reward enqueue лише з unwired oracle-callback (ARCH.53 демоут) → pipeline зараз **latent** (PATH-1 сім'я, як IoTeX B1); «самодостатня» стосується durable-механіки, не досяжності. |
| 7. Celo ReFi | Celo | Forno RPC down, низький cUSD balance | Multi-RPC fallback (E.49 `RPC_FALLBACK_ENV_KEYS` = `CELO_RPC_URL_FALLBACK_1/2`, [`04_02`](04_02_Business_Logic_and_Services)) + dedicated signer ARCH.50. Якщо всі RPC down → Sidekiq-retry; durable-захист = intent-marker + `CeloConfirmationWorker` reconcile для `:sent`. **Застрягле `:pending` без tx_hash (transient-timeout → dedup-skip, self-masking) → `CeloRewardReconcileWorker` sweep (:25/:55) → `:manual_review` (ARCH.64 — раніше тиха недоплата cUSD).** (🟡 target буфер-list `celo_pending_payouts` не реалізовано — INF.22.) | Нічого (Celo — самодостатня rail). |
| 8. Polygon + Hadron | Polygon EVM + Hadron compliance | Polygon RPC saturated, Hadron KYC service down | Polygon: `Web3::ResilientClient` circuit breaker + retry. Hadron: `hadron_kyc_status` — **персистентна колонка** wallet (НЕ кеш із TTL): уже-approved гаманці мінтяться і при лежачому Hadron; нові KYC чекають — **`HadronKycVerificationWorker` exhaust (retry:5, разовий `after_commit`-enqueue) → `HadronKycReverifyWorker` cron (:50) доверифіковує застряглі `pending` (ARCH.65 — інакше pending-KYC → тихий mint-skip назавжди).** `MintCarbonCoinWorker` retry 5× → `MintingRollbackService` → `manual_review` при невизначеному стані. | Крок 9 (The Graph) — оскільки graph індексує Polygon events. |
| 9. The Graph | The Graph hosted service | Subgraph health degraded, indexing lag >1 година | Read-side тільки: `TheGraph::QueryService` при фейлі raise `QueryError` (дашборд деградує). 🟡 target: direct-RPC `eth_getLogs` fallback НЕ реалізований (INF.22); mint flow не блокується. | Нічого (read-side). |
| 10. KlimaDAO | Polygon (KlimaDAO contracts) | Contract paused, approve revert | `KlimaRetirementWorker` (retry 3) існує, але **DEAD — 0 enqueue-сайтів** (узгоджено з [`06_02`](06_02_Akash_Network_Integration): активація = свідоме рішення). 🟡 target при активації: manual_review-хвіст + `ProtocolParameters`-toggle + ARCH.49 nonce-lock. | Нічого (retirement — окрема rail, не блокує emission). |
| 11. Filecoin/IPFS | Pinata / Web3.Storage | API limit, CID not pinned | `FilecoinArchiveWorker` retry 5×. **Джерело правди — НЕ локальний диск:** `AuditLog`-рядки з `chain_hash` уже персистяться у **PostgreSQL (managed Cloud SQL, поза Akash-подом)**, тож при недоступності Pinata нічого не втрачається. ✅ `FilecoinReconcileWorker` (daily :48 re-pin **outbox-marked** логів `AuditLog.pending_archive`) + detect-половина (`FilecoinArchiveWorker` `sidekiq_retries_exhausted`-hook + `silkennet_filecoin_unarchived_depth` gauge + P2-alert) — INF.22 крок 11 SHIPPED 2026-07-07. | Нічого (audit immutability — у durable Postgres, не на ефемерному диску). |
| 12. Ethereum L1 anchor | Ethereum mainnet | Gas spike, RPC down | `EthereumAnchorWorker` (cron `0 3 * * 1`, `unique_for: 7.days`): фейл тижня → Sidekiq retry; `detect_missed_anchor_weeks!` (gap > 8 днів → warn + `silkennet_anchor_missed_weeks_total`) робить пропуски видимими. gas-price-гейт (`MAX_ANCHOR_GWEI`) ✂️ **ВІДХИЛЕНО** (net-negative: max_fee cap уже дає opportunistic-landing + weekly-cron coupling → гарантований пропуск тижня + single-RPC censorship; 5-агентний red-team 07-07). [`ARCH.66`](00_07_Action_Plan_Tracker) ✅ **SHIPPED** (confirmation-lifecycle): `EthereumAnchorConfirmationWorker` (poll receipt → `:confirmed`/`:failed`/`:manual_review`; reorg-depth gate 64; enqueue після `:sent`) + `StuckSentAnchorSweeperWorker` (cron :40, re-arm застряглого `:sent` — read-only, НІКОЛИ re-broadcast) + `detect_missed` звужено на `[:confirmed]`. Метрики `ethereum_anchor_stuck_sent_depth`/`_manual_review_depth`/`_reverted_total` + alert'и (stuck-sent P1 · manual-review P1 · reverted P2 · anchor-stalled P1). Poll retries_exhausted робить фінальний receipt re-check перед escalate (дзеркало `MintingRollbackService`). Активація gated на деплой контракту (SEC.1). Анкор толерує multi-week gap by design. | Нічого (anchor — finality, не runtime). |

> **⚠️ Zero-Trust корекція: `did:local:fallback` для мінтингу видалено.** Минтити з локальним фейковим DID безглуздо й небезпечно: крок 5 (IoTeX W3bstream) генерує ZK-доказ, звіряючи підпис (наразі master-backed, не device-bound — true-DePIN ladder [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)) із **зареєстрованим на-чейн peaq DID**. Без реального on-chain DID ZK-провера не знайде публічного ключа → `verified_by_iotex?` = `false` → guard clause мінтингу блокує його **в будь-якому разі**. Тобто local-DID не «розблоковує» мінт, а лише ризикує приписати вуглецеві кредити неперевіреному походженню. Правильно: телеметрія спокійно чекає у `pending`, а коли peaq оживає — DID дореєстровується і IoTeX дозаганяється. Краще зачекати на легітимний консенсус, ніж пропхати дані «костилем».

### 2.3 Worker Configuration (Sidekiq) — фактичний патерн

Реальна механіка (`app/workers/concerns/web3_circuit_breaker.rb` + воркери; чесність-пас 2026-07-04 — попередня редакція показувала неіснуючий шаблон із `sidekiq-unique-jobs`/`lock_timeout`/кастомним `sidekiq_retry_in`):

```ruby
class XxxWorker
  include Sidekiq::Worker
  include Web3CircuitBreaker          # RPC-обличчя: iotex/celo/solana/mint/chainlink-cb

  sidekiq_options queue: :web3, retry: 5   # 3–5 за критичністю; дефолтний Sidekiq-backoff

  def perform(...)
    with_circuit_breaker("polygon") do   # open ⇒ raise CircuitOpenError (fail-fast)
      # ... web3 call
    end
  rescue Web3CircuitBreaker::CircuitOpenError
    raise   # → Sidekiq retry set із стандартним exponential backoff
  end
end
```

- **Fail-fast, не busy-spin:** при відкритому circuit виклик миттєво `raise` → job іде у Sidekiq **retry set** (знімається з active) зі стандартним backoff — мертвий RPC не б'ється, черга не «пережовується». Унікальність там, де вона money-несуча, дає **Sidekiq Enterprise unique-shim** (`lock:` у batch-payout/treasury/collector) + durable intent-marker'и ARCH.45 — НЕ gem `sidekiq-unique-jobs`.
- 🟡 **target (INF.22):** reschedule-on-open через `perform_in(cooldown)` — точніше повернення «рівно в кінець cooldown» замість експоненційної сітки; цінно на високому ingest, зараз YAGNI (Sidekiq-backoff з головою на TRL-обсязі).

> **Чому НЕ `Sidekiq::Queue.new(:web3).pause`:** circuit breaker — **per-RPC** (Polygon / Solana / peaq…), а черги `web3`/`web3_critical` спільні для багатьох чейнів. Пауза всієї черги зупинила б і **здорові** чейни. Fail-fast-у-retry зберігає per-chain гранулярність. Чисту queue-pause можна застосувати лише якщо кожен чейн отримає окрему чергу (рефактор, Phase 2).

### 2.4 Resilience SLO

| Метрика | Target | Як вимірюється |
|---------|--------|----------------|
| Telemetry intake survival при Queen offline | ≥ 95% за 24 год | Queen self-telemetry CIFO fill + Helium fallback hit rate |
| Mint flow availability при single Web3-chain outage | ≥ 80% (degraded but functional) | Prometheus `silkennet_mint_success_total / silkennet_mint_attempts_total` over 1h windows |
| Recovery to full pipeline after multi-chain outage | < 4 год once external chains restore | Sidekiq retry-drain + reconcile-крони (ARCH.45; Filecoin re-pin ✅ shipped) + Solana RPC-каскад; 🟡 target-вимір: IoTeX backfill не реалізований — INF.22 |
| No data loss when all external chains down for ≤ 24 год | 100% — все буферизується | `TelemetryLog.count`, `BlockchainTransaction.where(state: :pending).count` зростання без втрат |

**Емпіричний вимір стелі:** INF.23 load-harness (`lib/silken_net/load_test/` + `bin/coap_load`) міряє ці SLO проти живого стека — backlog→μ, arrival→sustainable-λ, сценарій S6 прямо валідує §2.5 process-ізоляцію (firehose ‖ money → starvation → flip → обидва SLO). ⚠️ dev-прогін = regression+structural detector (bottleneck-class inversion: dev compute-bound, prod IO-bound); абсолютна стеля — лише staging з prod-adapters. GVL-мікробенч уже показав pure-Ruby Lorenz-стелю ПЛОСКОЮ (горизонталь = процеси, не треди). Методологія + 6 сценаріїв + staging-runbook: `lib/silken_net/load_test/README.md`.

### 2.5 Money-path Queue Topology (ARCH.52 — anti-starvation at planetary scale)

**Проблема (planetary-обсяг, ~100 млрд дерев).** `config/sidekiq.yml` має `:strict: true` — у межах процесу черги дренажаться згори-вниз, нижча НІКОЛИ не випереджає вищу. Money-черги стоять НИЖЧЕ за intake: `uplink`(1) > `alerts`(2) > `critical`-slash(3) > … > `web3_critical`-mint(6) > `web3`(7). На planetary-обсязі `uplink` = вічний firehose телеметрії → під strict він дренажиться першим, а mint / slash / insurance / `BlockchainConfirmationWorker` **голодують** (money-throughput → 0; clawback-race на затриманому slash). Це НЕ priority-inversion — це коректний strict; money просто стоїть за intake. Перестановка черг лік не дає (підняти money над uplink = пожертвувати intake-SLO §2.4 ≥95%).

**Рішення — process-рівнева ізоляція (deploy-config, НЕ код).** Запускати **виділений money-path Sidekiq-процес** на черги `critical, web3_critical, web3, alerts` ФІЗИЧНО окремо від процесу intake (`uplink, downlink, default, …`). Кожен процес дренажить свій strict-ланцюг незалежно → firehose в `uplink` більше не може випередити mint/slash (детерміновано unstarvable thread-reservation). Обидва SLO §2.4 задоволені одночасно: intake-процес тримає intake ≥95%, money-процес тримає mint-availability ≥80%.

**Чому НЕ weighted-черги (drop `:strict`).** Weighted = probabilistic: під firehose не *гарантує* money-throughput І жертвує true critical-precedence (slash МУСИТЬ вигравати детерміновано). Strict + process-ізоляція > weighted на обох вимірах.

**Тригер flip'у (зараз НЕ потрібен — TRL-3, firehose ще немає).** Single-process baseline (`deploy.yml` job-role + Akash `count: 1`) коректний поки intake малий. Розділяти, коли: (а) `uplink`-backlog росте необмежено, АБО (б) mint-availability SLO (§2.4 `silkennet_mint_success_total / attempts`) пробиває ≥80%. Механізм flip'у = `sidekiq -q`-прапори per-процес у deploy-конфізі (reversible, без коду). ⚠️ Drift-ризик: список черг дублюється у deploy-місцях ([`06_02`](06_02_Akash_Network_Integration)). Розвиває §2.3 Phase-2 per-chain queue-split (та сама вісь — окремі процеси/черги).

### 2.6 Partition-prune scope (ARCH.52 — money-path hot-path queries)

`BlockchainTransaction` RANGE-партиційовано по `created_at` (композитний PK `(id, created_at)`). Запит без `created_at`-предиката → full-scan усіх партицій (O(P × log N)). Два РІЗНІ інструменти прунингу — за формою запиту:

- **Known-row lookup (id/tx_hash відомий) → `created_at`-вікно.** `BlockchainConfirmationWorker` несе `created_at_iso` (**6 із 7** enqueue-сайтів прокидають; сьомий — `PuroEarthPassportWorker`, і там це не недогляд, а наслідок глибшого: Puro не створює рядка `BlockchainTransaction` узагалі, тож прунити нема до чого — [`PERF.1`](00_07_Action_Plan_Tracker)) і фільтрує **LOWER-bound** `created_at >= earliest-1h`. ⚠️ Чому lower-bound, не симетричне ±1h: batchMint ділить ОДИН `tx_hash` на ≤100 рядків з РІЗНИМИ `created_at` (collector акумулює pending з широким span; reset-to-pending тримає старий `created_at`) → симетричне вікно виключило б рядки, новіші за earliest+1h → stuck `:sent`. Дзеркало `CeloConfirmationWorker` (ARCH.50).
- **Status-scan (множина невідома, може містити старі рядки) → partial index, НЕ `created_at`-вікно.** Pending-discovery (`Treasury::MintBatchCollectorService`, `MintCarbonCoinWorker`) НЕ може взяти `created_at` нижню межу: `MintCarbonCoinWorker` на RPC-error робить raw `update_all(:processing → :pending)` (зберігає старий `created_at`), а `MAX_PENDING_AGE_MINUTES` робить старі pending *urgent* (їх ТРЕБА знайти) → межа осиротила б stranded funds. Прунинг = **partial index** `index_blockchain_transactions_in_flight` `(status, created_at) WHERE status IN (0,1)` (pending+processing — крихітна частка all-time рядків) → full-scan стає index range-scan.
- **Свідомо НЕ прунимо (design):** slash `total_minted` sum (`BlockchainBurningService`) + anchor SFC-supply sum (`Ethereum::StateAnchorService`) = **all-time aggregates**, семантично unprunable (потребують усієї історії); long-term cost-opt = denormalized counter / on-chain `totalSupply` (як `ChainAuditService`), не partition-prune. `⚠️ **`BlockchainMintingService#initialize` з цього переліку ВИБУВ 2026-08-07** ([`PERF.1`](00_07_Action_Plan_Tracker)): тут стояло «`where(id:)` вже index-served по PK leading-колонці `id` per-partition (partition-count = малий обмежений constant)». Підстава правдива щодо ІНДЕКСУ й не та щодо ВАРТОСТІ — «index-served per-partition» означає окрему пробу в КОЖНІЙ партиції, і виміряно EXPLAIN'ом: `where(id: […])` торкається всіх листів, із `created_at`-вікном — **одного**. Тепер лійка бере `created_at_span` (`BlockchainTransaction.where_ids_pruned`) — це підказка планувальнику, не фільтр: межі беруться з `created_at` тих самих рядків, чиї id передано, тож множина не змінюється. 🔴 Урок форми: «партицій мало, тож пробувати кожну дешево» — це аргумент, який ЗАСТАРІВАЄ сам по собі, бо листів +1 щомісяця й retention-політики не існує.

---

## 3. 🧰 Реалізаційні Якорі (Implementation Anchors)

| Концепція | Файл / Сервіс | Статус |
|-----------|---------------|--------|
| Web3 circuit breaker (5 фейлів → 300 s open, Rails.cache, fail-fast) | `app/workers/concerns/web3_circuit_breaker.rb` ([`04_02`](04_02_Business_Logic_and_Services)) | ✅ Реалізовано |
| Multi-RPC fallback — **Celo** (`RPC_FALLBACK_ENV_KEYS`) | `Celo::CommunityRewardService` (E.49 in [`00_07`](00_07_Action_Plan_Tracker)) | ✅ Реалізовано (Solana/Polygon-каскади — 🟡 INF.22) |
| Queen-пульс: QATT-v2 health-блок + dead-man switch (DID=0-канал ВБИТИЙ — ARCH.54) | `enqueue_envelope_health` → `GatewayTelemetryWorker` · `GatewayStalenessSweepWorker` (§1.3) | ✅ Реалізовано |
| CoAP retry loop on Queen (`COAP_MAX_RETRIES`) | `firmware/queen/main.c`; host-tests `test_at_engine.c` (conversation-fail) + `test_fw51_*` (fail→retry→no-loss), FW.9 | ✅ Реалізовано |
| Manual review terminal state | `BlockchainTransaction` AASM | ✅ Реалізовано |
| Money-path crash-window idempotency (intent-marker + `in_flight` guard) | `BlockchainBurningService` / `Solana::BatchPayoutService` ([ARCH.45], [`04_02 §4/§10`](04_02_Business_Logic_and_Services)) | ✅ Реалізовано |
| Backfill/buffer-list механізми матриці §2.2 (IoTeX backfill · streamr/celo buffer) | — | 🟡 target-пакет [`00_07` INF.22](00_07_Action_Plan_Tracker) (Solana RPC-каскад + Filecoin re-pin ✅ shipped; anchor gas-gate ✂️ rejected → ARCH.66 — §2.2) |
| Stuck-`:sent` mint re-arm sweeper (EVM-scoped, cron 30 хв) | `StuckSentTransactionSweeperWorker` | ✅ SHIPPED (ARCH.55; дім — [`04_02 §4`](04_02_Business_Logic_and_Services)) |
| Puro-анкер confirmation-lifecycle (PERF.1(д): `biomass_passport_status` + receipt-полл; Phase 3 REST гейтована `:confirmed`) | `PuroEarthConfirmationWorker` ([`04_02 §5`](04_02_Business_Logic_and_Services)) | ✅ SHIPPED 2026-08-20 · ⚠️ stuck-`:sent` sweep СВІДОМО deferred до активації шляху (`ORACLE_PURO_PRIVATE_KEY`; recovery = console re-enqueue) — [`00_07` PERF.1](00_07_Action_Plan_Tracker) |
| Queen-to-Queen Backhaul Mesh | §1.2 L2-рядок (спека — дім тут) · [`00_07` — ARCH.10](00_07_Action_Plan_Tracker) | 🟡 Concept, planned Phase 2 |
| Helium fallback emit (Queen-side LoRaWAN) | Queen firmware `queen_helium_lorawan_uplink()` | 🟡 ARCH.34: обв'язка+wire+тригер+MAC-adapter+повний host-цикл join+uplink (мок-LNS)+KV-mount ✅ 2026-07-05 (гейт `ARCH34_HELIUM_ENABLED 0`); лишився bench OTAA-ефір + Helium Console (👤); backend ✅; Soldier-side відкинуто — Soldier не несе LoRaWAN MAC stack |
| Ingress Proxy (Rust/Go CoAP buffer, Series D) | ARCH.2 / E.5 | 🟡 far-horizon |
| Conductor L2 cluster heads (formerly "Sergeant") | [`00_07` ARCH.1](00_07_Action_Plan_Tracker) | 🟡 Concept (ARCH.1, TRL 1) |

---

## 4. 📖 Web3 Incident & Contract-Ops Runbooks

> [CONTRACT.1(5)] + [MRV.1(4)]: web3-специфічні інциденти й one-shot contract-операції — незворотні або фінансово-критичні, тому крок-за-кроком ТУТ, а не в голові оператора. Загальний DR (БД/інфра) — [`06_06`](06_06_Disaster_Recovery_and_Backup); секрет-компрометація peaq — [`06_04 §5.4`](06_04_Secrets_Checklist). Резолюція `manual_review` — свідомо **console-рецепт, не admin-UI** (founder-рішення 2026-07-04: один оператор, UI до першої реальної ops-потреби не будуємо; compliance вимагає ПРОЦЕС).

### 4.1 Chain reorg (Polygon): `:confirmed` tx зник з ланцюга

**Симптом:** `sn-alert-chain-audit-drift` (`silkennet_chain_audit_delta > 0`) АБО `eth_getTransactionReceipt(tx_hash) → null` для tx зі статусом `:confirmed`.

1. НЕ ре-мінтити вручну. Зафіксувати scope: `BlockchainTransaction.confirmed.where(confirmed_at: reorg_window)` + звірити кожен `tx_hash` через RPC.
2. Receipt відсутній ПІСЛЯ finality-вікна (~256 блоків Polygon) → `tx.escalate_to_review!` (кошти назад у `locked_balance`-охорону, двозначність = manual_review за дизайном).
3. Receipt з'явився в іншому блоці → false alarm (RPC-лаг), нічого не робити.
4. Масовий reorg (>10 tx) → `pause()` з Safe на час розбору; slash навмисно працює під паузою (B-07).
5. Постмортем: тижневий L1-anchor ([`05_04`](05_04_Ethereum_L1_State_Anchor)) = зовнішня точка звірки, якщо reorg глибший за локальні дані.

### 4.2 Підозра double-mint / rogue MINTER

**Симптом:** `chain_audit_delta > 0` стабільно 30+ хв (alert) АБО subgraph `CarbonMinted`-події без відповідного `BlockchainTransaction`-інтенту.

1. `Treasury::MonitorService`-зріз: `ChainAuditService.call` → який знак delta (on-chain > DB = зайвий мінт; DB > on-chain = недолік/rollback-дірка).
2. Атрибуція: subgraph-запит подій за вікно → зіставити `contextHash` ([CONTRACT.1] = `bytes32(intent tx id)`; порожній contextHash у `TokenSlashed` = manual-slash, у mint-подій інтент шукати по `to`+`amount`+блок-вікну).
3. Подія БЕЗ інтенту = ознака compromised MINTER-ключа → негайно §4.3.
4. Зайвий мінт підтверджено → clawback-трек: `slashUpTo` на суму over-mint (SLASHER-ключ незалежний) + інцидент у `AuditLog`.

### 4.3 Компрометація money-ключа (MINTER / SLASHER EOA)

> Ролі фізично розділені (E.2): компрометація одного ключа НЕ дає другого. `pause()` = Safe (миттєво); `revokeRole` = Timelock (48h) — **slash оминає паузу (B-07), тож для SLASHER-компрометації 48h-revoke = єдиний повний стоп**; для MINTER — пауза зупиняє мінт одразу.

1. `pause()` з Gnosis Safe (зупиняє mint/transfer; slash лишається живим — це свідомо).
2. Одночасно: Timelock-proposal `revokeRole(<COMPROMISED_ROLE>, <oldOracle>)` + `grantRole(<ROLE>, <newOracle>)` — годинник 48h пішов.
3. Ротація бекенда: новий ключ у `ORACLE_MINTER_PRIVATE_KEY` / `ORACLE_SLASHER_PRIVATE_KEY` (GitHub Secrets → redeploy; [`06_04 §5`](06_04_Secrets_Checklist)); до set-часу воркери молотять у revert → черга `web3_critical` тримає (retry+DeadSet, [`04_02`](04_02_Business_Logic_and_Services)).
4. SLASHER-кейс: 48h-вікно — моніторити `TokenSlashed`/`GovernanceSlashed` (масовий slash = атака; `sn-alert`-метрики `SCC_SLASHED_TOTAL`); постраждалі суми = clawback/re-mint ПІСЛЯ revoke.
5. `unpause()` лише після: revoke виконано + нові ключі верифіковані smoke-мінтом на 1 wei-екв.

### 4.4 `manual_review`-резолюція (console-рецепт — двозначні money-tx)

> `manual_review` = double-spend guard (tx_hash є, on-chain доля невідома; age-unbounded — блокує re-fire назавжди, [`04_02 §4`](04_02_Business_Logic_and_Services)). НЕ авто-резолвити. Кожна резолюція — з on-chain доказом.

```ruby
tx = BlockchainTransaction.manual_review.find(<id>)
receipt = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
            .eth_get_transaction_receipt(tx.tx_hash)   # Solana → getSignatureStatuses

# (а) Receipt SUCCESS → гроші пішли: фіналізуй як confirmed
tx.confirm!   # AASM-хук звільнить locked_points дискримінатором

# (б) Receipt REVERTED → безпечно провалити: fail! поверне locked_balance (M2-хук)
tx.fail!

# (в) Receipt null ПІСЛЯ finality-вікна → tx не існує on-chain: fail! + за потреби
#     re-enqueue штатним шляхом (MintBatchCollector підбере :pending)
```

Після резолюції: запис в `AuditLog` (`action: "manual_review_resolved"`, metadata: tx_hash + рішення + receipt-статус) — tamper-evident слід для MRV-аудитора ([MRV.1]).

### 4.5 Contract-ops one-shot (незворотні операції)

**Deploy-smoke (Amoy → Mainnet, до трансферу ролей):**
1. `forge script script/Deploy.s.sol --rpc-url $AMOY` → зафіксувати адреси. ⚠️ run() вимагає **всі 6 ENV** (incl. `DAO_TREASURY_ADDRESS` — читається лише для custody-гейта) навіть на dry-run; без `REQUIRE_SAFE_ADMIN` custody/key-split дають warn, не revert.
2. Роль-матриця: `Deploy.t.sol`-пін виконується і на живому деплої — прогнати `test_*_adminIsTimelock_notSafe`-еквіваленти читанням `hasRole` по кожному контракту.
3. Smoke: mint 1 SCC → transfer → `pause()` → переконатись mint revert → `slashUpTo(1, ctx)` під паузою ✅ → `unpause()`.
4. ЛИШЕ після зеленого smoke: transfer admin → Timelock ([`00_07` SEC.1](00_07_Action_Plan_Tracker)) — незворотний крок.

**Migration (контракти immutable):** «міграція» = новий деплой + supply-cutover: `pause()` старого → snapshot балансів (subgraph/`ChainAuditService`) → batchMint у новому за snapshot → анонс + оновлення адрес у ENV/subgraph (S3.5-процедура). Старий контракт лишається paused назавжди (історичний ланцюг доказів для MRV).

**Pause/unpause:** тільки Gnosis Safe (PAUSER_ROLE, миттєво, поза Timelock); причина + timestamp → `AuditLog`; slash працює під паузою (B-07) — це фіча, не баг.

### 4.6 Field-Audit ескалація C→A (console-рецепт — відкриває ворота необоротного slash)

> [SLASH-1] **Єдиний живий шлях до positive-A.** Автоматичного writer'а `vandalism_breach` немає за дизайном (wire status=3 = `vm_error` → `firmware_fault`; пилка → `chainsaw_detected`, поза A-сетом до field-validation) — тож доки людина не ескалює, КОЖЕН slash-тригер іде freeze/Field-Audit (`Slashing::CauseEvidence#positive_a?` = tamper-only). Політика + межі A-сету — [`05_05 §3.2`](05_05_Slashing_and_Risk_Policy); процедура Кат-C peer-review — [`05_05 §5`](05_05_Slashing_and_Risk_Policy). ⚠️ Крок незворотний за наслідком: після нього наступний `BurnCarbonTokensWorker` по цьому кластеру палить, а не морозить.

**Передумова:** прямий ФІЗИЧНИЙ доказ втручання, зафіксований людиною на місці (розкритий корпус, зрізаний/викопаний анкер) — з актом і фото. Непрямий сигнал (тиша, divergence, аномалія Z, акустика без field-validation) Кат-A **не дає** — [`05_05 §6`](05_05_Slashing_and_Risk_Policy) вимагає прямого некорельованого підтвердження.

```ruby
cluster = Cluster.find(<id>)

# Ескалація C→A. `severity: :critical` обов'язковий — гейт читає `.critical`
# (= severity_critical.unresolved), medium/low ворота не відчиняють.
# ⚠️ Колонки `message` НЕМАЄ з 2026-07-26 — алерт народжується там, де локалі глядача
# не існує, тож проза не зберігається (`04_01 §7`). Рецепт із `message:` кидав
# `ActiveModel::UnknownAttributeError` (виміряно рантаймом 2026-08-13), тобто ЄДИНИЙ
# людський шлях відчинити ворота Кат-A не виконувався. Параметри несуть ВИМІР
# (ідентифікатори акта/фото/вузла), ніколи фрагмент фрази.
EwsAlert.create!(
  cluster: cluster,
  tree:    <Tree|nil>,          # опційно — для атрибуції в аудиті; гейт cluster-scoped
  severity: :critical,
  alert_type: :vandalism_breach,
  message_key: "field_audit_escalated_c_to_a",
  message_params: { date: "<дата>", uid: "<uid вузла>", act: "<N>", photo: "<ref>" }
)

Slashing::CauseEvidence.new(cluster).positive_a?   # → true (ворота відчинені)
```

**Відкликання** (доказ не підтвердився): `alert.resolve!(user: <auditor>, notes: "...")` → гейт знову закритий (`positive_a?` читає лише unresolved). ⚠️ `resolve!` **з `user:`** — машинний resolve (`resolved_by` NULL) зарезервовано за sweeper'ом і має окремий сенс у penalty-тракті (gap-E, [`05_05 §6`](05_05_Slashing_and_Risk_Policy)).

Після ескалації: запис в `AuditLog` (`action: "field_audit_escalated_c_to_a"`, metadata: cluster_id + акт + фото-ref) — tamper-evident слід для MRV-аудитора ([MRV.1]). `vandalism_breach` свідомо виключений з `comms_no_ack?`/`critical_unmaintained?` (P1-3 self-ref: доказ A не має ще й накручувати penalty на собі).

### 4.7 Archive-batch `mismatch` / zero32-мінт (E.60 Фаза 1б — integrity, НЕ money)

> Механіка/семантика тракту — [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline). Money-периметр НЕ зачеплений: батч-стани живуть на `TelemetryArchiveBatch`, tx-AASM недоторканий — жоден крок тут не рухає кошти.

- **`mismatch`** (rebuild-root ≠ stored при живих логах; алерт по `…archive_batch_failures_total{reason="mismatch"}`): root уже поїхав on-chain — артефакт НЕ запінено (guard). Розслідування: `batch.blockchain_transactions` → вікна → знайди мутований лог (порівняй `Mrv::TelemetryLeaf.cid_for(log)` з `log.merkle_leaf`, якщо стемп встиг; sweeper-нога зазвичай показує `leaf_stamp_drift` поруч). Мутація = інцидент цілісності БД (raw-SQL повз seal-guard) — джерело шукати в git/логах, стан батчу лишити `mismatch` як слід; on-chain root ЧЕСНИЙ на момент диспатчу (артефакт відновлюваний лише якщо мутацію відкотили).
- **Repaired-`build_failed`** (пізній rebuild вдався — `repair!` → пін): root живе off-chain-only, chain на той мінт уже поїхав zero32 — легально за семантикою «zero32 = без witness-клейму»; артефакт = off-chain доказ, аудитор бачить розбіжність чесно.
- **Abandoned-`build_failed`** (repair неможливий: усі tx уже в інших батчах / вікна порожні — `abandon_repair!` → `superseded`): доказ невиправний, root лишається NULL, рядок виходить із `.reconcilable` (daily-backstop більше не чіпає). НЕ інцидент — dead-end слід; chain на той мінт уже поїхав zero32.
- **zero32-мінт при непорожніх персистованих вікнах** (алерт `reason="build"`): тракт зламався, гроші течуть (fail-open за дизайном) — лагодити тракт, НЕ зупиняти мінт; вікна персистовані → пізній repair намагається відновити доказ (успіх/неможливість → два буллети вище).
