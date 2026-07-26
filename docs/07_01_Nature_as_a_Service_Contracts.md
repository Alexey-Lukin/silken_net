# 07_01: Контракти Nature-as-a-Service (Юридичний та Бізнес-Шар)

## 🎯 Мета

Зафіксувати бізнес-логіку та юридичні параметри моделі Nature-as-a-Service (NaaS): хто є клієнтами, що входить у послугу, як юридичні події відображаються у викликах смарт-контрактів (`mint`, `slash`) і які правові документи наразі відсутні.

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
| [`07_03` — Academic Institutions Registry](07_03_Academic_Integration_and_IP) | MSA / KYC legal (Аблязов) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | §07 юр/бізнес-дім: BIZ.2/3/9/11/14/15/18/19/20/21/22 (BIZ.17 → [`07_02`](07_02_Unit_Economics_and_BOM); BIZ.13 → [`05_05`](05_05_Slashing_and_Risk_Policy)) |

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

NaaS — це модель підписки, де клієнти (Організації) платять за вимірювану D-MRV-послугу моніторингу лісів. SCC — атестація обсягу наданої послуги (підкріплена D-MRV-даними конкретних дерев); SFC — токен управління DAO.

### 1.1 B2B Corporate — Корпоративна Підписка

**Хто:** Корпорації з ESG-зобов'язаннями (CO₂ нейтральність), страхові компанії, інвестиційні фонди, агролісогосподарські підприємства.

**Що входить у послугу:**
- Верифіковані SilkenCarbonCoin (SCC) токени, кожен з яких підкріплений реальними D-MRV даними біомаси конкретних дерев.
- Real-time dashboard зі станом лісового кластера через Streamr P2P та Prometheus.
- Параметричне страхування кластера (`ParametricInsurance`) від `critical_fire`, `extreme_drought`, `insect_epidemic`.
- Корпоративний ESG-звіт з можливістю ретайрменту SCC через KlimaDAO.
- **(Roadmap, ADR [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM))** Гіперлокальні мікрокліматичні дані (t°/RH/тиск/VPD з BME280) — data-as-a-service для агрохолдингів і страховиків: 1000+ датчиків *усередині* екосистеми проти усереднених метеостанцій на 50 км². Окреме джерело доходу поза SCC; має кількісно вимірювати біопреципітацію.
- **(Roadmap, deferred SLA-фасети)** Predictive tree-fall як SLA-підписка — конкретні дерева, що впадуть під вітром (`z_value` + гіро-аналіз стовбура, [`03_04`](03_04_mruby_Lorenz_Attractor)) для енерго-ЛЕП / автотрас+залізниці (Service-of-Roads) / муніципальних парків (позови за аварійні стовбури) + захист берегозахисних лісосмуг Дніпра + оптимізація міського поливу за `delta_t` гідратації ксилеми (економія бюджету). SLA-дім → §2.

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

**Що входить у послугу:**
- Моніторинг здоров'я власних дерев (Soldier-вузли).
- SCC токени на свій `Wallet` (курс — [`05_03`](05_03_Tokenomics_SCC_and_SFC)).
- Мікро-нагороди у USDC на Solana (0.01–0.1 USDC за кожен LoRa пакет телеметрії).
- Celo ReFi нагороди (5 cUSD за здоровий кластер на добу) — якщо кластер проходить щоденний аудит.
- **(Roadmap, deferred B2C) Eco-Therapy 4.0** — цифрова лісотерапія: користувач біля дерева відкриває додаток → бачить «пульс» (`delta_t`) → синхронізація з природними ритмами. Перший у світі інструмент цифрової лісотерапії (напр. реабілітація ветеранів з ПТСД).

**Умови входу:**
- Реєстрація через OAuth2 (Google / Facebook / LinkedIn / Twitter — `Identity::SUPPORTED_PROVIDERS`; OmniAuth-флоу ще без дроту → [`00_07`](00_07_Action_Plan_Tracker) ARCH.69) або стандартна автентифікація (argon2id).
- Роль `User.role = :investor` або `User.role = :forester`.
- `Wallet` автоматично створюється при реєстрації Tree-вузла.

**Поточний стан:** Бекенд-інфраструктура (онбординг / Wallet / rewards) готова; on-chain SCC-мінт gated на деплой контрактів (SEC.1) + securities-присуд (BIZ.22). Публічного B2C онбординг-флоу (лендинг, ToS, Privacy Policy) — немає → відкрите [`00_07`](00_07_Action_Plan_Tracker) BIZ.3 (B2C ToS/Privacy).

---

### 1.3 DAO Agreement — Децентралізоване Управління

**Хто:** Власники SilkenForestCoin (SFC) — токену управління DAO.

**Що дає SFC:**
- Право голосу у протокольних рішеннях (зміна параметрів слешингу, схвалення нових кластерів).
- SFC мінтується за ті ж самі кластери, що генерують SCC, але через окремий виклик `SilkenForestCoin.mint(to, amount, clusterId)` з `MINTER_ROLE`.

**Умови входу:**
- Участь у верифікованій екосистемі (SCC-адреса на Polygon).
- Gasless approvals через EIP-2612 (`ERC20Permit`).

**Поточний стан:** SFC смарт-контракт code-complete + CI-audited, **ще НЕ задеплоєно** (placeholder-адреса до mainnet, [`05_03`](05_03_Tokenomics_SCC_and_SFC)). DAO Governance процес (Snapshot / Governor) — не визначений → механіка [`05_06`](05_06_Governance_and_DAO); юр-оформлення DAO → [`00_07`](00_07_Action_Plan_Tracker) BIZ.*.

---

## 📋 2. Таблиця SLA: Юридична Подія → On-Chain Транзакція

| Юридична Подія | D-MRV Тригер | Rails Worker | Смарт-Контракт | Функція | Наслідок |
|---|---|---|---|---|---|
| **Послуга надана** (дерево здорове, Z в межах норми) | `growth_points` ≥ 0, `stress_index < 0.83` | `TokenomicsEvaluatorWorker` (щогодинний cron) → `EvaluateTreeBatchWorker` → `Wallet#lock_and_mint!` → `BlockchainMintingService` (`telemetry_log: nil` для Path 2) | `SilkenCarbonCoin.sol` | `mint(to, amount, treeDid)` / `batchMint` | Клієнт отримує SCC на `Wallet.crypto_public_address`. **Guards (Path 2 — tokenomics aggregate):** `hadron_kyc_status = "approved"` (єдиний обов'язковий perimeter); `verified_by_iotex?` / `oracle_status` свідомо пропускаються — `growth_points` вже зараховані через AES-256-CBC decrypt + `valid_sensor_data?` у `TelemetryUnpackerService` (per-packet integrity). Альтернативний Path 1 (oracle-driven per-telemetry mint) — **латентний**: `ChainlinkDispatchWorker` dispatch = local-marker без RPC, callback unwired ([`00_07` ARCH.53](00_07_Action_Plan_Tracker)); живий мінт-шлях = Path 2 (вище). Cross-ref: [`05_02 §Усі Шляхи до lock_and_mint! [DOC.7]`](05_02_Proof_of_Growth_Pipeline). |
| **Пакетна емісія** (ціла лісова ділянка) | Batch з ≤100 дерев | `MintCarbonCoinWorker` (Gas Saving Mode) | `SilkenCarbonCoin.sol` | `batchMint(recipients[], amounts[], treeDids[])` | Масова емісія для всього кластера |
| **Дерево під стресом** (`stress_index ≥ 0.83`) | AiInsight.stress_index | `ClusterHealthCheckWorker` | — | Облік у D-MRV арбітражі | Якщо >20% кластера — тригер слешингу |
| **Порушення контракту** (>20% дерев аномальні) | `critical_insights_count > total_active_count / 5` | `ClusterHealthCheckWorker` (тригериться через `InsightBatchCallbacks#on_success` — коли всі `GenerateClusterInsightWorker` за добу зелені) → `BurnCarbonTokensWorker` | `SilkenCarbonCoin.sol` | `slash(investor, amount)` (gated) | [SLASH-1] **positive-A gate** ([`05_05 §3.2`](05_05_Slashing_and_Risk_Policy)): прямий доказ Кат-A (`vandalism_breach` — єдиний A-сигнал у коді; авто-writer'а немає → ручна C→A ескалація, на практиці freeze-first) → SCC спалюються + `status = :breached`; інакше (вкл. `chainsaw_detected` — реальна пилка, але поза A-сетом) → `:frozen` + Field-Audit `EwsAlert` (no burn, контракт лишається активним до C→A класифікації) |
| **Відсутність даних** (cluster-wide blackout — Starlink/шлюз) | `AiInsight.empty?` для кластера | `ContractHealthCheckService#flag_data_blackout!` | — (no on-chain дія) | `EwsAlert(:field_audit)` | **Force-majeure-сигнатура** (вкрадений/знищений шлюз, блекаут) → Field Audit (Category C), **НЕ** slash — карати лісника за збитий шлюз = false slash ([`05_05 §6`](05_05_Slashing_and_Risk_Policy)) |
| **Дерево згоріло** (`AiInsight.insight_type = :critical_fire`) | TinyML: `fire` клас | `EcosystemHealingWorker` → `InsurancePayoutWorker` | `SilkenCarbonCoin.sol` або Etherisc DIP | `mint(to, payout)` або `triggerClaim()` | Параметричне страхування активується |
| **Посуха** (`extreme_drought`) | `AiInsight.insight_type = :extreme_drought` | `InsurancePayoutWorker` | `SilkenCarbonCoin.sol` або Etherisc DIP | `mint(to, payout)` або `triggerClaim()` | Параметрична виплата |
| **Шкідники** (`insect_epidemic`) | `AiInsight.insight_type = :insect_epidemic` | `InsurancePayoutWorker` | `SilkenCarbonCoin.sol` або Etherisc DIP | `mint(to, payout)` або `triggerClaim()` | Параметрична виплата |
| **Дострокове розірвання** (Early Exit клієнта) | `ContractTerminationService.call(contract)` | Sync (API call) | `SilkenCarbonCoin.sol` | `slash(investor, burned_points)` (якщо `burn_accrued_points = true`; `contractual: true` — пропускає positive-A gate, бо це погоджена форфейтура, не slash-за-провину) | `NaasContract.status = :cancelled`, повернення з вирахуванням штрафу |
| **Успішне завершення** (контракт закінчився) | `NaasContract.pending_completion` + аудит | `ClusterHealthCheckWorker` → `fulfill!` | — | — | `NaasContract.status = :fulfilled`, звіт в Filecoin |
| **Смерть дерева** (біологічна) | `Tree.status = :deceased`, MaintenanceRecord | `EcosystemHealingWorker` → `PuroEarthPassportWorker` | Puro.earth (`PuroEarthPassportWorker` ✅ код; on-chain post-TRL 7) | D-MRV Biomass Passport | Biochar CORC генерація на Puro.earth |
| **ESG Ретайрмент** | `KlimaRetirementWorker` | `KlimaRetirementWorker` → `KlimaDao::RetirementService` | KlimaDAO (Polygon) | `approve()` + `retire()` | SCC перено до `esg_retired_balance` (незворотно) |
| **Щотижнева фіналізація** | Cron (понеділок 03:00 UTC) | `EthereumAnchorWorker` | Ethereum L1 | `anchorStateRoot(bytes32)` | State Root → Ethereum Mainnet |

> **[INS.1] Insurance-перили потребують НЕЗАЛЕЖНОГО Trigger-2 — не платяться напряму.** Рядки «Дерево згоріло / Посуха / Шкідники» — це ЛЕГАЛЬНИЙ наслідок; механічно виплата йде лише за **dual-trigger** (Trigger-1 AI-кандидат + Trigger-2 незалежне підтвердження, [`05_05 §4`](05_05_Slashing_and_Risk_Policy)). Реальний Trigger-2 існує ЛИШЕ для **пожежі** (dClimate FIRMS-супутник); **посуха/шкідник супутникового оракула НЕ мають** → `Dclimate::VerificationService` ескалює їх у `:inconclusive`/**Field-Audit** (Кат-C, ніколи `rejected_fraud`/slash), доки не з'явиться реальне drought/pest-джерело (👤 [`00_07` INS.1/S3.2/UNI.12](00_07_Action_Plan_Tracker)).

---

## 💰 3. Фінансові Константи (Financial Constants)

| Параметр | Значення | Джерело |
|---|---|---|
| **Конверсія: growth_points → SCC** | 10,000 growth_points = 1 SCC | [`05_03`](05_03_Tokenomics_SCC_and_SFC), `TokenomicsEvaluatorWorker` |
| **Денне накопичення** | **Calibration-pending** (`delta_t` recharge-каденція + GP-магнітуда = placeholder, чекають bench-кривої, [E.63](00_07_Action_Plan_Tracker)). Self-consistent realistic (Variant C, `delta_t`≈1.77 год [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)): ~13.6 пакети/добу × ~16 stored GP = **~217 growth_points/добу → ~8 SCC/дерево/рік**. Магнітуда = f(EBFC recharge): швидший `delta_t` → вище (фіз. стеля Δt=600s ≈ 326 SCC/рік; 1 TX/год = energy-negative без мітигацій). wire 5–31 × [FW.29] ×2 | [`05_03`](05_03_Tokenomics_SCC_and_SFC), [`07_02 §7.1`](07_02_Unit_Economics_and_BOM), [`02_03 §9`](02_03_BQ25570_MPPT_Nano_Power) |
| **Поріг емісії** | `Wallet.balance >= 10,000` | `TokenomicsEvaluatorWorker` |
| **Страхова премія** | 5% від `total_funding` → DAO Treasury Pool | `NaasContract::INSURANCE_PREMIUM_RATE = BigDecimal("0.05")` |
| **Частка форестера** | 95% від `total_funding` | `NaasContract#forester_share_amount` |
| **Celo ReFi нагорода** | 5 cUSD / здоровий кластер / добу | `CeloRewardWorker`, `Celo::CommunityRewardService` |
| **Solana мікро-нагорода** | 0.01–0.1 USDC / LoRa пакет | `SolanaMicroRewardWorker`, `Solana::MintingService` |
| **Динамічна ціна SCC** | Uniswap V3 Quoter (Polygon), fallback $25.50 | `PriceOracleService` |
| **Штраф за дострокове розірвання** | `total_funding × early_exit_fee_percent / 100` | `NaasContract#calculate_early_exit_fee` |
| **Пропорційне повернення** | `total_funding × (remaining_days / total_days) − fee` | `NaasContract#calculate_prorated_refund` |
| **Поріг слешингу** | >20% дерев кластера з `stress_index >= 0.83` | `ContractHealthCheckService` |
| **1 SCC = X кг CO₂** | ✅ **2000 SCC = 1 tCO₂ (1 SCC = 0.5 kg CO₂)** — `SystemParameter.current(:scc_per_tonne_co2, default: 2000)`, `ProtocolParameters.sol#sccPerTonneCo2()`. **Внутрішня облікова конвенція** Proof-of-Growth (Condition-прочитання — [`07_02 §7`](07_02_Unit_Economics_and_BOM)), НЕ registry-визнаний tCO₂e-кредит: продаваний кредит лише через незалежну методологію (BIZ.9); трек = MRV-Data-Provider/permanence-monitor | [BIZ.1] |
| **1 SCC = $Y (контрактна вартість)** | ⚠️ **Не зафіксовано** — визначається динамічно через DEX | `PriceOracleService` |

---

## 🔄 4. Життєвий Цикл NaaS Контракту

```
Organization pays for monitoring
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
Client → terminate_early!
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
| `total_funding` | numeric | Загальна сума оплати за послугу (USDC/USD) |
| `start_date` | timestamp | Дата початку контракту |
| `end_date` | timestamp | Дата закінчення контракту |
| `status` | integer (enum) | `draft(0)`, `active(1)`, `fulfilled(2)`, `breached(3)`, `cancelled(4)` |
| `emitted_tokens` | numeric (default: 0.0) | Загальна кількість емітованих SCC |
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

> ✅ **B-02 ВИРІШЕНО (2026):** SCC та SFC контракти приймають `minterOracle` і `slasherOracle` як **окремі параметри конструктора** ([`05_03 §SCC Constructor`](05_03_Tokenomics_SCC_and_SFC), рядки 108-111). Backend використовує два фізично розділені приватні ключі — `ORACLE_MINTER_PRIVATE_KEY` у `BlockchainMintingService` (`app/services/blockchain_minting_service.rb`) та `ORACLE_SLASHER_PRIVATE_KEY` у `BlockchainBurningService` (`app/services/blockchain_burning_service.rb`). Компрометація одного гаманця не дає повного контролю над токеноекономікою — мінтер не може спалити, слешер не може емітувати. Легасі спільний `ORACLE_PRIVATE_KEY` **retired повністю [INF.22, 2026-07-10]**: кожен aux-підписант (Celo/Etherisc/PuroEarth/Klima) має власний dedicated-ключ, а `Security::Web3NetworkGuard` відмовляє значенню під старим ім'ям.

---

## 🛡️ 7. Параметричне Страхування (Insurance Layer)

Страхування надається паралельно з NaaS контрактом. **[INS.1] Dual-trigger:** денний AI-оракул (`ParametricInsurance#evaluate_daily_health!` через `InsuranceOracleWorker`, за прапором `:parametric_insurance_oracle_enabled`) лише ОЗБРОЮЄ кандидата (`:triggered`); виплата йде ЛИШЕ за НЕЗАЛЕЖНИМ підтвердженням (dClimate satellite / Field-Audit) — політика-дім [`05_05 §4`](05_05_Slashing_and_Risk_Policy).

**Два режими виплати:**

1. **Internal mode (default):** `InsurancePayoutWorker` → `BlockchainMintingService` → SCC/SFC емісія на Polygon. **[INS.2]** Ця емісія **інфляційна** (мінтить новий SCC, не бере з пулу) → перед mint `Insurance::ReserveGate` накладає systemic stop-loss: (1) aggregate 24h correlated-event cap + (2) reserve-adequacy (30d Internal-mint vs `DAO_TREASURY`-баланс × ratio). Обидва пороги **inert-default** (`SystemParameter` 0 = off; калібрування = 👤 economic-політика → [`00_07` INS.2](00_07_Action_Plan_Tracker)). Breach → HOLD у `manual_review` (не незабезпечений mint); transient RPC → Sidekiq-retry (fail-closed, без permanent park). Etherisc-виплати з cap виключено (зовнішній USDC, не наша емісія).
2. **Oracle mode (Etherisc DIP):** Якщо `etherisc_policy_id` присутній, система переключається в режим Oracle: `Etherisc::ClaimService` → `triggerClaim()` → виплата USDC з децентралізованого пулу ліквідності Etherisc. Це запобігає інфляційному тиску на внутрішню токеноміку (Internal-mode натомість капить інфляцію через `ReserveGate` ↑). **[ARCH.45]** `triggerClaim` НЕ idempotent на нашому боці → orphaned `:pending` recovery-tx ескалює в `manual_review` (не сліпий re-claim) проти double-pay ([`04_02 §4`](04_02_Business_Logic_and_Services)).

**Guard clauses перед виплатою:**
- `required_confirmations` (default: 3) незалежних D-MRV підтверджень (Trigger-1 oracle-consensus).
- `ParametricInsurance.status = :active` (ще не тригернуто раніше).
- **[INS.1] Незалежне підтвердження (Trigger-2):** `InsurancePayoutWorker#awaiting_independent_confirmation?` — payout лише за verified Trigger-2 (fire — dClimate FIRMS-супутник; посуха/шкідник — Field-Audit/DAO, супутникового drought/pest-оракула немає → `:inconclusive`, ніколи `rejected_fraud`, [`05_05 §4`](05_05_Slashing_and_Risk_Policy)); без нього → hold (basis-risk guard).
- **[INS.1] No-data guard:** активні дерева Є, нуль AiInsight (катастрофа знищила сенсори) → `escalate_no_data_field_audit!` (Field Audit), а НЕ тихий `damage_ratio = 0` («не карати жертву», [`05_05 §6`](05_05_Slashing_and_Risk_Policy)).
- Майстер-прапор `:parametric_insurance_oracle_enabled` (kill-switch, default off → інертно до DAO/founder-активації).

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

**Дія:** Залучення юридичного консультанта (бажано з досвідом Web3 / ReFi) для підготовки шаблонів. **Академічний шлях вирішення:** СЄУ (Аблязов Денис Едуардович, к.ю.н., віцепрезидент СЄУ — господарське/комерційне право) — розробка шаблонів MSA, Term Sheet та Carbon Credit Purchase Agreement згідно з **українським господарським правом** (його фах); EU/MiCA-складова → профільний крипто/IP-юрист TBD. Детально: [`07_03 §1.5`](07_03_Academic_Integration_and_IP).

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

**Дія:** ⚖️ вибір KYC-провайдера (Sumsub / Veriff / Polygon Hadron) + юрисдикції (AMLD5/BSA/FATF) = рішення у [`00_07`](00_07_Action_Plan_Tracker) BIZ.20 (entity+KYC-counterparty) та BIZ.11 (Hadron KYC-flow) — не окремий item. Консультація compliance + **академічний шлях:** СЄУ (Аблязов Денис Едуардович) — **UA-правова** рамка KYC/AML для B2B клієнтів; EU-складова (ERC-3643 / AMLD5 / FATF) → профільний крипто-юрист TBD; облік KYC-витрат — СЄУ (Гедз М.Й., фінансовий облік криптоактивів). Детально: [`07_03 §1.5`](07_03_Academic_Integration_and_IP).

---

### Відсутній B2B Fiat-to-Retirement шлях (SPV-міст) [нот.19]

**Статус:** Не специфіковано. Блокує масовий B2B-онбординг (BIZ.15).

Корпорації з ESG-зобов'язаннями **не триматимуть крипту** на балансі й не керуватимуть Polygon-гаманцями/ключами заради ретайрменту. Поточний шлях ([`05_03`](05_03_Tokenomics_SCC_and_SFC) `KlimaRetirementWorker` → on-chain `retire()`) припускає, що клієнт уже володіє SCC on-chain. Бракує **Fiat-to-Retirement SPV** — інструмента, де корпорація платить фіат, а юр-особа-оператор (SPV) купує+ретайрить SCC від її імені й видає сертифікат офсету (ISO 14064-сумісний; **voluntary Scope 1-3 / net-zero** — добровільна ESG-звітність, НЕ regulatory-compliance-інструмент):

- Юрисдикція SPV + ліцензія на роботу з вуглецевими активами; хто кастодіан крипти.
- Bridge фіат → купівля SCC → `esg_retired_balance` (незворотно) → сертифікат.
- Audit-trail ретайрменту (Filecoin immutable archive — нот.18) для регуляторного звіту.

**Дія:** юридична рамка SPV — СЄУ (Аблязов Д., UA господарське право; MiCA/EU-складова → крипто-юрист TBD) + облік — СЄУ (Гедз М.Й., фінансовий облік криптоактивів). Cross-ref [`07_03 §1.5`](07_03_Academic_Integration_and_IP).

---


### Відсутній DAO Governance процес для SFC

**Статус:** SFC контракт code-complete (ще не задеплоєно), механізм голосування — не визначено.

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
> 1. **UA-юрисдикція:** Аблязов Д.Е. (СЄУ, персонально) + профільний крипто/IP-юрист TBD — меморандум «Юридична допустимість токенізації UA-лісу через ERC-3643» (cross-ref [`07_03 §4`](07_03_Academic_Integration_and_IP)). Перевіряє сумісність з Лісовим Кодексом України та Законом «Про природно-заповідний фонд».
> 2. **EU/MiCA:** Аблязов Д.Е. (СЄУ) — правова рамка ERC-3643 / MiCA для лісових RWA ([`07_03 §1.5`](07_03_Academic_Integration_and_IP)).
> 3. **Пілотна реєстрація:** одна ділянка Черкаського бору / ПЗФ за двостороннім меморандумом ЧНУ + СЄУ.

---

### SFC Voting Power зберігається після Slashing (Security Attack Vector)

**Статус:** 🟡 ЧАСТКОВО ВИРІШЕНО — `SilkenForestCoin.sol` реалізує `SLASHER_ROLE` + `slash()`. Голосування токени SFC тепер зменшуються при slashing (ERC20Votes `_update` → `_transferVotingUnits` → checkpoint update). Атака через купівлю SFC + навмисне порушення NaaS більше неможлива.

**Залишковий ризик — ширший, ніж стояло тут раніше** (звірено з кодом 2026-07-26): SFC-slash **не має бекенд-автоматизації взагалі**. Жоден Ruby-воркер чи сервіс не викликає `SilkenForestCoin.slash()`/`slashUpTo()` (перевірено по `app/`/`lib/`/`config/`), і сам контракт це фіксує коментарем «Manual DAO/Timelock-шлях — без бекенд-інтенту» ([`05_03`](05_03_Tokenomics_SCC_and_SFC)). Тому вікно, у якому вже-слешнутий за SCC учасник зберігає **повну** voting power, — це **не «~1–5 хв черги `web3_critical`»** (той опис припускав автоматизацію, якої немає), а проміжок **до ручного DAO/Timelock-втручання**, тобто за конструкцією необмежений. Vote Escrow (veToken) для `breached`-контрактів лишається **рекомендованим** доп-захистом; він інертний до живого DAO → [`00_07`](00_07_Action_Plan_Tracker) BIZ.14.

При порушенні NaaS контракту спрацьовує Slashing Protocol:
1. `BurnCarbonTokensWorker` → `BlockchainBurningService` → `SilkenCarbonCoin.slash(investor, amount)` — SCC зловмисника **спалюються**.
2. ✅ `SilkenForestCoin.sol` **має `SLASHER_ROLE`** та `slash()` функцію — реалізовано в `[B-06]`.
3. Результат: зловмисник **втрачає voting power** пропорційно обсягу slash.

**Поточний стан коду** (`contracts/SilkenForestCoin.sol`):
```solidity
bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");
function slash(address investor, uint256 amount) external onlyRole(SLASHER_ROLE) nonReentrant { ... }
```

**Дія:** Vote Escrow — опціональне покращення для повного DAO governance launch.

---

### Відсутня Customer-Facing Availability-SLA (BIZ.18)

**Статус:** Internal SLO є ([`06_08 §2.4`](06_08_Resilience_and_Failover_Policy) mint≥80%/intake≥95%, [`06_06 §3`](06_06_Disaster_Recovery_and_Backup) RTO/RPO), зовнішній customer-facing SLA — ні.

Специфікація артефакту: визначений uptime-% + service-credits + incident-comms + публічний status-page, на який B2B-покупець кредитів (Азот/agri) послатиметься в MSA (SLA = типовий exhibit BIZ.2). NB: ≠ `§2` «Таблиця SLA» (legal-event→tx, інше значення).

**Дія:** availability-target з перших live-SLO-вікон → SLA-exhibit. Статус трекається BIZ.18.

---

### Відсутнє Company-Level E&O / Liability-Страхування (BIZ.21)

**Статус:** INS.1 (параметричне) + DAO Treasury Pool за дизайном страхують КЛІЄНТА від деградації лісу (механіка inert — kill-switch off); professional-liability самого SilkenNet/founder — відсутня.

Специфікація артефакту: E&O/general-liability coverage (D-MRV-accuracy dispute · anchor-install injury третьої особи · carbon-credit-claim dispute); Certificate of Insurance = signing-exhibit B2B-MSA-due-diligence. Юрисдикція = UA (operational-vehicle, BIZ.20-присуд 2026-07-24).

**Дія:** coverage-spec → брокер+поліс. Гейт BIZ.2 signing. Статус трекається BIZ.21.

---

### Продукт описаний мовою інвестиційного договору (BIZ.22)

**Статус:** 🔴 відкрито — гейтить перший live-mint і Web3 mainnet.

Звірка **як-збудовано** (не наративу, а самого коду й вітрини) показала, що NaaS-продукт послідовно описаний мовою інвестиції, хоча так не проєктувався: роль користувача за замовчуванням названа інвесторською, сума платежу трактується як «інвестиція» з формулами штрафу за достроковий вихід і пропорційного повернення, є метод із «дохідністю» в назві, 5% кожного платежу йдуть у спільний пул, а ціна токена плаваюча на DEX. Жодна з механік окремо не є фінансовим інструментом — але **разом вони читаються не так, як задумано**, і та сама мова доти жила у відрендереній вітрині (UI-локалі, маніфест), тобто в комунікації до набувача.

**Що з цього випливає для §07:**
- Продаване — це **вимірювана D-MRV-послуга**; SCC = атестація обсягу наданої послуги (§1), а не інструмент із дохідністю. Формулювання «Що входить у послугу» в §1 — наслідок саме цього присуду.
- Юрисдикція-шопінг security-shaped transaction **не лікує** — консультація передує будь-якому вибору структури ([`07_03 §4.2`](07_03_Academic_Integration_and_IP)).
- **Вікно відкрите:** емісій не було, контракти не задеплоєні → виправлення до першого mint'а кратно дешевше за ретроактивне.

**Дія:** консультація профільного crypto/securities-юриста на as-built fact-pattern → продуктовий присуд → вирівнювання коду й канону. Повний перелік ознак, питання до юриста й статус — [`00_07`](00_07_Action_Plan_Tracker) BIZ.22 (+ канал UNI.16); токен-специфіка — [`05_03`](05_03_Tokenomics_SCC_and_SFC).

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
| `GET` | `/api/v1/contracts` | Required | Перелік NaaS контрактів клієнта (Pagy) |
| `GET` | `/api/v1/contracts/:id` | Required | Деталі контракту |
| `GET` | `/api/v1/contracts/stats` | Required | `total_contracted`, `tokens_minted`, `cluster_health`, `attested_value_usd` |

---

## 📌 Висновки (Summary)

| Аспект | Поточний стан |
|---|---|
| **Бізнес-логіка (код)** | ✅ Реалізована: lifecycle, slashing, early exit. Insurance-механіка (oracle/payout) є, але **INERT** — kill-switch off, без prod creation-path полісів |
| **On-chain механіка** | 🟡 Контракти **code-complete + CI-audited** (Slither/Aderyn/Halmos/Medusa), але **ще НЕ задеплоєно** — placeholder-адреси ([`05_03`](05_03_Tokenomics_SCC_and_SFC)); deploy gated на SEC.1 (Safe/Timelock) + BIZ.22 (securities-присуд) |
| **D-MRV підкріплення** | peaq DID + IoTeX ZK + The Graph (живі); Chainlink oracle PATH 1 = **latent** (unwired local-marker, ARCH.53) |
| **B2B продажі** | 🔴 Заблоковано: MSA, SLA, KYC відсутні |
| **B2C онбординг** | 🔴 Заблоковано: ToS, Privacy Policy відсутні |
| **CO₂ методологія** | ✅ 2000 SCC = 1 tCO₂ (1 SCC = 0.5 kg CO₂) — on-chain + SystemParameter. **Внутрішня облікова конвенція**, НЕ registry-визнаний кредит (§3) |
| **DAO Governance** | 🟡 SFC slash() реалізовано; Vote Escrow — опціонально |
| **RWA реєстрація** | 🟡 Інфраструктура є, процес не відпрацьований |
| **DB schema** | ✅ Узгоджено (`signed_at` прибрано з коду) |
