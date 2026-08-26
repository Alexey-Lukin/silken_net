# 05_06: Governance & DAO — Законодавча Гілка Влади

## 🎯 Мета

Канонічний дім **on-chain governance**: як SFC-голдери змінюють протокольні параметри (slashing-пороги/криву, tokenomics-курс, ціни; Lorenz-ключі — DCI-locked резерв OTA-ери, §7) через DAO замість хардкоду + redeploy. Описує `SilkenGovernor` / `SilkenTimelock` / `ProtocolParameters`, Flash-Loan-захист, governance-aware backend (`SystemParameter` / `ParameterSyncWorker`) та проактивну оборону (Auto-Immune Sentinel, beyond TRL 9). Виокремлено з [`05_03`](05_03_Tokenomics_SCC_and_SFC) (емісія токенів) — це **законодавча гілка**, концептуально окрема від token-spec.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — governance pipeline повністю реалізований (`SilkenGovernor.sol` + `SilkenTimelock.sol` + `ProtocolParameters.sol` + `Governance::ParameterSyncWorker` + `SystemParameter` model, RSpec-покрито). Mainnet-активація DAO + multisig council → [`00_07`](00_07_Action_Plan_Tracker) (BIZ.*).
- **Реактивний захист (TRL 9-ready):** Snapshot Voting + Timelock 48h + Quorum 4% + Voting Delay — Flash-Loan attack закрито.
- **Проактивний захист (Beyond TRL 9):** Auto-Immune Sentinel — R&D-напрям, не блокує поточний TRL.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) | Де governance-контракти живуть у 12-chain стеку |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | SFC `ERC20Votes`/`ERC20Permit` база; SCC/SFC контракти |
| [`05_04` — Ethereum L1 State Anchor](05_04_Ethereum_L1_State_Anchor) | Timelock керує `ANCHOR_ROLE`-ротацією (admin=Timelock) |
| [`05_05` — Slashing and Risk Policy](05_05_Slashing_and_Risk_Policy) | Slashing DAO peer-review (категорія C) користується цим governance |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | Lorenz σ/ρ/β — DCI-locked константи (FW.7); on-chain ключі = резерв OTA-ери, НЕ живий важіль (§7) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `SystemParameter` model, `Governance::ParameterSyncWorker` |
| [`00_03` — TRL Matrix HIL and Beyond](00_03_TRL_Matrix_HIL_and_Beyond) | TRL-матриця + beyond-TRL-9 контекст для §5 (Auto-Immune Sentinel R&D) |
| [`00_04` — Nature as a Service Contracts](00_04_Nature_as_a_Service_Contracts) | DAO Agreement (тип контракту §1.3) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкрите** (SSOT): mainnet DAO activation → `SEC.1` (поглинув BIZ.4); read-path ✅ GOV.1 (§🗄️) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Проблема (Абсолютна Монархія)](#-1-проблема-абсолютна-монархія)
- [2. Рішення — Governance DAO](#2-рішення--governance-dao)
- [3. Пріоритет та Залежності](#3-пріоритет-та-залежності)
- [4. ⚠️ Flash Loan Attack Vector (Критичний)](#4--flash-loan-attack-vector-критичний)
- [5. Beyond TRL 9: Auto-Immune Sentinel — Проактивний Захист від AI-Driven Economic Attack](#5-beyond-trl-9-auto-immune-sentinel--проактивний-захист-від-ai-driven-economic-attack)
- [6. Bonding Curves — Динамічне Ціноутворення (Перспектива TRL 9+)](#6-bonding-curves--динамічне-ціноутворення-перспектива-trl-9)
- [7. Governance-Aware Backend (✅ read-path + bounds; Lorenz = DCI-locked)](#7-governance-aware-backend--read-path--bounds-lorenz--dci-locked)
<!-- TOC:AUTO:END -->

---

## 🗳️ 1. Проблема (Абсолютна Монархія)

Поточні константи SilkenNet зашиті в Rails-сервісних класах та firmware:

| Константа | Де зашита | Значення |
|-----------|---------|---------|
| `SIGMA = 10.0`, `RHO = 28.0`, `BETA = 8.0/3.0` | `SilkenNet::Attractor` | Параметри атрактора Лоренца |
| `slash_threshold` = 0.20 | ⚠️ **НЕ константа** — `ContractHealthCheckService` читає `SystemParameter.current(:slash_threshold)` | 20% аномальних дерев → Slashing |
| `EMISSION_THRESHOLD = 10_000` | `TokenomicsEvaluatorWorker` | Конверсія growth points → SCC. ⚠️ Доти цей рядок звав її `POINTS_PER_SCC` — імені, якого в коді НІКОЛИ не було (переміряно 2026-08-26: нуль комітів), тож єдиний вхід до курсу з боку governance-канону вів у порожнечу |
| `AiInsight::SLASH_STRESS_THRESHOLD = 0.83` | ⚠️ **`AiInsight`, не `ContractHealthCheckService`** — той лише читає `AiInsight.slash_stress_threshold` (DAO-live) | Поріг стресу дерева |

> Значення-приклади ілюструють hardcoded-стан *до* governance; канонічні доми: Lorenz [`03_04 §1.2`](03_04_mruby_Lorenz_Attractor), slash-пороги [`05_05`](05_05_Slashing_and_Risk_Policy), tokenomics-курс [`05_03`](05_03_Tokenomics_SCC_and_SFC).

**Проблема при планетарному масштабуванні:** Тропічні ліси, тайга та мангрові зарості мають принципово різні метаболічні базлайни. Одні й ті самі константи σ=10, ρ=28 призведуть до масових хибних Slashings у тропіках та пропуску реальних аномалій у тайзі.

Зміна будь-якої константи = повний деплой Rails + перепрошивка всіх STM32-вузлів. При мільярдах дерев — практично нездійсненне.

## 2. Рішення — Governance DAO

SFC-токен вже має `ERC20Votes` та `ERC20Permit` — ідеальна база для DAO голосувань.

**Архітектура:**

```
SFC holders (+ Gnosis Safe multisig на bootstrap-періоді — `SilkenTimelock.sol`)
        │ vote()
        ▼
GovernorContract.sol (OpenZeppelin Governor + TimelockController)
        │ after 48h timelock
        ▼
ProtocolParameters.sol (on-chain registry)
        │ read via RPC eth_call (Web3::RpcConnectionPool)
        ▼
Governance::ParameterSyncWorker (Sidekiq, queue: web3_low)
        │ 1×/день · bounds-clamp · DCI-tripwire (§7)
        ▼
SystemParameter (source: "governance")
        │ SystemParameter.current(…)
        ▼
TokenomicsEvaluatorWorker.emission_threshold (курс конверсії)
ContractHealthCheckService (slash_threshold-частка) + AiInsight.slash_stress_threshold
BlockchainBurningService (slash_gamma / slash_penalty_factor_max)
BlockchainMintingService (dynamic_tax_rate / insurance_pool_threshold)
PriceOracleService (scc_fallback_price_usd)
```

**Нові смарт-контракти (✅ Реалізовано):**
1. `SilkenGovernor.sol` — OpenZeppelin Governor з GovernorVotes, GovernorTimelockControl (48h), GovernorCountingSimple, GovernorVotesQuorumFraction (4%)
2. `SilkenTimelock.sol` — TimelockController з 48h мінімальною затримкою
3. `ProtocolParameters.sol` — on-chain registry з generic `setParameter(bytes32 key, uint256 value)` + batch `setParameters()` + named getters (`lorenzSigma()`, `slashThreshold()`, etc.)

**Новий Rails воркер (✅ Реалізовано):**
- `Governance::ParameterSyncWorker` (queue: `web3_low`, cron: 1×/день)
- Зчитує поточні параметри з `ProtocolParameters.sol` через `Web3::RpcConnectionPool` + `Eth::Contract`
- Порівнює з поточними значеннями `SystemParameter` та оновлює змінені з `source: "governance"`
- Використовує `Timeout.timeout(10s)` на кожен RPC-запит
- 9 економічних параметрів (tokenomics/minting/insurance + slashing/alerts) з bounds-clamp (§7); 8 Lorenz-ключів контракту — **DCI-locked**, свідомо НЕ синхронізуються (tripwire-WARN на голос — §7)

**Друга governance-поверхня — ролі контрактів (не лише параметри).** Той самий шлях Governor → Timelock у production тримає `DEFAULT_ADMIN_ROLE` над токенами та `StateRootAnchor`, тож DAO може видавати/відкликати `MINTER_ROLE`/`SLASHER_ROLE`/`ANCHOR_ROLE` — **ротувати oracle-адреси** — теж лише за 48h-затримкою (`pause` лишається миттєвим у Safe, [SEC.1]). Це і є незворотний крок «transfer admin-ролей → Timelock» ([`00_07` SEC.1](00_07_Action_Plan_Tracker) — поглинув BIZ.4). Розкладка ролей/власників живе в [`05_03`](05_03_Tokenomics_SCC_and_SFC) (токени) + [`05_04`](05_04_Ethereum_L1_State_Anchor) (anchor) — тут лише вказівник.

## 3. Пріоритет та Залежності

| Аспект | Деталі |
|--------|--------|
| **Пріоритет** | ✅ Реалізовано (ARCH.4 / BIZ.4 / E.35). Governance DAO pipeline повністю функціональний |
| **Залежить від** | `SilkenForestCoin.sol` (SFC) — ⚠️ **НЕ задеплоєний** (виправлено 2026-08-26: доти стояло «✅ є» і суперечило [`05_03`](05_03_Tokenomics_SCC_and_SFC), де адреса — placeholder до mainnet). Контракт написаний і CI-audited; гейт деплою — [`SEC.1`](00_07_Action_Plan_Tracker) |
| **Блокує** | Планетарне масштабування з різними кліматичними зонами — far-horizon гейт: **кожен новий біом потребує community vote (SFC) + слот лабораторної валідації ПЕРШ ніж із нього можуть мінтитись SCC**. Це не бюрократія, а пряме продовження «правдиво» ([`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap)): мінтити з породи, чиї Lorenz-константи ніхто не калібрував, означає видавати вгадане за виміряне (hardware-бік 5 SKU → [`01_01 §6`](01_01_Coaxial_Gyroid_Topology_and_PEEK)) |
| **Ризики DAO** | ✅ Захисти реалізовано: quorum 4% + timelock 48h + snapshot voting + votingDelay 43200 blocks |

## 4. ⚠️ Flash Loan Attack Vector (Критичний)

**Загроза:** Якщо параметри системи (наприклад, `SLASH_THRESHOLD`) можна змінювати через DAO голосування, зловмисник може:
1. Взяти Flash Loan токенів SFC на DEX (позика + повернення в одній транзакції)
2. Проголосувати за зміну параметра (наприклад, підвищити `SLASH_THRESHOLD` до 100%, щоб уникнути слешингу свого лісу)
3. Повернути позику в тій самій транзакції — нульова вартість атаки

**Обов'язкові захисти в `SilkenGovernor.sol` (✅ Реалізовано):**

| Захист | Механізм | Чому працює |
|--------|----------|-------------|
| **Snapshot Voting** | `getPastVotes(account, blockNumber)` замість `balanceOf()` | Голоси рахуються за балансом на момент створення пропозиції, а не поточним. Flash Loan отримується ПІСЛЯ snapshot → не має voting power |
| **Voting Delay** | Мінімум 1 блок (рекомендовано 1 день / ~43200 блоків на Polygon при ~2s block time) між створенням пропозиції та початком голосування | Зловмисник мусить тримати токени протягом delay — Flash Loan неможливий |
| **Quorum** | Мінімум 4% від `totalSupply()` для прийняття пропозиції | Запобігає атакам малими обсягами |
| **Timelock** | `TimelockController` з 48h затримкою між прийняттям та виконанням | Дає час для реакції та vetoing |
| **Vote Weight = Past Balance** | `ERC20Votes._delegate()` + checkpoint system (вже реалізовано в SFC) | Кожен трансфер створює checkpoint; `getPastVotes` читає історичний checkpoint |

**Реалізація (`contracts/SilkenGovernor.sol`):**
```solidity
// SilkenGovernor.sol — SSOT: contracts/SilkenGovernor.sol
contract SilkenGovernor is Governor, GovernorSettings, GovernorCountingSimple,
    GovernorVotes, GovernorVotesQuorumFraction, GovernorTimelockControl {

    constructor(IVotes _token, TimelockController _timelock)
        Governor("Silken Governor")
        GovernorSettings(
            43200,     // votingDelay: ~1 day on Polygon (block time ~2s)
            302400,    // votingPeriod: ~7 days on Polygon
            10_000e18  // [CONTRACT.1] proposalThreshold: 10 000 SFC = 0.01% MAX_SUPPLY (anti-spam)
        )
        GovernorVotesQuorumFraction(4)  // 4% quorum
        GovernorTimelockControl(_timelock)
    {}
}
```

> **✅ Реалізовано:** SFC має `ERC20Votes` з auto-delegation — checkpoint система працює. Governor + Timelock контракти реалізовано.

## 5. Beyond TRL 9: Auto-Immune Sentinel — Проактивний Захист від AI-Driven Economic Attack

> **Контекст:** Поточні захисти (Snapshot Voting, Timelock, Quorum, Flash Loan defense) — **реактивні** і **достатні для TRL 9**. Але як тільки SCC market cap перевищить ~$100M, система стане апетитною ціллю для **AI-driven trading bots** і **adversarial ML attacks** (синтетичні telemetry-патерни, які проходять Dual Computation Integrity).
>
> **Майбутній напрям (Beyond TRL 9 / SRL roadmap) — Proactive AI Sentinel:**
> - **Cluster-level statistical fingerprints:** замість per-tree fraud detection — federated anomaly detection. Якщо 100 дерев кластера раптом видають «too perfect» Z-curves (lower variance than physically possible) → suspicious activity flag.
> - **Decoy DID Tripwire (backend, НЕ on-chain honeypot):** набір decoy DID у серверному watchlist (не on-chain — публічний стейт контракту видав би «заблоковане» дерево відсутністю mint-подій, і атакер обійшов би). Будь-яка телеметрія/mint-спроба від decoy DID = доведена підробка → instant slashing + 12-chain rotation. Канон — тут.
> - **Red Team Adversarial Telemetry Generators:** GAN-вироблені синтетичні patterns як частина CI/CD ([`04_06`](04_06_Testing_Guide_and_Coverage)) — знаходимо вразливості до того, як їх знайде зовнішній attacker.
> - **Quantum-Resistant Oracle Migration:** перехід Chainlink + 12-chain stack (асиметричні підписи ECDSA/Ed25519) на NIST PQC до 2030+; симетричний LoRa/CoAP-трафік (AES) уже PQ-стійкий. Канон — [`03_05 §10`](03_05_Hardware_Symmetric_Crypto_and_Security).
> - **AI Sentinel Service:** окремий ML-сервіс 24/7 у режимі "hunting for hunters" — корелює trading volume на SCC DEXs з telemetry-аномаліями та oracle response patterns.
>
> **Філософська позиція:** SCC — це **критична інфраструктура планетарного клімату**. Стандарт безпеки має бути **на рівні national-grid SCADA**, а не «не гірше за DeFi 2020–2024».
>
> **Партнери напряму:** Аблязов Д. (СЄУ, правова рамка), Карапетян (ChDTU, статистика fraud detection).

## 6. Bonding Curves — Динамічне Ціноутворення (Перспектива TRL 9+)

Поточна модель: фіксований курс емісії ⚠️ **— і це правда лише про SCC.** Правила емісії SFC не існує НІДЕ (виміряно 2026-08-26): [`05_03`](05_03_Tokenomics_SCC_and_SFC) дає курс тільки для SCC, а SFC-комірка стелі стоїть без деривації взагалі. 🔴 Наслідок гостріший за прогалину в документі: quorum рахується від `totalSupply`, genesis-supply = 0 (premine немає), тож перші `10_000 SFC` дають своєму власникові 100% голосів, а доти `proposalThreshold` не дає подати пропозицію НІКОМУ. Осі присуду — [`00_07`](00_07_Action_Plan_Tracker) DOC-T.89 ([`05_03`](05_03_Tokenomics_SCC_and_SFC)). Для планетарного масштабу можна розглянути алгоритмічне ціноутворення:

**Концепт:** Вартість мінтингу SCC алгоритмічно залежить від глобального показника здоров'я лісу (середній Z-value атрактора Лоренца по всіх кластерах). Чим здоровіший ліс → тим цінніший актив → тим більше growth_points потрібно для 1 SCC. ⚠️ **[Lorenz de-risk]** Прив'язка ціни до «середній Z = здоров'я лісу» передбачає доведений Z↔health ([`05_05 §8`](05_05_Slashing_and_Risk_Policy)) — ще одна причина «відкладено до TRL 9+».

**Чому відкладено:** Bonding Curves значно ускладнюють аудит контрактів, створюють MEV-вектори та потребують ліквідності для функціонування. Для TRL 6-8 фіксований курс є простішим та безпечнішим.

**Статус:** Перспективна ідея. Не планується до TRL 9+.

## 7. Governance-Aware Backend (✅ read-path + bounds; Lorenz = DCI-locked)

```ruby
# Живий патерн (GOV.1, 2026-07-04):
# Замість: EMISSION_THRESHOLD = 10_000 (хардкод)
threshold = TokenomicsEvaluatorWorker.emission_threshold  # SystemParameter ← ProtocolParameters.sol

# Замість: Rational(1, 5) — точна десяткова частка без IEEE-похибки:
slash_fraction = Rational(SystemParameter.current(:slash_threshold, default: 0.2).to_s)

# Спільний slash/damage-поріг (тригер + сайзинг, ARCH.46):
AiInsight.slash_stress_threshold  # default 0.83

# Admin/Governance update:
SystemParameter.set("slash_gamma", "1.5", updated_by: admin, source: "governance")
```

> Значення-дефолти у прикладах (`10_000` / `0.2` / `0.83`) — лише `default:`-fallback, що дзеркалить канон-доми (примітка §1 вище має посилання: slash / курс); governance/admin override має пріоритет.

📐 **Форма реєстру — ОДИН СКАЛЯР НА КЛЮЧ, і це обмежує, що взагалі можна винести на DAO.** `ProtocolParameters.sol` — це `mapping(bytes32 => uint256)`, тож будь-який параметр, який за природою є **вектором** (набір ваг, профіль порогів, кортеж коефіцієнтів), у реєстр не лягає взагалі. Проєктуючи нову governance-ручку, спершу спитай, чи величина скалярна; якщо ні — вибір робиться ЯВНО між трьома формами: N окремих ключів ⊥ packed-`uint256` ⊥ off-chain-конфіг із on-chain хешем. ⚠️ І пара `db/seeds.rb` ⟷ `PARAMETER_MAP` гейтована (`system_parameter_delivery_spec`), тож ключ без реального читача не «на майбутнє», а червоний.

**Стан read-path ([GOV.1] закрито 2026-07-04):**
- **Синхронізуються + читаються назад (повний DAO-ефект):** `emission_threshold` → `TokenomicsEvaluatorWorker.emission_threshold` (One-Home: селектор, `EvaluateTreeBatchWorker`-конверсія, `OracleVisionsController`; `MintingRollbackService` legacy-fallback свідомо на дефолт-константі — історичний refund не переоцінюється) · `slash_threshold` → `ContractHealthCheckService` (Rational-точність) · `stress_threshold` → `AiInsight.slash_stress_threshold` (спільний для тригера й damage-сайзингу — ARCH.46) · `slash_gamma`/`slash_penalty_factor_max` → `BlockchainBurningService` · `dynamic_tax_rate`/`insurance_pool_threshold` → `BlockchainMintingService` · `scc_fallback_price_usd` → `PriceOracleService` · `scc_per_tonne_co2` (синхронізується; прод-споживач прийде з carbon-registry інтеграцією — BIZ.1). Поза on-chain: kill-switches (`parametric_insurance_oracle_enabled`, `slash_cause_uplift_enabled`) та oracle-balance пороги (E.51) — admin-only за дизайном.
- **Bounds-clamp:** sync-воркер пише `min_value`/`max_value` (One-Home меж = `PARAMETER_MAP` ↔ `db/seeds.rb`) — out-of-bounds DAO-значення (клас «18-decimals мис-скейл», напр. tax=2e18 «200%» → `beneficiary_amount<0` → mint-halt) **відхиляється**: чинним лишається попереднє, `silkennet_governance_param_rejected_total` + ERROR-лог → потрібен коригувальний голос ([`06_03 §2.7`](06_03_Prometheus_Observability)).
- ⊕ **Цей перелік ЗАКРИТИЙ, і саме тому потребує вказівника назовні:** [`04_02 §Forester Guild`](04_02_Business_Logic_and_Services) та [`05_05 §3.1`](05_05_Slashing_and_Risk_Policy) обіцяють ще чотири DAO-ручки (bond-sizing · holdback-% · sponsor-cap · reputation-scaling), яких **у контракті, сідах і `PARAMETER_MAP` немає** — вони gated на ⚖️ [`00_07`](00_07_Action_Plan_Tracker) BIZ.13 (Модель B). Без цього рядка пропуск невидимий саме з боку governance: читач §7 бачить повний список і не дізнається, що два інші доки обіцяють більше.
- **8 Lorenz-ключів = DCI-locked** (σ/ρ/β/dt/iterations/z_min/z_max/z_target): `SilkenNet::Attractor` тримає bit-identical Float-константи з прошитим firmware (FW.7 — Dual Computation Integrity), governance-зміна зламала б device↔server parity. Ключі лишаються в контракті як резерв OTA-ери; `ParameterSyncWorker` їх НЕ тягне, `db/seeds.rb` НЕ сідирує (запис без читача = пастка), лише **tripwire**: голос за DCI-locked ключ → WARN «набуття ефекту = координований fleet-reflash» ([`03_04`](03_04_mruby_Lorenz_Attractor)).

**`SystemParameter` model** (`app/models/system_parameter.rb`):
- Кеш поточних значень з TTL 24h (invalidation через `after_commit`)
- Fallback на `default:` при відсутності запису
- Type coercion: `integer`, `float`, `decimal`, `string`, `boolean`, `json`
- Bounds validation (`min_value` / `max_value`) — governance-safety-межі (↑)
- Audit trail (`updated_by` → User FK, `source`: default/admin/governance) + **[ARCH.57]** value-мутація пише tamper-evident `system_parameter_changed` у глобальний (org=nil) AuditLog hash-ланцюг (концерн `Auditable` — [`04_01 §7`](04_01_Data_Models_and_Entities))
- seed-параметри: tokenomics/minting/insurance + slashing/alerts (slash_threshold/stress_threshold/slash_gamma/slash_penalty_factor_max) + fraud/fire/hardware + **insurance kill-switch** (`parametric_insurance_oracle_enabled` — kill-switch money-path параметричного страхування, default false; [INS.1] — admin/governance, НЕ on-chain `ProtocolParameters`); Lorenz свідомо НЕ сідирується (DCI ↑)
- Синхронізація з `ProtocolParameters.sol` через RPC eth_call — `Governance::ParameterSyncWorker` (§2)
