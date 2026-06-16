# 07_01: Контракти Nature-as-a-Service (Юридичний та Бізнес-Шар)

## 🎯 Мета

Зафіксувати бізнес-логіку та юридичні параметри моделі Nature-as-a-Service (NaaS): хто є клієнтами, що саме вони купують, як юридичні події відображаються у викликах смарт-контрактів (`mint`, `slash`) і які правові документи наразі відсутні.

Документ **не** є юридичним текстом. Він фіксує поточний стан ("як є") для синхронізації команди та партнерів.

---

## ✅ Статус

- **Поточний TRL:** TRL 5 — бізнес-логіка зафіксована в SSOT; юридичні документи відсутні
- **Відкрите:** юридичні/compliance артефакти (MSA, KYC/AML, DAO governance, RWA реєстрація) → [`00_07`](00_07_Action_Plan_Tracker) (BIZ.*).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `app/models/naas_contract.rb` | NaasContract lifecycle (AASM) — SSOT коду |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | SCC/SFC + фінансові константи (home) |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Proof of Growth (мінтинг-тригер) |
| [`07_02` — Unit Economics and BOM](07_02_Unit_Economics_and_BOM) | Юніт-економіка, BOM |
| [`08_02` — Academic Institutions Registry](08_02_Academic_Institutions_Registry) | MSA / KYC legal (Аблязов) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | BIZ.1/2/3/4/6/9/11/13/14, UNI.8 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Реєстр Типів Контрактів (Contract Type Registry)](#-1-реєстр-типів-контрактів-contract-type-registry)
- [2. Таблиця SLA: Юридична Подія → On-Chain Транзакція](#-2-таблиця-sla-юридична-подія--on-chain-транзакція)
- [3. Фінансові Константи (Financial Constants)](#-3-фінансові-константи-financial-constants)
- [4. Життєвий Цикл NaaS Контракту](#-4-життєвий-цикл-naas-контракту)
- [5. Структура Даних (Data Model)](#-5-структура-даних-data-model)
- [6. Ієрархія Ролей та Доступу](#-6-ієрархія-ролей-та-доступу)
- [7. Параметричне Страхування (Insurance Layer)](#-7-параметричне-страхування-insurance-layer)
- [8. Юридичні та бізнес-передумови (open → 00_07)](#-8-юридичні-та-бізнес-передумови-open--00_07)
- [9. Міжланцюгові Залежності (Cross-Module Dependencies)](#-9-міжланцюгові-залежності-cross-module-dependencies)
- [10. API Endpoints (Contracts Registry)](#-10-api-endpoints-contracts-registry)
- [Висновки (Summary)](#-висновки-summary)
<!-- TOC:AUTO:END -->

---

## 👥 1. Реєстр Типів Контрактів (Contract Type Registry)

NaaS — це модель підписки, де клієнти (Організації) платять за моніторинг лісів і отримують натомість верифіковані вуглецеві токени (SCC) та токени управління DAO (SFC).

### 1.1 B2B Corporate — Корпоративна Підписка

**Хто:** Корпорації з ESG-зобов'язаннями (CO₂ нейтральність), страхові компанії, інвестиційні фонди, агролісогосподарські підприємства.

**Що купують:**
- Верифіковані SilkenCarbonCoin (SCC) токени, кожен з яких підкріплений реальними D-MRV даними біомаси конкретних дерев.
- Real-time dashboard зі станом лісового кластера через Streamr P2P та Prometheus.
- Параметричне страхування кластера (`ParametricInsurance`) від `critical_fire`, `extreme_drought`, `insect_epidemic`.
- Корпоративний ESG-звіт з можливістю ретайрменту SCC через KlimaDAO.
- **(Roadmap, ADR [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM))** Гіперлокальні мікрокліматичні дані (t°/RH/тиск/VPD з BME280) — data-as-a-service для агрохолдингів і страховиків: 1000+ датчиків *усередині* екосистеми проти усереднених метеостанцій на 50 км². Окреме джерело доходу поза SCC; доводить біопреципітацію цифрами.

**Умови входу:**
- KYC/KYB верифікація через Polygon Hadron Identity Platform (ERC-3643). Поле `hadron_kyc_status = 'approved'` на `Wallet` є обов'язковою guard clause перед будь-яким мінтингом SCC.
- `total_funding > 0` (валідація моделі).
- `start_date < end_date`.

**Страхова премія (Hybrid Protocol Gaia):**
При активації контракту 5% від `total_funding` направляється до DAO Treasury Parametric Insurance Pool (константа `NaasContract::INSURANCE_PREMIUM_RATE = BigDecimal("0.05")`). Залишок 95% — `forester_share_amount` — надходить форестеру.

**Поточний стан:** Бізнес-логіка реалізована в коді. Юридичного шаблону угоди (Term Sheet, Master Service Agreement) — немає → відкрите [`00_07`](00_07_Action_Plan_Tracker) BIZ.2 (B2B MSA).

---

### 1.2 B2C Individual — Підписка Власника Дерева

**Хто:** Приватні власники лісових ділянок, фізичні особи, які хочуть монетизувати або захистити свій ліс.

**Що купують:**
- Моніторинг здоров'я власних дерев (Soldier-вузли).
- SCC токени на свій `Wallet` (курс — [`05_03`](05_03_Tokenomics_SCC_and_SFC)).
- Мікро-нагороди у USDC на Solana (0.01–0.1 USDC за кожен LoRa пакет телеметрії).
- Celo ReFi нагороди (5 cUSD за здоровий кластер на добу) — якщо кластер проходить щоденний аудит.

**Умови входу:**
- Реєстрація через OAuth2 (Google/Apple) або стандартна автентифікація (argon2id).
- Роль `User.role = :investor` або `User.role = :forester`.
- `Wallet` автоматично створюється при реєстрації Tree-вузла.

**Поточний стан:** Технічна інфраструктура повністю готова. Публічного B2C онбординг-флоу (лендинг, ToS, Privacy Policy) — немає → відкрите [`00_07`](00_07_Action_Plan_Tracker) BIZ.3 (B2C ToS/Privacy).

---

### 1.3 DAO Agreement — Децентралізоване Управління

**Хто:** Власники SilkenForestCoin (SFC) — токену управління DAO.

**Що купують / контролюють:**
- Право голосу у протокольних рішеннях (зміна параметрів слешингу, схвалення нових кластерів).
- SFC мінтується за ті ж самі кластери, що генерують SCC, але через окремий виклик `SilkenForestCoin.mint(to, amount, clusterId)` з `MINTER_ROLE`.

**Умови входу:**
- Участь у верифікованій екосистемі (SCC-адреса на Polygon).
- Gasless approvals через EIP-2612 (`ERC20Permit`).

**Поточний стан:** SFC смарт-контракт задеплоєно. DAO Governance процес (Snapshot / Governor) — не визначений → механіка [`05_06`](05_06_Governance_and_DAO); юр-оформлення DAO → [`00_07`](00_07_Action_Plan_Tracker) BIZ.*.

---

## 📋 2. Таблиця SLA: Юридична Подія → On-Chain Транзакція

| Юридична Подія | D-MRV Тригер | Rails Worker | Смарт-Контракт | Функція | Наслідок |
|---|---|---|---|---|---|
| **Послуга надана** (дерево здорове, Z в межах норми) | `growth_points` ≥ 0, `stress_index < 0.83` | `TokenomicsEvaluatorWorker` (щогодинний cron) → `EvaluateTreeBatchWorker` → `Wallet#lock_and_mint!` → `BlockchainMintingService` (`telemetry_log: nil` для Path 2) | `SilkenCarbonCoin.sol` | `mint(to, amount, treeDid)` / `batchMint` | Інвестор отримує SCC на `Wallet.crypto_public_address`. **Guards (Path 2 — tokenomics aggregate):** `hadron_kyc_status = "approved"` (єдиний обов'язковий perimeter); `verified_by_iotex?` / `oracle_status` свідомо пропускаються — `growth_points` вже зараховані через AES-256-CBC decrypt + `valid_sensor_data?` у `TelemetryUnpackerService` (per-packet integrity). Альтернативний Path 1 (oracle-driven per-telemetry mint) тригериться `ChainlinkDispatchWorker` → `MintCarbonCoinWorker`. Cross-ref: [`05_02 §Усі Шляхи до lock_and_mint! [DOC.7]`](05_02_Proof_of_Growth_Pipeline). |
| **Пакетна емісія** (ціла лісова ділянка) | Batch з ≤100 дерев | `MintCarbonCoinWorker` (Gas Saving Mode) | `SilkenCarbonCoin.sol` | `batchMint(recipients[], amounts[], treeDids[])` | Масова емісія для всього кластера |
| **Дерево під стресом** (`stress_index ≥ 0.83`) | AiInsight.stress_index | `ClusterHealthCheckWorker` | — | Облік у D-MRV арбітражі | Якщо >20% кластера — тригер слешингу |
| **Порушення контракту** (>20% дерев аномальні) | `critical_insights_count > total_active_count / 5` | `ClusterHealthCheckWorker` (тригериться через `InsightBatchCallbacks#on_success` — коли всі `GenerateClusterInsightWorker` за добу зелені) → `BurnCarbonTokensWorker` | `SilkenCarbonCoin.sol` | `slash(investor, amount)` | SCC спалюються, `NaasContract.status = :breached`, EwsAlert створено |
| **Відсутність даних** (>24 год без телеметрії, Starlink-блекаут) | `AiInsight.empty?` для кластера | `ContractHealthCheckService` | `SilkenCarbonCoin.sol` | `slash(investor, amount)` | Ідентично порушенню контракту |
| **Дерево згоріло** (`AiInsight.insight_type = :critical_fire`) | TinyML: `fire` клас | `EcosystemHealingWorker` → `InsurancePayoutWorker` | `SilkenCarbonCoin.sol` або Etherisc DIP | `mint(to, payout)` або `triggerClaim()` | Параметричне страхування активується |
| **Посуха** (`extreme_drought`) | `AiInsight.insight_type = :extreme_drought` | `InsurancePayoutWorker` | `SilkenCarbonCoin.sol` або Etherisc DIP | `mint(to, payout)` або `triggerClaim()` | Параметрична виплата |
| **Шкідники** (`insect_epidemic`) | `AiInsight.insight_type = :insect_epidemic` | `InsurancePayoutWorker` | `SilkenCarbonCoin.sol` або Etherisc DIP | `mint(to, payout)` або `triggerClaim()` | Параметрична виплата |
| **Дострокове розірвання** (Early Exit Investor) | `ContractTerminationService.call(contract)` | Sync (API call) | `SilkenCarbonCoin.sol` | `slash(investor, burned_points)` (якщо `burn_accrued_points = true`) | `NaasContract.status = :cancelled`, повернення з вирахуванням штрафу |
| **Успішне завершення** (контракт закінчився) | `NaasContract.pending_completion` + аудит | `ClusterHealthCheckWorker` → `fulfill!` | — | — | `NaasContract.status = :fulfilled`, звіт в Filecoin |
| **Смерть дерева** (біологічна) | `Tree.status = :deceased`, MaintenanceRecord | `EcosystemHealingWorker` → `PuroEarthPassportWorker` | Puro.earth (майбутня інтеграція) | D-MRV Biomass Passport | Biochar CORC генерація на Puro.earth |
| **ESG Ретайрмент** | `KlimaRetirementWorker` | `KlimaRetirementWorker` → `KlimaDao::RetirementService` | KlimaDAO (Polygon) | `approve()` + `retire()` | SCC перено до `esg_retired_balance` (незворотно) |
| **Щотижнева фіналізація** | Cron (понеділок 03:00 UTC) | `EthereumAnchorWorker` | Ethereum L1 | `anchorStateRoot(bytes32)` | State Root → Ethereum Mainnet |

---

## 💰 3. Фінансові Константи (Financial Constants)

| Параметр | Значення | Джерело |
|---|---|---|
| **Конверсія: growth_points → SCC** | 10,000 growth_points = 1 SCC | [`05_03`](05_03_Tokenomics_SCC_and_SFC), `TokenomicsEvaluatorWorker` |
| **Денне накопичення** | ~24 growth_points/дерево/добу (~1 LoRa пакет/год; живлення EBFC Gen 2.0 **>500 mV**, а не застаріле 44 mV) | [`05_03`](05_03_Tokenomics_SCC_and_SFC) |
| **Поріг емісії** | `Wallet.balance >= 10,000` | `TokenomicsEvaluatorWorker` |
| **Страхова премія** | 5% від `total_funding` → DAO Treasury Pool | `NaasContract::INSURANCE_PREMIUM_RATE = BigDecimal("0.05")` |
| **Частка форестера** | 95% від `total_funding` | `NaasContract#forester_share_amount` |
| **Celo ReFi нагорода** | 5 cUSD / здоровий кластер / добу | `CeloRewardWorker`, `Celo::CommunityRewardService` |
| **Solana мікро-нагорода** | 0.01–0.1 USDC / LoRa пакет | `SolanaMicroRewardWorker`, `Solana::MintingService` |
| **Динамічна ціна SCC** | Uniswap V3 Quoter (Polygon), fallback $25.50 | `PriceOracleService` |
| **Штраф за дострокове розірвання** | `total_funding × early_exit_fee_percent / 100` | `NaasContract#calculate_early_exit_fee` |
| **Пропорційне повернення** | `total_funding × (remaining_days / total_days) − fee` | `NaasContract#calculate_prorated_refund` |
| **Поріг слешингу** | >20% дерев кластера з `stress_index >= 0.83` | `ContractHealthCheckService` |
| **1 SCC = X кг CO₂** | ✅ **2000 SCC = 1 tCO₂ (1 SCC = 0.5 kg CO₂)** — `SystemParameter.current(:scc_per_tonne_co2, default: 2000)`, `ProtocolParameters.sol#sccPerTonneCo2()` | [BIZ.1] |
| **1 SCC = $Y (контрактна вартість)** | ⚠️ **Не зафіксовано** — визначається динамічно через DEX | `PriceOracleService` |

---

## 🔄 4. Життєвий Цикл NaaS Контракту

```
Organization funds cluster
           │
           ▼
    NaasContract (status: draft)
    start_date, end_date, total_funding
    cancellation_terms (JSONB)
    5% → DAO Insurance Pool (INSURANCE_PREMIUM_RATE)
           │
           │ activate!
           ▼
    NaasContract (status: active)
    Trees earn growth_points per LoRa packet
    10,000 points → MintCarbonCoinWorker → SCC.mint()
           │
     ┌─────┴──────────────────┐
     │                        │
     ▼                        ▼
Daily Health Check         Catastrophic Event
(ClusterHealthCheck        (critical_fire, drought,
 Worker via                 insect_epidemic)
 InsightBatchCallbacks)
     │                        │
     │ >20% critical           │
     │ stress_index            │
     ▼                        ▼
NaasContract (:breached)  InsurancePayoutWorker
BurnCarbonTokens          (SCC mint або Etherisc
Worker → SCC.slash()       DIP triggerClaim())
EwsAlert created
AuditLog → Filecoin
     │                        │
     │ ≤20% stress             │
     ▼                        │
NaasContract (:active)         │
CeloRewardWorker               │
(5 cUSD/cluster/day)           │
     │                        │
     │ end_date reached        │
     ▼                        │
NaasContract (:fulfilled)      │
EthereumAnchorWorker ◄─────────┘
(weekly State Root → L1)
```

### Дострокове розірвання (Early Exit)

```
Investor → terminate_early!
           │
           ▼
ContractTerminationService
  validate_termination! (min_days_before_exit)
  calculate_prorated_refund
  calculate_early_exit_fee
           │
           ├─ burn_accrued_points = true
           │      → BurnCarbonTokensWorker → SCC.slash()
           │
           ▼
NaasContract (status: cancelled, cancelled_at: now)
```

---

## 🗃️ 5. Структура Даних (Data Model)

### NaasContract (таблиця `naas_contracts`)

| Поле | Тип | Опис |
|---|---|---|
| `organization_id` | bigint FK | Організація-клієнт |
| `cluster_id` | bigint FK | Лісовий кластер під захистом |
| `total_funding` | numeric | Загальна сума інвестиції (USDC/USD) |
| `start_date` | timestamp | Дата початку контракту |
| `end_date` | timestamp | Дата закінчення контракту |
| `status` | integer (enum) | `draft(0)`, `active(1)`, `fulfilled(2)`, `breached(3)`, `cancelled(4)` |
| `emitted_tokens` | numeric (default: 0.0) | Загальна кількість виміняних SCC |
| `cancellation_terms` | jsonb | `early_exit_fee_percent`, `burn_accrued_points`, `min_days_before_exit` |
| `cancelled_at` | timestamp | Час дострокового розірвання |
| `hadron_asset_id` | varchar | ID лісової ділянки як RWA в Polygon Hadron |

### Wallet (таблиця `wallets`)

| Поле | Тип | Опис |
|---|---|---|
| `tree_id` | bigint FK | Прив'язка до конкретного дерева |
| `balance` | numeric | Накопичені `growth_points` (поточні) |
| `locked_balance` | numeric (default: 0.0) | Заблоковані бали під час мінтингу (pessimistic lock) |
| `crypto_public_address` | varchar | Polygon-адреса для SCC |
| `organization_id` | bigint FK | Організація-власник (для агрегованого гаманця) |
| `solana_public_address` | varchar | Solana-адреса для USDC мікро-нагород |
| `hadron_kyc_status` | varchar (default: 'pending') | KYC статус: `pending`, `approved`, `rejected` |
| `esg_retired_balance` | numeric (default: 0.0) | Необоротно ретайрнуті SCC через KlimaDAO |
| `toucan_bridged_balance` | numeric (default: 0.0) | Перекинуті через Toucan Protocol (TCO2) |

### ParametricInsurance (таблиця `parametric_insurances`)

| Поле | Тип | Опис |
|---|---|---|
| `organization_id` | bigint FK | Страхувальник |
| `cluster_id` | bigint FK | Кластер під страховим захистом |
| `status` | integer (enum) | `active(0)`, `triggered(1)`, `paid(2)`, `expired(3)` |
| `trigger_event` | integer (enum) | `critical_fire(0)`, `extreme_drought(1)`, `insect_epidemic(2)` |
| `payout_amount` | numeric | Сума виплати |
| `threshold_value` | numeric | Поріг для тригера (% аномальних дерев) |
| `token_type` | integer (default: 0) | Тип токена виплати (SCC або SFC) |
| `required_confirmations` | integer (default: 3) | Мін. підтверджень D-MRV перед виплатою |
| `paid_at` | timestamp | Час виплати |
| `etherisc_policy_id` | varchar | ID Etherisc DIP policy (режим Oracle, виплата в USDC) |

---

## 🔑 6. Ієрархія Ролей та Доступу

| Роль | Код | Можливості щодо NaaS контрактів |
|---|---|---|
| `super_admin` | 3 | Повний доступ: `index`, `show`, `stats` для всіх організацій |
| `admin` | 2 | Доступ до контрактів власної організації |
| `forester` | 1 | Доступ до контрактів власної організації (польовий) |
| `investor` | 0 | Read-only: тільки власні контракти |

**Права на смарт-контракт (Polygon):**

| Роль | SCC `MINTER_ROLE` | SCC `SLASHER_ROLE` | SCC `DEFAULT_ADMIN_ROLE` | SFC `MINTER_ROLE` | SFC `SLASHER_ROLE` |
|---|---|---|---|---|---|
| Minter Oracle (`ORACLE_MINTER_PRIVATE_KEY`) | ✅ | ❌ | ❌ | ✅ | ❌ |
| Slasher Oracle (`ORACLE_SLASHER_PRIVATE_KEY`) | ❌ | ✅ | ❌ | ❌ | ✅ |
| Platform Admin (`ADMIN_ADDRESS`) | ❌ | ❌ | ✅ | ❌ (окремий admin) | ❌ |

> ✅ **B-02 ВИРІШЕНО (2026):** SCC та SFC контракти приймають `minterOracle` і `slasherOracle` як **окремі параметри конструктора** ([`05_03 §SCC Constructor`](05_03_Tokenomics_SCC_and_SFC), рядки 108-111). Backend використовує два фізично розділені приватні ключі — `ORACLE_MINTER_PRIVATE_KEY` у `BlockchainMintingService` (`app/services/blockchain_minting_service.rb`) та `ORACLE_SLASHER_PRIVATE_KEY` у `BlockchainBurningService` (`app/services/blockchain_burning_service.rb`). Компрометація одного гаманця не дає повного контролю над токеноекономікою — мінтер не може спалити, слешер не може емітувати. Backward-compatible fallback на старий `ORACLE_PRIVATE_KEY` залишається лише для legacy/migration сервісів (Celo, Etherisc, Toucan тощо).

---

## 🛡️ 7. Параметричне Страхування (Insurance Layer)

Страхування надається паралельно з NaaS контрактом і активується автоматично при настанні страхових подій.

**Два режими виплати:**

1. **Internal mode (default):** `InsurancePayoutWorker` → `BlockchainMintingService` → SCC/SFC емісія на Polygon.
2. **Oracle mode (Etherisc DIP):** Якщо `etherisc_policy_id` присутній, система переключається в режим Oracle: `Etherisc::ClaimService` → `triggerClaim()` → виплата USDC з децентралізованого пулу ліквідності Etherisc. Це запобігає інфляційному тиску на внутрішню токеноміку.

**Guard clauses перед виплатою:**
- `required_confirmations` (default: 3) незалежних D-MRV підтверджень.
- `ParametricInsurance.status = :active` (ще не тригернуто раніше).

---

## ⚖️ 8. Юридичні та бізнес-передумови (open → 00_07)

> Специфікація потрібних юридичних / compliance-артефактів для B2B/B2C запуску. Статуси трекаються в [`00_07`](00_07_Action_Plan_Tracker) (BIZ.*).

---

### Відсутній юридичний шаблон NaaS угоди (Master Service Agreement)

**Статус:** Не розроблено. Блокує B2B продажі.

Код реалізує повний lifecycle NaaS контракту (`draft → active → fulfilled / breached / cancelled`), проте **жодного юридично обов'язкового документа не існує**. Перед підписанням будь-якого корпоративного контракту необхідно:

- **Master Service Agreement (MSA)** — основна рамкова угода між Silken Net та Організацією.
- **Service Level Agreement (SLA)** — параметри якості: час реакції на інциденти, uptime гарантії, умови відшкодування при недоступності системи.
- **Subscription Order Form** — документ на конкретний `NaasContract` (кластер, тривалість, `total_funding`, `cancellation_terms`).

**Дія:** Залучення юридичного консультанта (бажано з досвідом Web3 / ReFi) для підготовки шаблонів. **Академічний шлях вирішення:** СЄУ (Аблязов Денис Едуардович, к.ю.н., доцент кафедри публічного та приватного права) — розробка шаблонів MSA, Term Sheet та Carbon Credit Purchase Agreement згідно з MiCA та українським законодавством. Детально: [`08_02 §5`](08_02_Academic_Institutions_Registry).

---

### Відсутні Terms of Service та Privacy Policy для B2C

**Статус:** Не розроблено. Блокує публічний онбординг.

Для залучення B2C клієнтів (приватних власників дерев) через публічний лендинг необхідні:

- **Terms of Service (ToS)** — умови використання платформи Silken Net.
- **Privacy Policy** — GDPR-сумісна (для ЄС), описує збір та обробку телеметричних даних.
- **Cookie Policy** — якщо є маркетинговий сайт.

**Дія:** Підготовка базових шаблонів ToS та Privacy Policy (GDPR, CCPA).

---

### Відсутній KYC/AML процес для B2B клієнтів

**Статус:** Технічна інфраструктура є (`hadron_kyc_status` на `Wallet`), юридичний процес — відсутній.

Polygon Hadron Identity Platform надає технічну верифікацію (ERC-3643), але **регуляторний KYC/AML процес** для юридичних осіб не визначений:

- Хто проводить KYC/KYB для корпорацій?
- Які документи збираються (виписка з реєстру, ID директора, proof of funds)?
- Яка юрисдикція? (ЄС — AMLD5, США — BSA, міжнародні — FATF)
- Скільки коштує ліцензія на надання таких послуг?

**Дія:** Консультація з compliance-спеціалістом та вибір KYC-провайдера (Sumsub, Veriff, або Polygon Hadron). **Академічний шлях вирішення:** СЄУ (Аблязов Денис Едуардович) — юридична рамка KYC/AML для B2B клієнтів у контексті ERC-3643 та AMLD5/FATF регулювань; СЄУ (Ус Галина Олександрівна) — бухгалтерська класифікація KYC витрат та compliance-процесів у корпоративному обліку. Детально: [`08_02 §5`](08_02_Academic_Institutions_Registry).

---

### Відсутній B2B Fiat-to-Retirement шлях (SPV-міст) [нот.19]

**Статус:** Не специфіковано. Блокує масовий B2B-онбординг (`00_07 BIZ.15`).

Корпорації з ESG-зобов'язаннями **не триматимуть крипту** на балансі й не керуватимуть Polygon-гаманцями/ключами заради ретайрменту. Поточний шлях ([`05_03`](05_03_Tokenomics_SCC_and_SFC) `KlimaRetirementWorker` → on-chain `retire()`) припускає, що клієнт уже володіє SCC on-chain. Бракує **Fiat-to-Retirement SPV** — інструмента, де корпорація платить фіат, а юр-особа-оператор (SPV) купує+ретайрить SCC від її імені й видає сертифікат офсету (CBAM/ISO 14064-сумісний):

- Юрисдикція SPV + ліцензія на роботу з вуглецевими активами; хто кастодіан крипти.
- Bridge фіат → купівля SCC → `esg_retired_balance` (незворотно) → сертифікат.
- Audit-trail ретайрменту (Filecoin immutable archive — нот.18) для регуляторного звіту.

**Дія:** юридична рамка SPV — СЄУ (Аблязов Д., RWA/MiCA) + бухгалтерія — СЄУ (Ус Г.). Cross-ref [`08_02 §5`](08_02_Academic_Institutions_Registry).

---


### Відсутній DAO Governance процес для SFC

**Статус:** SFC контракт задеплоєно, механізм голосування — не визначено.

SilkenForestCoin має `ERC20Votes` (checkpoint-based voting power), але:

- **Голосування відбувається де?** — Snapshot.org, Governor Bravo, або власна реалізація?
- **Які рішення підлягають голосуванню?** — Зміна параметра слешингу (20%)? Схвалення нових кластерів? Зміна курсу емісії ([`05_03`](05_03_Tokenomics_SCC_and_SFC))?
- **Quorum?** — Яка мінімальна частка SFC для валідного рішення?

**Дія:** Технічне рішення (Governor contract або Snapshot) + юридичне оформлення DAO як юридичної особи (DAO LLC, Swiss Verein, або інша структура).

---

### Відсутній процес реєстрації лісових ділянок як RWA

**Статус:** `hadron_asset_id` поле є в `naas_contracts`, `HadronAssetRegistrationWorker` реалізовано, але процес реєстрації не визначений.

Для реєстрації лісового масиву як Real World Asset (RWA) через Polygon Hadron необхідно:

- Правовстановлюючі документи на земельну ділянку (cadastral number, deed).
- Незалежна оцінка вартості біомаси.
- Юридична особа, що може бути власником RWA токена.

**Дія:** Пілотна реєстрація однієї лісової ділянки через Polygon Hadron з юридичним супроводом.

> 📋 **Юридичний супровід — рекомендована послідовність:**
> 1. **UA-юрисдикція:** Кафедра Інтелектуальної Власності та Цивільно-Правових Дисциплін ЧНУ — меморандум "Юридична допустимість токенізації UA-лісу через ERC-3643" (cross-ref [`08_01 §2.1.2`](08_01_Joint_Publications_and_IP_Strategy)). Перевіряє сумісність з Лісовим Кодексом України та Законом «Про природно-заповідний фонд».
> 2. **EU/MiCA:** Аблязов Д.Е. (СЄУ) — Стаття 32 у [`08_01 §1F`](08_01_Joint_Publications_and_IP_Strategy), правова рамка ERC-3643 / MiCA для лісових RWA.
> 3. **Пілотна реєстрація:** одна ділянка Черкаського бору / ПЗФ за двостороннім меморандумом ЧНУ + СЄУ.

---

### SFC Voting Power зберігається після Slashing (Security Attack Vector)

**Статус:** 🟡 ЧАСТКОВО ВИРІШЕНО — `SilkenForestCoin.sol` реалізує `SLASHER_ROLE` + `slash()`. Голосування токени SFC тепер зменшуються при slashing (ERC20Votes `_update` → `_transferVotingUnits` → checkpoint update). Атака через купівлю SFC + навмисне порушення NaaS більше неможлива.

**Залишковий ризик:** Між нарахуванням SCC slash-події та обробкою `SilkenForestCoin.slash()` існує часовий лаг (бекенд-pipeline + Web3 черга `web3_critical`). Протягом цього вікна (~1–5 хв) учасник технічно може проголосувати. Для додаткового захисту рекомендується Vote Escrow (veToken) при активних NaaS контрактах зі статусом `breached`.

При порушенні NaaS контракту спрацьовує Slashing Protocol:
1. `BurnCarbonTokensWorker` → `BlockchainBurningService` → `SilkenCarbonCoin.slash(investor, amount)` — SCC зловмисника **спалюються**.
2. ✅ `SilkenForestCoin.sol` **має `SLASHER_ROLE`** (рядок 37) та `slash()` функцію (рядок 148) — реалізовано в `[B-06]`.
3. Результат: зловмисник **втрачає voting power** пропорційно обсягу slash.

**Поточний стан коду** (`contracts/SilkenForestCoin.sol`):
```solidity
bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE"); // рядок 37
function slash(address investor, uint256 amount) external onlyRole(SLASHER_ROLE) nonReentrant { ... } // рядок 148
```

**Дія:** Vote Escrow — опціональне покращення для повного DAO governance launch.

---


## 🔗 9. Міжланцюгові Залежності (Cross-Module Dependencies)

```
[05_03 Tokenomics] ──── СИНХРОНІЗОВАНО ────► [07_01 NaaS Contracts]
[07_01 NaaS Contracts] ──── БЛОКУЄ ────► [07_02 Unit Economics & BOM]
[07_01 NaaS Contracts] ──── БЛОКУЄ ────► B2B Sales (onboarding)
[05_02 Proof of Growth] ──── ЗАБЕЗПЕЧУЄ ────► [07_01 NaaS Contracts]
```

---

## 📊 10. API Endpoints (Contracts Registry)

| Метод | URL | Авт. | Опис |
|---|---|---|---|
| `GET` | `/api/v1/contracts` | Required | Портфель NaaS контрактів (Pagy) |
| `GET` | `/api/v1/contracts/:id` | Required | Деталі контракту |
| `GET` | `/api/v1/contracts/stats` | Required | `total_invested`, `tokens_minted`, `portfolio_health`, `market_value_usd` |

---

---

## 📌 Висновки (Summary)

| Аспект | Поточний стан |
|---|---|
| **Бізнес-логіка (код)** | ✅ Повністю реалізована: lifecycle, slashing, insurance, early exit |
| **On-chain механіка** | ✅ SCC mint/slash на Amoy testnet; mainnet заблоковано |
| **D-MRV підкріплення** | ✅ peaq DID + IoTeX ZK + Chainlink + The Graph |
| **B2B продажі** | 🔴 Заблоковано: MSA, SLA, KYC відсутні |
| **B2C онбординг** | 🔴 Заблоковано: ToS, Privacy Policy відсутні |
| **CO₂ методологія** | ✅ 2000 SCC = 1 tCO₂ (1 SCC = 0.5 kg CO₂) — on-chain + SystemParameter |
| **DAO Governance** | 🟡 SFC slash() реалізовано; Vote Escrow — опціонально |
| **RWA реєстрація** | 🟡 Інфраструктура є, процес не відпрацьований |
| **DB schema** | ✅ Узгоджено (`signed_at` прибрано з коду) |
