# 00_03: TRL Matrix, HIL & Beyond-TRL-9

## 🎯 Мета

Канонічний дім **per-module TRL-матриці** (§1), принципу **TRL-Layered-Independence** (§2) та **HIL-симуляторів** (§3) — поточний стан готовності + метод його вимірювання. HIL — **програмні еквіваленти фізичного навантаження**, що дозволяють софт-доменам незалежно досягати свого *per-domain* TRL. ⚠️ HIL **НЕ «знімає» System-TRL-Lock** (той лишається обмеженим найнижчим модулем критичного шляху) — він лише декаплить per-domain прогрес. Далекогоризонтна R&D-агенда **за межами TRL 9** (Planetary Intelligence + фрактальне масштабування) винесена у [`00_08`](00_08_Beyond_TRL9_Planetary_Roadmap). Near-term дорожня карта (фази масштабування) — у [`00_01`](00_01_Vision_Mission_and_Roadmap).

---

## ✅ Статус

- **Поточний TRL (System):** TRL 4 — EBFC TRL 3→4 PASSED (Zero-Lab 2026-05-25). Програмні домени TRL 6-9.
- **Per-domain TRL (декаплінг):** суть зняття TRL-Lock — програмні домени (Rails, Web3, Firmware, Security) рухаються до TRL 8–9 незалежно від фізичного відставання металу/хімії (anchor/EBFC **TRL 4**, Zero-Lab L1-L4 PASSED 2026-05-25; in vitro Stages 1-3 ще не закриті). **Канонічні per-module числа — `§1 Per-module TRL` нижче (єдиний дім; тут свідомо НЕ дублюються, щоб уникнути drift).** Оновлюється при кожному cool-down.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_01` — Vision Mission and Roadmap](00_01_Vision_Mission_and_Roadmap) | Бізнес-візія та slashing |
| [`00_02` — AI Native Engineering and TRL](00_02_AI_Native_Engineering_and_TRL) | AI-Native TRL philosophy (метрика прогресу) |
| [`00_04` — Shape Up Operations and RnD Clusters](00_04_Shape_Up_Operations_and_RnD_Clusters) | Shape Up operations; §Async-Review TRL Gates |
| [`00_05` — GitHub Projects and IaC Automation](00_05_GitHub_Projects_and_IaC_Automation) | TRL Auto-Advancement (HIL → Projects V2 cards) |
| [`04_06` — Testing Guide and Coverage](04_06_Testing_Guide_and_Coverage) | §B Gap Analysis — відомі обмеження тестів + відкриті ризики |
| [`08_02` — Academic Institutions Registry](08_02_Academic_Institutions_Registry) | Фізичні валідаційні протоколи ВНЗ (TRL 1-4) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** (SSOT): Module 01 chemistry (HW.*), 06 DevOps deploy, 08 UNI.* |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Матриця готовності Silken Net (The TRL Matrix)](#-1-матриця-готовності-silken-net-the-trl-matrix)
- [2. Принцип "TRL-Lock" → "TRL-Layered Independence"](#-2-принцип-trl-lock--trl-layered-independence)
- [3. HIL Simulators — Програмне розблокування Software TRL](#-3-hil-simulators--програмне-розблокування-software-trl)
<!-- TOC:AUTO:END -->

---

## 📊 1. Матриця готовності Silken Net (The TRL Matrix)

Ми адаптували шкалу NASA TRL для кіберфізичних екосистем. Проєкт рухається від фундаментальної лабораторії до глобальної фіналізації.

| Рівень | Етап | Технічний критерій (Evidence) | Лабораторія / Хаб |
|:---|:---|:---|:---|
| **TRL 1-2** | Ідея / Принцип | Математичне обґрунтування EBFC та Атрактора Лоренца. | ЧНУ (Хімія/Фізика) |
| **TRL 3-4** | Proof of Concept | Валідація EBFC Gen 2.0 **>500 мВ** (OCV ~600 мВ > BQ25570 Cold-Start 330 мВ; [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)) → 3.3V boost та перша транзакція в Sandbox. *(«44 мВ» — застаріла гіпотеза streaming-potential/п'єзо, відкинута з Gen 2.0.)* | ЧНУ (ФОТІУС) |
| **TRL 5-6** | Прототипування | Робота кластера "Солдат-Королева" в Черкаському борі (30 днів). | Silken Lab |
| **TRL 7-8** | Кваліфікація | Повна інтеграція: DID → ZK-Proof → Chainlink → Polygon. | Production (Canopy) |
| **TRL 9** | Експлуатація | Стабільний мінтинг SCC на мільйонах вузлів, фіналізація в L1. | Global Mainnet |

### Per-module TRL (канонічне джерело)

> SSOT для per-domain TRL. **System TRL = найнижчий модуль критичного шляху (01–07 build-path)** — наразі 4 (модулі 01/02 — hardware-критичні). **Foundation (00)** = візія/метод (зрілі, TRL 9 — поза критичним шляхом, не гейтить). Модулі 08 (R&D-партнерства), 09 (PM-процес), 10 (Security-hardening) — це org/process/безпекова зрілість, яка трекається окремо і **не гейтить** System TRL (інакше System=2 за рахунок ранніх ВНЗ-партнерств, що хибно). Оновлюється при кожному cool-down. *(Мігровано з [`00_07`](00_07_Action_Plan_Tracker) 2026-05-28 — канон тут.)*

| Модуль | TRL | Цільовий | Головний блокер |
|--------|-----|----------|-----------------|
| 00 Foundation (Vision + Method) | 9 | 9 | — (методологія/візія зрілі) |
| 01 Materials & EBFC | 4 | 6 | Lab tests (ЧНУ) |
| 02 Hardware & BOM | 4 | 6 | BQ25570, PCB, Pogo, PEEK |
| 03 Firmware | 6 | 8 | AES key, TinyML, AT blocking |
| 04 Backend Rails | 8 | 9 | RSpec тести |
| 05 Web3 Pipeline | 8 | 9 | SFC address |
| 06 DevOps | 5 | 9 | production deploy не проведено (06_01=4 outlier); Docker registry, TLS |
| 07 Business | 5 | 8 | CO₂ methodology, MSA, ToS |
| 08 University R&D | 2 | 6 | 5-сторонній партнерський фреймворк (ChNU + ChDTU + ChIPB + ChMA + СЄУ) — UNI.4-14 |
| 09 Project Management | 7 | 9 | OPS.3 R&D portfolio, OPS.4 semester sync |
| 10 Security | 7 | 9 | SEC.9 master key, ✅ SEC.11 Lorenz seed provenance, Multisig, RDP, Factory (Rails web layer ✅ S6.18) |

> **Рядок модуля = агрегат (мінімум) member-TRL його під-доків** — гейтиться найнижчим під-компонентом критичного шляху, не «середнім». Окремий під-док може декларувати **вищий** member-TRL у власному `## ✅ Статус` без суперечності з рядком: це джерело (не дубль), а рядок просто бере мінімум. Приклад — **Module 02 = 4**: капсула [`02_01`](02_01_Hardware_Architecture_and_BOM) (архітектура + BOM заморожені) і шлюз Королеви [`02_05`](02_05_Queen_Hardware_and_Starlink) декларують вищі member-TRL у своїх Статусах, але агрегат гейтиться фізичними під-компонентами на TRL 4 — Pogo-pin [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface), резисторна мережа BQ25570 [`02_03`](02_03_BQ25570_MPPT_Nano_Power), EDLC [`02_04`](02_04_EDLC_Supercapacitor_Buffer) (anchor/EBFC-gated). Тож «HW=4» у матриці й «капсула вище» у 02_01 — **не drift**, а агрегат vs member.

---

## 🛡️ 2. Принцип "TRL-Lock" → "TRL-Layered Independence"

> **Стара формулювання (Waterfall):** *"Жоден компонент не може бути переведений у стан Production, якщо він не досяг TRL 7. Якщо апаратна частина анкера на рівні TRL 4, а софт на TRL 8 — загальний статус модуля залишається TRL 4."*

Це лінійне правило знищує сенс Concurrent Engineering. Якщо Rails-модуль, токеноміка і Web3-мости готові до TRL 8, вони не повинні чекати, поки хіміки з ЧМА закінчать роботу з EBFC.

### Нова формулювання (Concurrent + HIL):

1. **System TRL** залишається обмеженим найнижчим модулем **критичного шляху** (01–07; §1-note) — це чесна метрика для grant заявок та regulator-комунікації ("система готова до пілоту тоді й тільки тоді, коли всі шари готові").
2. **Per-domain TRL** є **незалежним** і відстежується в `docs/00_03 §TRL Matrix` per-module. Software може бути TRL 8 коли Hardware TRL 4.
3. **HIL Simulators** (Hardware-in-the-Loop) — програмні генератори, які імітують поведінку реального hardware, дозволяють software-домену пройти TRL 5-8 без живої EBFC/анкера.

---

## 🧪 3. HIL Simulators — Програмне розблокування Software TRL

### 3.1 Чому це критично

Поточна політика блокувала весь TRL модулів 04 (Rails) і 05 (Web3) на TRL 4-5, попри їхню зрілість і **готовність до production**. Без HIL ці модулі лишаються заблокованими на TRL 4 суто формальністю.

### 3.2 HIL-симулятори в SilkenNet

| Симулятор | Імітує | Файл | Замінює реальний компонент для |
|-----------|--------|------|-------------------------------|
| `bin/forest_simulator` | Емулює **Queen→Backend CoAP-батчі** (AES-256-**CBC**) з телеметрією Soldier'ів, full Lorenz attractor curves. ⚠️ Це Queen-рівень: per-Soldier LoRa-хоп — на залізі **AES-128** (ECB→CCM, [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)), а до бекенду доходить CoAP-батч (AES-256-CBC). **Два режими (див. ⚠️ нижче):** `load_test_mode` (батч кожні 3–8 сек — стрес черг) та `realistic_mode` (CIFO-точний: рідкі об'ємні батчі ~раз на годину/45 записів + packet loss + jitter мобільної мережі) | `bin/forest_simulator` (load_test існує; realistic_mode — TODO) | Локальна розробка Rails + sidekiq + Web3 pipeline |
| `HilQueenSimulator` | Queen self-telemetry (`DID == 0x00000000`), CIFO flush, Starlink/LTE timing | новий: `lib/hil/queen_simulator.rb` (планований) | Test Queen failover ([`06_08 §Queen Failover`](06_08_Resilience_and_Failover_Policy)) |
| `HilWebPipelineSimulator` | peaq → IoTeX → Chainlink → Polygon → KlimaDAO → Filecoin → L1 — 12-chain mock з deterministic responses. ⚠️ Це **логіко-рівневий** інструмент (TRL 5-6): валідує pipeline-логіку та guard clauses, але **НЕ** Web3 реального світу (gas spikes, RPC 429/rate-limit, orphaned blocks, nonce collisions, Chainlink DON latency). НЕ є достатнім для TRL 7-8 — див. §3.3. | `WEB3_STRICT_MODE=false` + stub services у `app/services/web3/*_stub.rb` | Логіка pipeline + unit/integration (TRL 5-6) |
| `HilLorenzGenerator` | mruby Lorenz curves з різних tree species, environmental conditions (temp, vibration), faulty/normal patterns | `lib/hil/lorenz_generator.rb` (планований) | TinyML training data + Rails Attractor validation |
| `HilAttackerScenarios` | Bit-flip attacks, replay attacks, hardware tamper detection, dual-computation divergence > 30% | RSpec scenarios у `spec/integration/security/` (частково існує) | Anti-fraud cross-checks ([`05_05 §6`](05_05_Slashing_and_Risk_Policy)) |

> **⚠️ Реалістичний профіль навантаження vs DDoS (корекція 2026-05-28):** батч «кожні 3–8 сек» суперечить буферу CIFO ([`06_08 §1.2`](06_08_Resilience_and_Failover_Policy): flush на 45 записів **або** раз на годину) — для цього Soldier мав би передавати кілька разів на хвилину, що неможливо за енергобюджетом. Тобто 3–8 сек = `load_test_mode` (стрес черг/пропускної здатності), а НЕ реальний IoT-профіль. **`realistic_mode`** (потрібно додати) має відтворювати фізичну Queen: рідкі об'ємні батчі раз на ~годину, + мережеві умови **Starlink Direct-to-Cell**: Carrier-NAT, можливе блокування вхідного UDP (CoAP), зміна портів, високий jitter / packet loss супутникового LTE. Це тестує дефіцит з'єднань, тайм-аути long-poll та розриви TCP-сесій — справжні відмови, яких load-test не ловить. Транспортний фолбек (CoAP-over-TCP / MQTT-SN) — див. [`02_05`](02_05_Queen_Hardware_and_Starlink) + Ingress Proxy [`06_01`](06_01_Deployment_Kamal_Terraform).

### 3.3 TRL Промоція через HIL

> ⚠️ **Колонка нижче — НЕ блокер (інакше це повернуло б TRL-Lock з §2).** Сенс HIL саме в тому, щоб **не чекати** фізичних дерев. Тому це **Physical-Equivalent Target** — той фізичний стан, який HIL-симулятор *відтворює навантаженням*, а НЕ передумова. Software досягає TRL завдяки тому, що HIL генерує еквівалентне навантаження (напр. 1000+ віртуальних дерев), а не тому, що вони є в полі.

| Per-domain TRL | Physical-Equivalent Target (НЕ блокер) | HIL, що його відтворює | Status |
|----------------|----------------------|----------------|--------|
| Software TRL 5 (Prototype validated) | ~анкер у дереві 30 днів | `bin/forest_simulator` + integration tests | ✅ Достатньо |
| Software TRL 6 (Demonstration in relevant environment) | ~LoRa mesh у канопі | HIL Queen Simulator + Akash staging deploy + multi-node forest_simulator | 🟡 Частково (HIL Queen ще не написаний) |
| Software TRL 7 (Operational prototype) | ~pilot 100 дерев | Все HIL + chaos engineering + **реальний testnet pipeline ОБОВ'ЯЗКОВИЙ** (Polygon Amoy + Solana Devnet + Ethereum Sepolia) з реальними RPC-вузлами | 🟡 Частково (chaos engineering exists; testnet pipeline — TODO) |
| Software TRL 8 (Production-validated) | ~1000+ дерев у полі | **HIL відтворює 1000+ віртуальних дерев** + **повний testnet stress** (Amoy/Devnet/Sepolia: gas spikes, RPC 429, nonce collisions, DON latency, orphaned blocks) + Slither high-severity = 0 + multi-sig deployment dry-run. Mainnet — лише TRL 9. | 🟡 Контракти TRL 9-ready (Foundry/Slither); backend↔chain integration потребує testnet-стресу |

> **⚠️ Два рівні Web3-тестування (корекція 2026-05-28):** детермінований mock (`HilWebPipelineSimulator`) НЕ може давати Software TRL 8 — він валідує лише логіку (TRL 5-6). Реальні відмови Web3 (gas spikes, RPC rate-limit/429, orphaned blocks, nonce collisions, Chainlink DON latency) ловляться **тільки на справжніх testnet'ах**. Тому: **TRL 5-6** → deterministic mock; **TRL 7-8** → обов'язковий **Testnet Pipeline** (Polygon Amoy + Solana Devnet + Ethereum Sepolia, реальні RPC); **TRL 9** → mainnet. Без testnet-стресу вихід у mainnet після моків гарантує падіння бекенду у перші години.

### 3.4 Прозорість

> HIL-симулятори **не приховують** фізичне відставання — `docs/README.md` Current Stat показує **System TRL** (4) поряд із **per-domain TRL** (Rails 8, Solidity 9, EBFC 4). Це чесніше, ніж блокувати Software на TRL 4 формальністю TRL-Lock.

---

> **🌌 Beyond TRL 9 — винесено у власний дім.** Далекогоризонтна R&D-агенда — 4 Planetary-Intelligence прогалини (колективний гомеостаз, self-evolving edge AI, cross-biome, apex-predator security) + фрактальна мережева топологія (L1/L2/L3, H-LDSE, Edge Data Fusion), горизонт 2026–2040+ — тепер канонічно живе в [`00_08`](00_08_Beyond_TRL9_Planetary_Roadmap). Тут лишаються **жива TRL-матриця** (§1) + **метод** (TRL-Layered-Independence §2, HIL-симулятори §3).
