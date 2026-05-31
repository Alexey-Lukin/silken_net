# 05_06: Governance & DAO — Законодавча Гілка Влади

## 🎯 Мета

Канонічний дім **on-chain governance**: як SFC-голдери змінюють протокольні параметри (Lorenz σ/ρ/β, slashing-пороги, tokenomics-курс) через DAO замість хардкоду + redeploy/reflash. Описує `SilkenGovernor` / `SilkenTimelock` / `ProtocolParameters`, Flash-Loan-захист, governance-aware backend (`SystemParameter` / `ParameterSyncWorker`) та проактивну оборону (Apex Predator, beyond TRL 9). Виокремлено з `05_03` (емісія токенів) — це **законодавча гілка**, концептуально окрема від token-spec.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — governance pipeline повністю реалізований (`SilkenGovernor.sol` + `SilkenTimelock.sol` + `ProtocolParameters.sol` + `Governance::ParameterSyncWorker` + `SystemParameter` model, RSpec-покрито). Mainnet-активація DAO + multisig council → [00_07](00_07_Action_Plan_Tracker) (BIZ.*).
- **Реактивний захист (TRL 9-ready):** Snapshot Voting + Timelock 48h + Quorum 4% + Voting Delay — Flash-Loan attack закрито.
- **Проактивний захист (Beyond TRL 9):** Apex Predator Defense — R&D-напрям, не блокує поточний TRL.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [05_03_Tokenomics_SCC_and_SFC](05_03_Tokenomics_SCC_and_SFC) | SFC `ERC20Votes`/`ERC20Permit` база; SCC/SFC контракти |
| [05_05_Slashing_and_Risk_Policy](05_05_Slashing_and_Risk_Policy) | Slashing DAO peer-review (категорія C) користується цим governance |
| [03_04_mruby_Lorenz_Attractor](03_04_mruby_Lorenz_Attractor) | Lorenz σ/ρ/β — governance-керовані параметри (per-climate-zone) |
| [04_02_Business_Logic_and_Services](04_02_Business_Logic_and_Services) | `SystemParameter` model, `Governance::ParameterSyncWorker` |
| [00_03_TRL_Matrix_HIL_and_Beyond](00_03_TRL_Matrix_HIL_and_Beyond) | Apex Predator Defense R&D-програма (§7.4) |
| [07_01_Nature_as_a_Service_Contracts](07_01_Nature_as_a_Service_Contracts) | DAO Agreement (тип контракту §1.3) |
| [00_07_Action_Plan_Tracker](00_07_Action_Plan_Tracker) | **Відкрите** (SSOT): mainnet DAO activation, BIZ.* governance backlog |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Проблема (Абсолютна Монархія)](#-1-проблема-абсолютна-монархія)
- [2. Рішення — Governance DAO](#2-рішення--governance-dao)
- [3. Пріоритет та Залежності](#3-пріоритет-та-залежності)
- [4. ⚠️ Flash Loan Attack Vector (Критичний)](#4--flash-loan-attack-vector-критичний)
- [5. Beyond TRL 9: Apex Predator Defense — Проактивний Захист від AI-Driven Economic Attack](#5-beyond-trl-9-apex-predator-defense--проактивний-захист-від-ai-driven-economic-attack)
- [6. Bonding Curves — Динамічне Ціноутворення (Перспектива TRL 9+)](#6-bonding-curves--динамічне-ціноутворення-перспектива-trl-9)
- [7. Governance-Aware Backend (✅ Реалізовано)](#7-governance-aware-backend--реалізовано)
<!-- TOC:AUTO:END -->

---

## 🗳️ 1. Проблема (Абсолютна Монархія)

Поточні константи Gaia 2.0 зашиті в Rails-сервісних класах та firmware:

| Константа | Де зашита | Значення |
|-----------|---------|---------|
| `SIGMA = 10.0`, `RHO = 28.0`, `BETA = 8.0/3.0` | `SilkenNet::Attractor` | Параметри атрактора Лоренца |
| `SLASH_THRESHOLD = 0.20` | `ContractHealthCheckService` | 20% аномальних дерев → Slashing |
| `POINTS_PER_SCC = 10_000` | `TokenomicsEvaluatorWorker` | Конверсія growth points → SCC |
| `STRESS_THRESHOLD = 0.83` | `ContractHealthCheckService` | Поріг стресу дерева |

> Значення-приклади ілюструють hardcoded-стан *до* governance; канонічні доми: Lorenz [`03_04 §4.1`](03_04_mruby_Lorenz_Attractor), slash-пороги [`05_05`](05_05_Slashing_and_Risk_Policy), tokenomics-курс [`05_03`](05_03_Tokenomics_SCC_and_SFC).

**Проблема при планетарному масштабуванні:** Тропічні ліси, тайга та мангрові зарості мають принципово різні метаболічні базлайни. Одні й ті самі константи σ=10, ρ=28 призведуть до масових хибних Slashings у тропіках та пропуску реальних аномалій у тайзі.

Зміна будь-якої константи = повний деплой Rails + перепрошивка всіх STM32-вузлів. При мільярдах дерев — практично нездійсненне.

## 2. Рішення — Governance DAO

SFC-токен вже має `ERC20Votes` та `ERC20Permit` — ідеальна база для DAO голосувань.

**Архітектура:**

```
SFC holders / Multisig Forester Council
        │ vote()
        ▼
GovernorContract.sol (OpenZeppelin Governor + TimelockController)
        │ after 48h timelock
        ▼
ProtocolParameters.sol (on-chain registry)
        │ read via TheGraph
        ▼
Governance::ParameterSyncWorker (Sidekiq, queue: web3_low)
        │ scheduled 1x/day
        ▼
SilkenNet::Attractor (dynamic params instead of constants)
ContractHealthCheckService (dynamic slash threshold)
TokenomicsEvaluatorWorker (dynamic conversion rate)
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
- 13 параметрів: 8 Lorenz (σ/ρ/β/dt/iterations/z_min/z_max/z_target), 3 tokenomics, 2 slashing

## 3. Пріоритет та Залежності

| Аспект | Деталі |
|--------|--------|
| **Пріоритет** | ✅ Реалізовано (ARCH.4 / BIZ.4 / E.35). Governance DAO pipeline повністю функціональний |
| **Залежить від** | `SilkenForestCoin.sol` (SFC) задеплоєний → ✅ є |
| **Блокує** | Планетарне масштабування з різними кліматичними зонами |
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
            43200,   // votingDelay: ~1 day on Polygon (block time ~2s)
            302400,  // votingPeriod: ~7 days on Polygon
            100e18   // proposalThreshold: 100 SFC to propose
        )
        GovernorVotesQuorumFraction(4)  // 4% quorum
        GovernorTimelockControl(_timelock)
    {}
}
```

> **✅ Реалізовано:** SFC має `ERC20Votes` з auto-delegation — checkpoint система працює. Governor + Timelock контракти реалізовано.

## 5. Beyond TRL 9: Apex Predator Defense — Проактивний Захист від AI-Driven Economic Attack

> **Контекст:** Поточні захисти (Snapshot Voting, Timelock, Quorum, Flash Loan defense) — **реактивні** і **достатні для TRL 9**. Але як тільки SCC market cap перевищить ~$100M, система стане апетитною ціллю для **AI-driven trading bots** і **adversarial ML attacks** (синтетичні telemetry-патерни, які проходять Dual Computation Integrity).
>
> **Майбутній напрям (Beyond TRL 9 / SRL roadmap) — Proactive AI Sentinel:**
> - **Cluster-level statistical fingerprints:** замість per-tree fraud detection — federated anomaly detection. Якщо 100 дерев кластера раптом видають «too perfect» Z-curves (lower variance than physically possible) → suspicious activity flag.
> - **Honeypot Trees:** 1 з кожних 100 — honeypot (справжній анкер, але SCC-emission заблокований). Будь-яка mint-спроба = доведена адресна атака → instant slashing + 12-chain rotation.
> - **Red Team Adversarial Telemetry Generators:** GAN-вироблені синтетичні patterns як частина CI/CD (`04_06`) — знаходимо вразливості до того, як їх знайде зовнішній attacker.
> - **Quantum-Resistant Oracle Migration:** перехід Chainlink + всього 12-chain stack на NIST PQC standards (Kyber/Dilithium) до 2030+.
> - **AI Sentinel Service:** окремий ML-сервіс 24/7 у режимі "hunting for hunters" — корелює trading volume на SCC DEXs з telemetry-аномаліями та oracle response patterns.
>
> **Філософська позиція:** SCC — це **критична інфраструктура планетарного клімату**. Стандарт безпеки має бути **на рівні national-grid SCADA**, а не «не гірше за DeFi 2020–2024».
>
> **Деталі повної R&D-програми:** [`00_08 §1.4`](00_08_Beyond_TRL9_Planetary_Roadmap) — Apex Predator Defense Gap. Партнери: Аблязов Д. (СЄУ, правова рамка), Карапетян (ChDTU, статистика fraud detection), Ярмілко (firmware PQC integration).

## 6. Bonding Curves — Динамічне Ціноутворення (Перспектива TRL 9+)

Поточна модель: фіксований курс емісії ([`05_03`](05_03_Tokenomics_SCC_and_SFC)). Для планетарного масштабу можна розглянути алгоритмічне ціноутворення:

**Концепт:** Вартість мінтингу SCC алгоритмічно залежить від глобального показника здоров'я лісу (середній Z-value атрактора Лоренца по всіх кластерах). Чим здоровіший ліс → тим цінніший актив → тим більше growth_points потрібно для 1 SCC. ⚠️ **[Lorenz de-risk]** Прив'язка ціни до «середній Z = здоров'я лісу» передбачає доведений Z↔health ([`05_05 §8`](05_05_Slashing_and_Risk_Policy)) — ще одна причина «відкладено до TRL 9+».

**Чому відкладено:** Bonding Curves значно ускладнюють аудит контрактів, створюють MEV-вектори та потребують ліквідності для функціонування. Для TRL 6-8 фіксований курс є простішим та безпечнішим.

**Статус:** Перспективна ідея. Не планується до TRL 9+.

## 7. Governance-Aware Backend (✅ Реалізовано)

```ruby
# Замість: SIGMA = 10.0
# Тепер:
sigma = SystemParameter.current(:lorenz_sigma, default: 10.0)

# Замість: SLASH_THRESHOLD = 0.20
# Тепер:
threshold = SystemParameter.current(:slash_threshold, default: 0.20)

# Bulk fetch:
params = SystemParameter.current_values(lorenz_sigma: 10.0, lorenz_rho: 28.0)

# Admin/Governance update:
SystemParameter.set("lorenz_sigma", "12.0", updated_by: admin, source: "governance")
```

**`SystemParameter` model** (`app/models/system_parameter.rb`):
- Кеш поточних значень з TTL 24h (invalidation через `after_commit`)
- Fallback на `default:` при відсутності запису
- Type coercion: `integer`, `float`, `decimal`, `string`, `boolean`, `json`
- Bounds validation (`min_value` / `max_value`)
- Audit trail (`updated_by` → User FK, `source`: default/admin/governance)
- 19 seed-параметрів: Lorenz (σ/ρ/β/dt/iterations/z_min/z_max/z_target), tokenomics, alerts, hardware
- Синхронізація з `ProtocolParameters.sol` через The Graph — `Governance::ParameterSyncWorker` (§2)
