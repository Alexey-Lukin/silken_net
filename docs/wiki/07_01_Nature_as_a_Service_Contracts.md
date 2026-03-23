## 07_01: Nature-as-a-Service Contracts (Юридичний та Бізнес Шар)

**Модуль:** 07_01 — Nature-as-a-Service Contracts
**Пов'язані модулі:** [05_03 Tokenomics SCC/SFC](05_03_Tokenomics_SCC_and_SFC) · [07_02 Unit Economics & BOM](07_02_Unit_Economics_and_BOM) · [05_02 Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline)
**Поточний TRL:** 5 (Бізнес-логіка зафіксована в SSOT; юридичні документи відсутні — блокери задокументовані нижче)
**Цільовий TRL:** 6 (Перший реальний B2B контракт підписано з пілотним клієнтом)
**Статус Аудиту:** Reverse Shaping — лише документація поточного стану, без рефакторингу коду

> **⚠️ SSOT Sync:** Цей документ синхронізовано з кодовою базою станом на 2026-03-23.
> **Джерела правди:** `app/models/naas_contract.rb`, `app/services/contract_health_check_service.rb`, `app/services/contract_termination_service.rb`, `app/models/parametric_insurance.rb`, `contracts/SilkenCarbonCoin.sol`, `contracts/SilkenForestCoin.sol`, `db/structure.sql`.

---

## 🎯 Мета (Objective)

Зафіксувати бізнес-логіку та юридичні параметри моделі Nature-as-a-Service (NaaS): хто є клієнтами, що саме вони купують, як юридичні події відображаються у викликах смарт-контрактів (`mint`, `slash`) і які правові документи наразі відсутні.

Документ **не** є юридичним текстом. Він фіксує поточний стан ("як є") для синхронізації команди та партнерів.

---

## ✅ Статус (Status)

| Компонент | Стан |
|-----------|------|
| **NaasContract модель** | ✅ Реалізована (AASM state machine: `draft → active → fulfilled / breached / cancelled`) |
| **ContractHealthCheckService** | ✅ Реалізований (D-MRV арбітраж, 20% поріг критичних аномалій) |
| **ContractTerminationService** | ✅ Реалізований (Early exit з пропорційним поверненням та штрафом) |
| **SCC `mint()` + `slash()`** | ✅ Задеплоєно на Amoy testnet (Polygon) |
| **Parametric Insurance** | ✅ Реалізована (3 типи тригерів: `critical_fire`, `extreme_drought`, `insect_epidemic`) |
| **API ендпоінти** | ✅ `GET /contracts`, `GET /contracts/:id`, `GET /contracts/stats` |
| **KYC / Legal Templates** | 🔴 ВІДСУТНІ — блокери задокументовані нижче |
| **Mainnet деплой** | 🔴 Заблоковано критичними блокерами B-01–B-06 з [05_03_Tokenomics_SCC_and_SFC](05_03_Tokenomics_SCC_and_SFC) |

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

**Умови входу:**
- KYC/KYB верифікація через Polygon Hadron Identity Platform (ERC-3643). Поле `hadron_kyc_status = 'approved'` на `Wallet` є обов'язковою guard clause перед будь-яким мінтингом SCC.
- `total_funding > 0` (валідація моделі).
- `start_date < end_date`.

**Страхова премія (Hybrid Protocol Gaia):**
При активації контракту 5% від `total_funding` направляється до DAO Treasury Parametric Insurance Pool (константа `NaasContract::INSURANCE_PREMIUM_RATE = BigDecimal("0.05")`). Залишок 95% — `forester_share_amount` — надходить форестеру.

**Поточний стан:** Бізнес-логіка реалізована в коді. Юридичного шаблону угоди (Term Sheet, Master Service Agreement) — немає. Це BLOCKER-1.

---

### 1.2 B2C Individual — Підписка Власника Дерева

**Хто:** Приватні власники лісових ділянок, фізичні особи, які хочуть монетизувати або захистити свій ліс.

**Що купують:**
- Моніторинг здоров'я власних дерев (Soldier-вузли).
- SCC токени на свій `Wallet` (10,000 `growth_points` = 1 SCC).
- Мікро-нагороди у USDC на Solana (0.01–0.1 USDC за кожен LoRa пакет телеметрії).
- Celo ReFi нагороди (5 cUSD за здоровий кластер на добу) — якщо кластер проходить щоденний аудит.

**Умови входу:**
- Реєстрація через OAuth2 (Google/Apple) або стандартна автентифікація (argon2id).
- Роль `User.role = :investor` або `User.role = :forester`.
- `Wallet` автоматично створюється при реєстрації Tree-вузла.

**Поточний стан:** Технічна інфраструктура повністю готова. Публічного B2C онбординг-флоу (лендинг, ToS, Privacy Policy) — немає. Це BLOCKER-2.

---

### 1.3 DAO Agreement — Децентралізоване Управління

**Хто:** Власники SilkenForestCoin (SFC) — токену управління DAO.

**Що купують / контролюють:**
- Право голосу у протокольних рішеннях (зміна параметрів слешингу, схвалення нових кластерів).
- SFC мінтується за ті ж самі кластери, що генерують SCC, але через окремий виклик `SilkenForestCoin.mint(to, amount, clusterId)` з `MINTER_ROLE`.

**Умови входу:**
- Участь у верифікованій екосистемі (SCC-адреса на Polygon).
- Gasless approvals через EIP-2612 (`ERC20Permit`).

**Поточний стан:** SFC смарт-контракт задеплоєно. DAO Governance процес (Snapshot / Governor) — не визначений. Це BLOCKER-5.

---

## 📋 2. Таблиця SLA: Юридична Подія → On-Chain Транзакція

| Юридична Подія | D-MRV Тригер | Rails Worker | Смарт-Контракт | Функція | Наслідок |
|---|---|---|---|---|---|
| **Послуга надана** (дерево здорове, Z в межах норми) | `growth_points` ≥ 0, `stress_index < 0.83` | `TokenomicsEvaluatorWorker` → `MintCarbonCoinWorker` | `SilkenCarbonCoin.sol` | `mint(to, amount, treeDid)` | Інвестор отримує SCC на `Wallet.crypto_public_address`. **Guard clauses:** `verified_by_iotex? = true`, `oracle_status = "fulfilled"`, `hadron_kyc_status = "approved"` |
| **Пакетна емісія** (ціла лісова ділянка) | Batch з ≤200 дерев | `MintCarbonCoinWorker` (Gas Saving Mode) | `SilkenCarbonCoin.sol` | `batchMint(recipients[], amounts[], treeDids[])` | Масова емісія для всього кластера |
| **Дерево під стресом** (`stress_index ≥ 0.83`) | AiInsight.stress_index | `ClusterHealthCheckWorker` | — | Облік у D-MRV арбітражі | Якщо >20% кластера — тригер слешингу |
| **Порушення контракту** (>20% дерев аномальні) | `critical_insights_count > total_active_count / 5` | `ClusterHealthCheckWorker` → `BurnCarbonTokensWorker` | `SilkenCarbonCoin.sol` | `slash(investor, amount)` | SCC спалюються, `NaasContract.status = :breached`, EwsAlert створено |
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
| **Конверсія: growth_points → SCC** | 10,000 growth_points = 1 SCC | `docs/TOKENOMICS.md`, `TokenomicsEvaluatorWorker` |
| **Денне накопичення** | ~24 growth_points/дерево/добу (при 44 mV сап-потенціалі, 1 LoRa пакет/год) | `docs/TOKENOMICS.md` |
| **Поріг емісії** | `Wallet.balance >= 10,000` | `TokenomicsEvaluatorWorker` |
| **Страхова премія** | 5% від `total_funding` → DAO Treasury Pool | `NaasContract::INSURANCE_PREMIUM_RATE = BigDecimal("0.05")` |
| **Частка форестера** | 95% від `total_funding` | `NaasContract#forester_share_amount` |
| **Celo ReFi нагорода** | 5 cUSD / здоровий кластер / добу | `CeloRewardWorker`, `Celo::CommunityRewardService` |
| **Solana мікро-нагорода** | 0.01–0.1 USDC / LoRa пакет | `SolanaMicroRewardWorker`, `Solana::MintingService` |
| **Динамічна ціна SCC** | Uniswap V3 Quoter (Polygon), fallback $25.50 | `PriceOracleService` |
| **Штраф за дострокове розірвання** | `total_funding × early_exit_fee_percent / 100` | `NaasContract#calculate_early_exit_fee` |
| **Пропорційне повернення** | `total_funding × (remaining_days / total_days) − fee` | `NaasContract#calculate_prorated_refund` |
| **Поріг слешингу** | >20% дерев кластера з `stress_index >= 0.83` | `ContractHealthCheckService` |
| **1 SCC = X кг CO₂** | ⚠️ **Не визначено в коді** — юридичний блокер (→ BLOCKER-4 нижче) | — |
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
Daily Health Check        Catastrophic Event
(ClusterHealthCheck       (critical_fire, drought,
  Worker 02:00 UTC)        insect_epidemic)
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

| Роль | SCC `MINTER_ROLE` | SCC `SLASHER_ROLE` | SCC `DEFAULT_ADMIN_ROLE` | SFC `MINTER_ROLE` |
|---|---|---|---|---|
| Backend Oracle (`ORACLE_PRIVATE_KEY`) | ✅ | ✅ | ❌ | ✅ |
| Platform Admin (`ADMIN_ADDRESS`) | ❌ | ❌ | ✅ | ❌ (окремий admin) |

> ⚠️ **Архітектурна проблема (зовнішній модуль):** Той самий oracle отримує і `MINTER_ROLE`, і `SLASHER_ROLE` в конструкторі SCC. Компрометація `ORACLE_PRIVATE_KEY` — повний контроль над токеноекономікою. Задокументовано як **B-02** в зовнішньому модулі [05_03_Tokenomics_SCC_and_SFC](05_03_Tokenomics_SCC_and_SFC) (поза нумерацією блокерів цього документа).

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

## 🛑 8. Блокери (Blockers / Needs Action)

> Цей розділ є критично важливим. Жоден реальний B2B продаж неможливий без вирішення наступних пунктів.

---

### 🔴 BLOCKER-1: Відсутній юридичний шаблон NaaS угоди (Master Service Agreement)

**Статус:** Не розроблено. Блокує B2B продажі.

Код реалізує повний lifecycle NaaS контракту (`draft → active → fulfilled / breached / cancelled`), проте **жодного юридично обов'язкового документа не існує**. Перед підписанням будь-якого корпоративного контракту необхідно:

- **Master Service Agreement (MSA)** — основна рамкова угода між Silken Net та Організацією.
- **Service Level Agreement (SLA)** — параметри якості: час реакції на інциденти, uptime гарантії, умови відшкодування при недоступності системи.
- **Subscription Order Form** — документ на конкретний `NaasContract` (кластер, тривалість, `total_funding`, `cancellation_terms`).

**Дія:** Залучення юридичного консультанта (бажано з досвідом Web3 / ReFi) для підготовки шаблонів.

---

### 🔴 BLOCKER-2: Відсутні Terms of Service та Privacy Policy для B2C

**Статус:** Не розроблено. Блокує публічний онбординг.

Для залучення B2C клієнтів (приватних власників дерев) через публічний лендинг необхідні:

- **Terms of Service (ToS)** — умови використання платформи Silken Net.
- **Privacy Policy** — GDPR-сумісна (для ЄС), описує збір та обробку телеметричних даних.
- **Cookie Policy** — якщо є маркетинговий сайт.

**Дія:** Підготовка базових шаблонів ToS та Privacy Policy (GDPR, CCPA).

---

### 🔴 BLOCKER-3: Відсутній KYC/AML процес для B2B клієнтів

**Статус:** Технічна інфраструктура є (`hadron_kyc_status` на `Wallet`), юридичний процес — відсутній.

Polygon Hadron Identity Platform надає технічну верифікацію (ERC-3643), але **регуляторний KYC/AML процес** для юридичних осіб не визначений:

- Хто проводить KYC/KYB для корпорацій?
- Які документи збираються (виписка з реєстру, ID директора, proof of funds)?
- Яка юрисдикція? (ЄС — AMLD5, США — BSA, міжнародні — FATF)
- Скільки коштує ліцензія на надання таких послуг?

**Дія:** Консультація з compliance-спеціалістом та вибір KYC-провайдера (Sumsub, Veriff, або Polygon Hadron).

---

### 🔴 BLOCKER-4: Відсутнє юридичне визначення "1 SCC = X кг CO₂"

**Статус:** Не зафіксовано ні в коді, ні в документації.

Поточний стан: `10,000 growth_points = 1 SCC`, але:

- **Скільки кг CO₂ секвестровано за 1 SCC?** — Відповіді немає в жодному файлі.
- **За якою методологією?** — Verra VCS? Gold Standard? Puro.earth?
- **Хто верифікує ці розрахунки?** — IoTeX ZK-proof підтверджує *факт* телеметрії, але не *обсяг* секвестрації.
- **Яка юридична відповідальність** якщо реальний обсяг CO₂ розходиться з токенізованим?

Без цього визначення SCC є utility токеном без підкріплення, і його не можна легально використовувати для корпоративного ESG-звітування.

**Дія:** Залучення сертифікованого методолога (Verra, Gold Standard) для розробки та сертифікації методики підрахунку.

---

### 🟡 BLOCKER-5: Відсутній DAO Governance процес для SFC

**Статус:** SFC контракт задеплоєно, механізм голосування — не визначено.

SilkenForestCoin має `ERC20Votes` (checkpoint-based voting power), але:

- **Голосування відбувається де?** — Snapshot.org, Governor Bravo, або власна реалізація?
- **Які рішення підлягають голосуванню?** — Зміна параметра слешингу (20%)? Схвалення нових кластерів? Зміна курсу 10,000 growth_points = 1 SCC?
- **Quorum?** — Яка мінімальна частка SFC для валідного рішення?

**Дія:** Технічне рішення (Governor contract або Snapshot) + юридичне оформлення DAO як юридичної особи (DAO LLC, Swiss Verein, або інша структура).

---

### 🔴 BLOCKER-6: Відсутній процес реєстрації лісових ділянок як RWA

**Статус:** `hadron_asset_id` поле є в `naas_contracts`, `HadronAssetRegistrationWorker` реалізовано, але процес реєстрації не визначений.

Для реєстрації лісового масиву як Real World Asset (RWA) через Polygon Hadron необхідно:

- Правовстановлюючі документи на земельну ділянку (cadastral number, deed).
- Незалежна оцінка вартості біомаси.
- Юридична особа, що може бути власником RWA токена.

**Дія:** Пілотна реєстрація однієї лісової ділянки через Polygon Hadron з юридичним супроводом.

---

### 🔴 BLOCKER-7: SFC Voting Power не анулюється після Slashing (Security Attack Vector)

**Статус:** Архітектурна вада в `SilkenForestCoin.sol`. Блокує production запуск DAO governance.

При порушенні NaaS контракту спрацьовує Slashing Protocol:
1. `BurnCarbonTokensWorker` → `BlockchainBurningService` → `SilkenCarbonCoin.slash(investor, amount)` — SCC зловмисника **спалюються**.
2. `SilkenForestCoin.sol` **не має `SLASHER_ROLE`** та взагалі не має `slash()` функції.
3. Результат: зловмисник (власник аномального кластера) **зберігає повний DAO voting power** на SFC навіть після покарання.

**Вектор атаки:** Актор купує SFC, навмисно допускає порушення NaaS (або не заважає загибелі дерев), отримує slashing SCC, але зберігає право голосу і може блокувати DAO рішення проти себе. Конкретний поріг блокування залежить від quorum — який наразі не визначений (→ BLOCKER-5).

**Можливі рішення (потребують архітектурного рішення):**
- Додати `SLASHER_ROLE` до SFC (ламає ERC20Votes checkpoint-based snapshot model).
- Vote escrow (veToken): заморожувати SFC при breached NaasContract.
- Snapshot off-chain governance із ручним blacklist — централізовано, але швидко.

**Дія:** Архітектурне рішення до запуску DAO governance. Без нього механізм slashing є неповним.

---

### 🟡 BLOCKER-8: `signed_at` поле відсутнє у DB schema

**Статус:** Розбіжність між кодом контролера та схемою БД.

`Api::V1::ContractsController#index` серіалізує `NaasContract` з полем `signed_at`:

```ruby
only: [ :id, :status, :total_value, :emitted_tokens, :signed_at ]
```

Однак таблиця `naas_contracts` в `db/structure.sql` **не містить колонки `signed_at`** — `as_json` поверне `nil` для цього поля без помилки. Семантично це важливо: дата підписання контракту відрізняється від `created_at` та `start_date`.

**Дія:** Або додати міграцію з колонкою `signed_at timestamp` (дата фізичного підписання угоди), або видалити з `only:` у контролері.

---

## 🔗 9. Міжланцюгові Залежності (Cross-Module Dependencies)

```
[05_03 Tokenomics] ──── СИНХРОНІЗОВАНО ────► [07_01 NaaS Contracts]
  SCC.mint() / SCC.slash()                     Юридичне підґрунтя
  growth_points → SCC rate                     Contract types
  Slashing Protocol                             SLA mapping

[07_01 NaaS Contracts] ──── БЛОКУЄ ────► [07_02 Unit Economics & BOM]
  Фінансові константи (SCC price)               Unit cost calculation
  B2B contract value                            ROI модель

[07_01 NaaS Contracts] ──── БЛОКУЄ ────► B2B Sales (onboarding)
  MSA / SLA templates                          Перший корпоративний клієнт
  KYC/AML process                              Legality of operations

[05_02 Proof of Growth] ──── ЗАБЕЗПЕЧУЄ ────► [07_01 NaaS Contracts]
  peaq DID verification                        Trustless proof of service
  IoTeX ZK-proof                               Legal defensibility
  Chainlink Oracle                             On-chain audit trail
```

---

## 📊 10. API Endpoints (Contracts Registry)

| Метод | URL | Авт. | Опис |
|---|---|---|---|
| `GET` | `/api/v1/contracts` | Required | Портфель NaaS контрактів (з пагінацією Pagy) |
| `GET` | `/api/v1/contracts/:id` | Required | Деталі контракту з emission history |
| `GET` | `/api/v1/contracts/stats` | Required | Фінансова аналітика: `total_invested`, `tokens_minted`, `portfolio_health`, `market_value_usd` |

**GET /contracts/stats** повертає:
```json
{
  "total_invested": 150000.00,
  "total_tokens_minted": 12500.0,
  "portfolio_health": 87.3,
  "market_value_usd": 318750.00
}
```
де `market_value_usd = emitted_tokens × PriceOracleService.current_scc_price` (динамічна ціна Uniswap V3).

---

## 📌 Висновки (Summary)

| Аспект | Поточний стан |
|---|---|
| **Бізнес-логіка (код)** | ✅ Повністю реалізована: lifecycle, slashing, insurance, early exit |
| **On-chain механіка** | ✅ SCC mint/slash на Amoy testnet; mainnet заблоковано блокерами B-01–B-06 у [05_03](05_03_Tokenomics_SCC_and_SFC) + BLOCKER-7 цього документа |
| **D-MRV підкріплення** | ✅ peaq DID + IoTeX ZK + Chainlink + The Graph |
| **B2B продажі** | 🔴 Заблоковано: MSA, SLA, KYC відсутні (BLOCKER-1, BLOCKER-3) |
| **B2C онбординг** | 🔴 Заблоковано: ToS, Privacy Policy відсутні (BLOCKER-2) |
| **CO₂ методологія** | 🔴 Заблоковано: 1 SCC = ? кг CO₂ не визначено (BLOCKER-4) |
| **DAO Governance** | 🔴 SFC voting power зберігається після slashing — security вектор (BLOCKER-7) |
| **DAO Governance (операційно)** | 🟡 Технічно є (SFC), процес голосування не визначено (BLOCKER-5) |
| **RWA реєстрація** | 🟡 Інфраструктура є, процес не відпрацьований (BLOCKER-6) |
| **DB schema** | 🟡 `signed_at` відсутнє в schema, але є в контролері (BLOCKER-8) |
