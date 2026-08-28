# 00_04: Контракти Nature-as-a-Service (Юридичний та Бізнес-Шар)

## 🎯 Мета

Зафіксувати бізнес-логіку та юридичні параметри моделі Nature-as-a-Service (NaaS): хто є клієнтами, що входить у послугу, як юридичні події відображаються у викликах смарт-контрактів (`mint`, `slash`) і які правові документи наразі відсутні. ⊕ **Вартісний бік винесено назад 2026-08-22** (DOC-T.83): BOM, CAPEX/OPEX і модель окупності живуть у [`02_06`](02_06_Unit_Economics_and_BOM), поруч із залізом, яке вони рахують. Ця сторінка відповідає «**за яким договором**», сусідня — «**за скільки**»; злиття 2026-08-10 тримало обидві відповіді в одному тілі, і за три місяці вони так і не зрослись.

---

## ✅ Статус

- **Стан:** Бізнес-логіка зафіксована в SSOT; юридичні документи відсутні. Шкала готовності тут **незастосовна** — предмет договірна, а не технологічна зрілість ([`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond), DOC-T.70)
- **Відкрите:** юридичні/compliance артефакти (MSA, KYC/AML, DAO governance, RWA реєстрація) → [`00_07`](00_07_Action_Plan_Tracker) (BIZ.*).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `app/models/naas_contract.rb` | NaasContract lifecycle (AASM) — SSOT коду |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | SCC/SFC + фінансові константи (home) |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Proof of Growth (мінтинг-тригер) |
| [`02_06` — Unit Economics and BOM](02_06_Unit_Economics_and_BOM) | Юніт-економіка, BOM, CAPEX/OPEX — друга половина питання клієнта |
| [`00_02` — Academic Institutions Registry](00_02_Academic_Integration_and_IP) | MSA / KYC legal (Аблязов) |
| [`02_01` — Hardware Architecture and BOM](02_01_Hardware_Architecture_and_BOM) | Апаратна архітектура (BOM source для [`02_06 §1`](02_06_Unit_Economics_and_BOM)) |
| [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) | Шлюз Королева (Queen BOM → [`02_06 §4`](02_06_Unit_Economics_and_BOM)) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | §07 юр/бізнес-дім — родина `BIZ.*` (винятки, чий дім деінде: BIZ.17 → [`00_04`](00_04_Nature_as_a_Service_Contracts); BIZ.13 → [`05_05`](05_05_Slashing_and_Risk_Policy)) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Реєстр Типів Контрактів (Contract Type Registry)](#-1-реєстр-типів-контрактів-contract-type-registry)
- [2. Таблиця SLA: Юридична Подія → On-Chain Транзакція](#-2-таблиця-sla-юридична-подія--on-chain-транзакція)
- [3. Фінансові Константи (Financial Constants)](#-3-фінансові-константи-financial-constants)
- [4. Життєвий Цикл NaaS Контракту](#-4-життєвий-цикл-naas-контракту)
- [5. Структура Даних (Data Model)](#-5-структура-даних-data-model)
- [6. Ієрархія Ролей та Доступу](#-6-ієрархія-ролей-та-доступу)
- [7. Параметричне Страхування (Insurance Layer)](#-7-параметричне-страхування-insurance-layer)
- [8. Юридичні та бізнес-передумови (дім стану — трекер BIZ.*)](#-8-юридичні-та-бізнес-передумови-дім-стану--трекер-biz)
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
- Параметричне страхування кластера (`ParametricInsurance`) від `critical_fire` та `extreme_drought`.
- Корпоративний ESG-звіт з можливістю ретайрменту SCC через KlimaDAO.
- **(Roadmap, ADR [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM))** Гіперлокальні мікрокліматичні дані (t°/RH/тиск/VPD з BME280) — data-as-a-service для агрохолдингів і страховиків: 1000+ датчиків *усередині* екосистеми проти усереднених метеостанцій на 50 км². Окреме джерело доходу поза SCC; має кількісно вимірювати біопреципітацію.
- **(Roadmap, deferred SLA-фасети)** Predictive tree-fall як SLA-підписка — конкретні дерева, що впадуть під вітром (`z_value` + гіро-аналіз стовбура, [`03_04`](03_04_mruby_Lorenz_Attractor)) для енерго-ЛЕП / автотрас+залізниці (Service-of-Roads) / муніципальних парків (позови за аварійні стовбури) + захист берегозахисних лісосмуг Дніпра + оптимізація міського поливу за `delta_t` гідратації ксилеми (економія бюджету). SLA-дім → §2.

**Умови входу:**
- KYC/KYB верифікація через Polygon Hadron Identity Platform (ERC-3643). Поле `hadron_kyc_status = 'approved'` на `Wallet` є обов'язковою guard clause перед будь-яким мінтингом SCC.
- `total_funding > 0` (валідація моделі).
- `start_date < end_date`.

**Страхова премія (Hybrid Protocol Gaia):**
При активації контракту 5% від `total_funding` направляється до DAO Treasury Parametric Insurance Pool (константа `NaasContract::INSURANCE_PREMIUM_RATE = BigDecimal("0.05")`). Залишок 95% — `forester_share_amount` — **обчислюється** як частка форестера, але диспенс-шляху ще немає (метод не має жодного call-site поза власною спекою) → [`05_05 §3.1`](05_05_Slashing_and_Risk_Policy).

**Поточний стан:** Бізнес-логіка реалізована в коді. Юридичного шаблону угоди (Term Sheet, Master Service Agreement) — немає → відкрите [`00_07`](00_07_Action_Plan_Tracker) BIZ.2 (B2B MSA).

---

### 1.2 B2C Individual — Підписка Власника Дерева

**Хто:** Приватні власники лісових ділянок, фізичні особи, які хочуть монетизувати або захистити свій ліс.

> ⚖️ **Присуд 2026-07-30 — навіть ОДИНОКЕ дерево дістає власний кластер (із одного дерева), а не «кластер відсутній».** Це не адміністративна умовність: `cluster_id` є HKDF-salt для `K_ota`/`KEYB`, тож без нього юніт **не пройде фабричне прошивання взагалі**. Два наслідки, обидва несучі саме для B2C. (1) Контракт укладається на кластер (`naas_contracts.cluster_id` — `NOT NULL`), тож однодеревний кластер — єдина форма, у якій B2C-договір узагалі виражається. (2) 🔴 **Слешинг при N=1 не спрацьовує автоматично:** відсотковий поріг вироджується (`N × 0.2 < 1` — одне дерево перетинає його механічно), тому нижче межі `N < 1/slash_fraction` вердикт — Field Audit, ніколи авто-burn. Приватний власник не втрачає баланс від однієї посушливої доби на єдиному сенсорі, але й без нагляду не лишається. Механіка → [`05_05 §7`](05_05_Slashing_and_Risk_Policy).

**Що входить у послугу:**
- Моніторинг здоров'я власних дерев (Soldier-вузли).
- SCC токени на свій `Wallet` (курс — [`05_03`](05_03_Tokenomics_SCC_and_SFC)).
- Мікро-нагороди у USDC на Solana (0.01–0.0162 USDC за кожен LoRa пакет телеметрії — формула-дім [`04_02`](04_02_Business_Logic_and_Services)).
- Celo ReFi нагороди (5 cUSD за здоровий кластер на добу) — якщо кластер проходить щоденний аудит.
- **(Roadmap, deferred B2C) Eco-Therapy 4.0** — цифрова лісотерапія: користувач біля дерева відкриває додаток → бачить «пульс» (`delta_t`) → синхронізація з природними ритмами. Перший у світі інструмент цифрової лісотерапії (напр. реабілітація ветеранів з ПТСД).

**Умови входу:**
- Стандартна автентифікація (Argon2id).
- Роль `User.role = :subscriber` або `User.role = :forester`.
- `Wallet` автоматично створюється при реєстрації Tree-вузла.

**Поточний стан:** Бекенд-інфраструктура (онбординг / Wallet / rewards) готова; on-chain SCC-мінт gated на деплой контрактів (SEC.1) + securities-присуд (BIZ.22). Публічного B2C онбординг-флоу (лендинг, ToS, Privacy Policy) — немає → відкрите [`00_07`](00_07_Action_Plan_Tracker) BIZ.3 (B2C ToS/Privacy).

---

### 1.3 DAO Agreement — Децентралізоване Управління

**Хто:** Власники SilkenForestCoin (SFC) — токену управління DAO.

**Що дає SFC:**
- Право голосу у протокольних рішеннях (зміна параметрів слешингу, схвалення нових кластерів).
- SFC мінтується за ті ж самі кластери, що генерують SCC, але через окремий виклик `SilkenForestCoin.mint(to, amount, clusterId, archiveRoot)` з `MINTER_ROLE`. 🔴 **ОБІЦЯНКА, А НЕ ОПИС — код цього не робить** (виміряно 2026-08-26): `Wallet#lock_and_mint!` дефолтить `token_type: :carbon_coin`, і його ЄДИНИЙ живий викликач третього аргумента не передає, тож емісії SFC за ріст не існує; єдиний живий writer `forest_coin` — страхова виплата. ⚠️ Сигнатуру теж виправлено: аргументів ЧОТИРИ, не три. Правила емісії SFC (курс, бенефіціар, стеля голосів) не визначені ніде — осі присуду в [`00_07`](00_07_Action_Plan_Tracker) DOC-T.89.

**Умови входу:**
- Участь у верифікованій екосистемі (SCC-адреса на Polygon).
- Gasless approvals через EIP-2612 (`ERC20Permit`).

**Поточний стан:** SFC смарт-контракт code-complete + CI-audited, **ще НЕ задеплоєно** (placeholder-адреса до mainnet, [`05_03`](05_03_Tokenomics_SCC_and_SFC)). DAO Governance процес (Snapshot / Governor) — не визначений → механіка [`05_06`](05_06_Governance_and_DAO); юр-оформлення DAO → [`00_07`](00_07_Action_Plan_Tracker) BIZ.*.

---

## 📋 2. Таблиця SLA: Юридична Подія → On-Chain Транзакція

| Юридична Подія | D-MRV Тригер | Rails Worker | Смарт-Контракт | Функція | Наслідок |
|---|---|---|---|---|---|
| **Послуга надана** (дерево здорове, Z в межах норми) | `growth_points` ≥ 0, `stress_index < 0.83` ⚠️ **DAO-керований поточний дефолт**, не фіксована умова | `TokenomicsEvaluatorWorker` (щогодинний cron) → `EvaluateTreeBatchWorker` → `Wallet#lock_and_mint!` → `BlockchainMintingService` (`telemetry_log: nil` для Path 2) | `SilkenCarbonCoin.sol` | `mint(to, amount, treeDid, archiveRoot)` / `batchMint` | Клієнт отримує SCC на `Wallet.crypto_public_address`. **Guards (Path 2 — tokenomics aggregate):** `hadron_kyc_status = "approved"` (єдиний обов'язковий perimeter); `verified_by_iotex?` / `oracle_status` свідомо пропускаються — `growth_points` вже зараховані через AES-256-CBC decrypt + `valid_sensor_data?` у `TelemetryUnpackerService` (per-packet integrity). Альтернативний Path 1 (oracle-driven per-telemetry mint) — **латентний**: `ChainlinkDispatchWorker` dispatch = local-marker без RPC, callback unwired ([`00_07` ARCH.53](00_07_Action_Plan_Tracker)); живий мінт-шлях = Path 2 (вище). Cross-ref: [`05_02 §Усі Шляхи до lock_and_mint! [DOC.7]`](05_02_Proof_of_Growth_Pipeline). |
| **Пакетна емісія** (ціла лісова ділянка) | Batch з ≤100 дерев | `MintCarbonCoinWorker` (Gas Saving Mode) | `SilkenCarbonCoin.sol` | `batchMint(recipients[], amounts[], treeDids[], archiveRoot)` | Масова емісія для всього кластера |
| **Дерево під стресом** (`stress_index ≥ 0.83` — **DAO-керований дефолт**) | AiInsight.stress_index | `ClusterHealthCheckWorker` | — | Облік у D-MRV арбітражі | Якщо >20% кластера — тригер слешингу |
| **Порушення контракту** (>20% дерев, ЩО ЗАСВІДЧИЛИ) | `critical_insights_count > witnessing_trees / 5` — 🔴 [SLASH-1, ⚖️ 2026-08-26] знаменник більше НЕ «всі активні»: мовчазне дерево не подає `AiInsight`, тож у чисельник потрапити не може, а в знаменнику стояло — тобто мовчання рахувалось свідченням про виживання й розбавляло шкоду. **Для клієнта умова стала СТРОГІШОЮ, і це названо тут явно**, бо йшлося про контрактну подію; ⛔ але тиша сама по собі й далі НІКОЛИ не карає (мовчазне дерево лише перестає бути доказом здоров'я), а нижче межі виродження вироку немає взагалі — Field Audit ([`05_05 §7`](05_05_Slashing_and_Risk_Policy)) | `ClusterHealthCheckWorker` (тригериться через `InsightBatchCallbacks#on_success` — коли всі `GenerateClusterInsightWorker` за добу зелені) → `BurnCarbonTokensWorker` | `SilkenCarbonCoin.sol` | `slash(investor, amount)` (gated) | [SLASH-1] **positive-A gate** ([`05_05 §3.2`](05_05_Slashing_and_Risk_Policy)): прямий доказ Кат-A (`vandalism_breach` — єдиний A-сигнал у коді; авто-writer'а немає → ручна C→A ескалація, на практиці freeze-first) → SCC спалюються + `status = :breached`; інакше (вкл. `chainsaw_detected` — реальна пилка, але поза A-сетом) → `:frozen` + Field-Audit `EwsAlert` (no burn, контракт лишається активним до C→A класифікації) |
| **Відсутність даних** (cluster-wide blackout — Starlink/шлюз) | `AiInsight.empty?` для кластера | `ContractHealthCheckService#flag_data_blackout!` | — (no on-chain дія) | `EwsAlert(:field_audit)` | **Force-majeure-сигнатура** (вкрадений/знищений шлюз, блекаут) → Field Audit (Category C), **НЕ** slash — карати лісника за збитий шлюз = false slash ([`05_05 §6`](05_05_Slashing_and_Risk_Policy)) |
| **Дерево згоріло** (`critical_fire`) | `EwsAlert` `fire_detected` — термальний поріг `temperature_c ≥ fire_limit` (`AlertDispatchService`, біом-адаптивний) | `EcosystemHealingWorker` → `InsurancePayoutWorker` | `SilkenCarbonCoin.sol` або Etherisc DIP | `mint(to, payout)` або `triggerClaim()` | Параметричне страхування активується |
| **Посуха** (`extreme_drought`) | `EwsAlert` `severe_drought` — wire-статус stress АБО вихід за per-family Z-смугу (`AlertDispatchService`) | `InsurancePayoutWorker` | `SilkenCarbonCoin.sol` або Etherisc DIP | `mint(to, payout)` або `triggerClaim()` | Параметрична виплата |
| **Дострокове розірвання** (Early Exit клієнта) | `ContractTerminationService.call(contract)` | Sync (API call) | `SilkenCarbonCoin.sol` | `slash(investor, burned_points)` (якщо `burn_accrued_points = true`; `contractual: true` — пропускає positive-A gate, бо це погоджена форфейтура, не slash-за-провину) | `NaasContract.status = :cancelled`, повернення з вирахуванням штрафу |
| **Успішне завершення** (контракт закінчився) | `NaasContract.pending_completion` + аудит | `ClusterHealthCheckWorker` → `fulfill!` | — | — | `NaasContract.status = :fulfilled`, звіт в Filecoin |
| **Смерть дерева** (біологічна) | `Tree.status = :deceased`, MaintenanceRecord | `EcosystemHealingWorker` (смерть) → **`MaintenanceRecord#attest!`** → `PuroEarthPassportWorker` — заявку подає незалежний ПІДПИС, не зцілення ([E.20] ⚖️ 2026-08-24) | Puro.earth (`PuroEarthPassportWorker` ✅ код; on-chain post-TRL 7) | D-MRV Biomass Passport | Biochar CORC генерація на Puro.earth |
| **ESG Ретайрмент** | `KlimaRetirementWorker` | `KlimaRetirementWorker` → `KlimaDao::RetirementService` | KlimaDAO (Polygon) | `approve()` + `retire()` | SCC перено до `esg_retired_balance` (незворотно) |
| **Щотижнева фіналізація** | Cron (понеділок 03:00 UTC) | `EthereumAnchorWorker` | Ethereum L1 | `anchorStateRoot(bytes32)` | State Root → Ethereum Mainnet |

> **[INS.1] Insurance-перили потребують НЕЗАЛЕЖНОГО Trigger-2 — не платяться напряму.** Рядки «Дерево згоріло / Посуха» — це ЛЕГАЛЬНИЙ наслідок; механічно виплата йде лише за **dual-trigger** (Trigger-1 AI-кандидат + Trigger-2 незалежне підтвердження, [`05_05 §4`](05_05_Slashing_and_Risk_Policy)). Реальний Trigger-2 існує ЛИШЕ для **пожежі** (dClimate FIRMS-супутник); **посуха супутникового оракула НЕ має** → `Dclimate::VerificationService` ескалює її у `:inconclusive`/**Field-Audit** (Кат-C, ніколи `rejected_fraud`/slash), доки не з'явиться реальне drought-джерело (👤 [`00_07` INS.1/S3.2/UNI.12](00_07_Action_Plan_Tracker)).

---

## 💰 3. Фінансові Константи (Financial Constants)

| Параметр | Значення | Джерело |
|---|---|---|
| **Конверсія: growth_points → SCC** | 10,000 growth_points = 1 SCC | [`05_03`](05_03_Tokenomics_SCC_and_SFC), `TokenomicsEvaluatorWorker` |
| **Денне накопичення** | **Calibration-pending** (`delta_t` recharge-каденція + GP-магнітуда = placeholder, чекають bench-кривої, [E.63](00_07_Action_Plan_Tracker)). Self-consistent realistic (Variant C, `delta_t`≈1.77 год [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)): ~13.6 пакети/добу × ~16 stored GP = **~217 growth_points/добу → ~8 SCC/дерево/рік**. Магнітуда = f(EBFC recharge): швидший `delta_t` → вище (фіз. стеля Δt=600s ≈ 326 SCC/рік; 1 TX/год = energy-negative без мітигацій). wire 5–31 × [FW.29] ×2 | [`05_03`](05_03_Tokenomics_SCC_and_SFC), [`02_06 §7.1`](02_06_Unit_Economics_and_BOM), [`02_03 §9`](02_03_BQ25570_MPPT_Nano_Power) |
| **Поріг емісії** | `Wallet.available_balance >= 10,000` (NET — сконвертоване лишається в `locked_balance`, [ARCH.94]) | `TokenomicsEvaluatorWorker` |
| **Страхова премія** | 5% від `total_funding` → DAO Treasury Pool | `NaasContract::INSURANCE_PREMIUM_RATE = BigDecimal("0.05")` |
| **Частка форестера** | 95% від `total_funding` — обчислюється, не диспенситься ([`05_05 §3.1`](05_05_Slashing_and_Risk_Policy)) | `NaasContract#forester_share_amount` |
| **Celo ReFi нагорода** | 5 cUSD / здоровий кластер / добу | `CeloRewardWorker`, `Celo::CommunityRewardService` |
| **Solana мікро-нагорода** | 0.01–0.0162 USDC / LoRa пакет (10 000 + GP×100 lamports; stored GP ≤ 62 = wire 5-bit ×2) | `SolanaMicroRewardWorker`, `Solana::MintingService`; формула-дім [`04_02`](04_02_Business_Logic_and_Services) |
| **Штраф за дострокове розірвання** | `total_funding × early_exit_fee_percent / 100` | `NaasContract#calculate_early_exit_fee` |
| **Пропорційне повернення** | `total_funding × (remaining_days / total_days) − fee` | `NaasContract#calculate_prorated_refund` |
| **Поріг слешингу** | >20% дерев, ЩО ЗАСВІДЧИЛИ за добу, з `stress_index >= 0.83` — **поточний дефолт, DAO-керований**: `SystemParameter.current(:stress_threshold, default: 0.83)` ← `ProtocolParameters.sol` (bounds 0.65..1.0, [GOV.1]). ⚠️ Значення змінюється голосуванням, тож у MSA/SLA його НЕ можна подавати як зафіксовану контрактну умову — або цитуй як «поточний дефолт», або фіксуй КОНТРАКТНУ стелю окремо від протокольної | `ContractHealthCheckService` |
| **1 SCC = X кг CO₂** | ✅ **2000 SCC = 1 tCO₂ (1 SCC = 0.5 kg CO₂)** — `SystemParameter.current(:scc_per_tonne_co2, default: 2000)`, `ProtocolParameters.sol#sccPerTonneCo2()`. **Внутрішня облікова конвенція** Proof-of-Growth (Condition-прочитання — [`02_06 §7`](02_06_Unit_Economics_and_BOM)), НЕ registry-визнаний tCO₂e-кредит: продаваний кредит лише через незалежну методологію (BIZ.9); трек = MRV-Data-Provider/permanence-monitor | [BIZ.1] |
| **1 SCC = $Y (контрактна вартість)** | ⚠️ **Не зафіксовано, і курсу протокол не тримає ВЗАГАЛІ** — ні читача ціни, ні governance-параметра fallback-ціни: система міряє КІЛЬКІСТЬ (SCC), вартість множить сам споживач. Єдине місце, де долар за SCC узагалі фігурує, — sensitivity-крива payback-моделі [`02_06 §7.3`](02_06_Unit_Economics_and_BOM) ($0.15…$5.00), і це **вхід сценарію, а не курс системи**: цитувати її як ціну — помилка жанру. ⛔ Не заводь «тимчасовий» курс у сіди/`ProtocolParameters` заради одного екрана: ключ без читача = ручка, якою нікому крутити (гейт ARCH.104). Ціна повернення механізму названа чесно — це читання DEX-quoter'а (+ кеш і мітка при мовчанні), не архітектура; тригер — перший реальний споживач ціни (Tier A / registry-канал) | — (нема реалізації за призначенням) |

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
(ClusterHealthCheck        (critical_fire, drought)
 Worker via
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

> **Значення тут — дзеркало SSOT, правити в [`04_01`](04_01_Data_Models_and_Entities).** Нижче лише ті поля, що несуть БІЗНЕС-семантику NaaS; повний набір колонок (включно з lineage-курсором `lineage_cursor_at`/`lineage_cursor_log_id` [MRV.1], якого тут свідомо немає — він про мінт-вікно, не про контракт) живе в домі моделей.

### NaasContract (таблиця `naas_contracts`)

| Поле | Тип | Опис |
|---|---|---|
| `organization_id` | bigint FK | Організація-клієнт |
| `cluster_id` | bigint FK | Лісовий кластер під захистом |
| `total_funding` | numeric | Загальна сума оплати за послугу (USDC/USD) |
| `start_date` | timestamp | Дата початку контракту |
| `end_date` | timestamp | Дата закінчення контракту |
| `status` | integer (enum) | `draft(0)`, `active(1)`, `fulfilled(2)`, `breached(3)`, `cancelled(4)` |
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
| `trigger_event` | integer (enum) | `critical_fire(0)`, `extreme_drought(1)` |
| `payout_amount` | numeric | Сума виплати |
| `threshold_value` | numeric | Поріг для тригера (% аномальних дерев) |
| `token_type` | integer (default: 0) | Тип токена виплати — **лише SCC** (`carbon_coin`); SFC знято з енуму присудом DOC-T.89, ціле `1` зарезервоване |
| `required_confirmations` | integer (default: 3) | Мін. підтверджень D-MRV перед виплатою |
| `paid_at` | timestamp | Час виплати |
| `etherisc_policy_id` | varchar | ID Etherisc DIP policy (режим Oracle, виплата в USDC) |

---

## 🔑 6. Ієрархія Ролей та Доступу

Застосункові ролі та їхній скоуп даних — дім [`04_03 §3`](04_03_REST_API_v1_Reference) (RBAC) + [`04_03 §3.1`](04_03_REST_API_v1_Reference) (acting-organization). Тут лише те, що несуче для NaaS: **скоуп даних відв'язано від ролі** — у контексті ОДНІЄЇ організації за раз працюють усі, включно з `super_admin`, який її лише перемикає. `NaasContractPolicy` не має super_admin-гілки взагалі: і `show?`, і `Scope` стоять на одній умові приналежності організації.

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

1. **Internal mode (default):** `InsurancePayoutWorker` → `BlockchainMintingService` → **SCC**-емісія на Polygon (SFC не мінтиться взагалі — присуд DOC-T.89; поліс у типі SFC відтепер невиразний структурно). **[INS.2]** Ця емісія **інфляційна** (мінтить новий SCC, не бере з пулу) → перед mint `Insurance::ReserveGate` накладає systemic stop-loss: (1) aggregate 24h correlated-event cap + (2) reserve-adequacy (30d Internal-mint vs `DAO_TREASURY`-баланс × ratio). Обидва пороги **inert-default** (`SystemParameter` 0 = off; калібрування = 👤 economic-політика → [`00_07` INS.2](00_07_Action_Plan_Tracker)). Breach → HOLD у `manual_review` (не незабезпечений mint); transient RPC → Sidekiq-retry (fail-closed, без permanent park). Etherisc-виплати з cap виключено (зовнішній USDC, не наша емісія).
2. **Oracle mode (Etherisc DIP):** Якщо `etherisc_policy_id` присутній, система переключається в режим Oracle: `Etherisc::ClaimService` → `triggerClaim()` → виплата USDC з децентралізованого пулу ліквідності Etherisc. Це запобігає інфляційному тиску на внутрішню токеноміку (Internal-mode натомість капить інфляцію через `ReserveGate` ↑). **[ARCH.45]** `triggerClaim` НЕ idempotent на нашому боці → orphaned `:pending` recovery-tx ескалює в `manual_review` (не сліпий re-claim) проти double-pay ([`04_02 §4`](04_02_Business_Logic_and_Services)).

**Guard clauses перед виплатою:**
- `required_confirmations` (default: 3) незалежних D-MRV підтверджень (Trigger-1 oracle-consensus).
- `ParametricInsurance.status = :active` (ще не тригернуто раніше).
- **[INS.1] Незалежне підтвердження (Trigger-2):** `InsurancePayoutWorker#awaiting_independent_confirmation?` — payout лише за verified Trigger-2 **власного перилу поліса** (fire — dClimate FIRMS-супутник; посуха — Field-Audit/DAO, супутникового drought-оракула немає → `:inconclusive`, ніколи `rejected_fraud`, [`05_05 §4`](05_05_Slashing_and_Risk_Policy)); без нього → hold (basis-risk guard). ⚠️ Практичний наслідок для клієнта, який варто називати в умовах: поліс від посухи сьогодні **не має шляху до авто-виплати** — його рухає лише людський Field-Audit, доки не приземлиться реальне drought-джерело.
- **[INS.1] No-data guard:** активні дерева Є, нуль AiInsight (катастрофа знищила сенсори) → `escalate_no_data_field_audit!` (Field Audit), а НЕ тихий `damage_ratio = 0` («не карати жертву», [`05_05 §6`](05_05_Slashing_and_Risk_Policy)).
- Майстер-прапор `:parametric_insurance_oracle_enabled` (kill-switch, default off → інертно до DAO/founder-активації).

---

## ⚖️ 8. Юридичні та бізнес-передумови (дім стану — трекер BIZ.*)

> **Ця секція більше не специфікує передумови — вона на них ВКАЗУЄ** (DOC-T.68 фаза 5, 2026-08-10). Тут стояло 146 рядків (30% дока), і звірка блок-за-блоком показала, що **кожен із десяти вже має пункт у трекері, причому багатший**: трекер несе не лише «чого бракує», а й стан артефакту, виконавця, гейти й ратифіковані присуди. Дублювання коштувало дорожче за навігацію — сторінка почала розходитись із власним трекером (див. 🔴 нижче).

| Передумова | Дім стану |
|---|---|
| B2B MSA + SLA + Subscription Order Form (каркас — [`msa_skeleton.md`](protocols/legal/msa_skeleton.md)) | [`00_07`](00_07_Action_Plan_Tracker) BIZ.2 |
| B2C ToS / Privacy / Cookie (чернетки — [`b2c_tos_privacy.md`](protocols/legal/b2c_tos_privacy.md)); чи адресуємо CCPA/CPRA | [`00_07`](00_07_Action_Plan_Tracker) BIZ.3 |
| Машинна інтеграційна поверхня для Клієнта (OpenAPI-контракт · org-scoped outbound-webhooks). ⚠️ Канон її НЕ обіцяє: [`00_01 §8`](00_01_Vision_Mission_and_Roadmap) тримає production API-доступ серед **УТРИМУВАНИХ** активів — а чернетковий шар уже продає «Tier A (Dashboard + API)» | [`00_07`](00_07_Action_Plan_Tracker) ARCH.63 |
| KYC/AML-процес для B2B (регуляторний шар поверх `hadron_kyc_status`) | [`00_07`](00_07_Action_Plan_Tracker) BIZ.20 |
| B2B Fiat-to-Retirement SPV (юрисдикція · ліцензія · кастодіан · сертифікат-флоу) | [`00_07`](00_07_Action_Plan_Tracker) BIZ.15 |
| Юр-оболонка DAO (LLC / Swiss Verein / Wyoming DUNA) — механіка вже в [`05_06`](05_06_Governance_and_DAO) | [`00_07`](00_07_Action_Plan_Tracker) BIZ.20 |
| Реєстрація лісової ділянки як RWA (партнер-лісокористувач · кадастр · biomass appraisal) | [`00_07`](00_07_Action_Plan_Tracker) BIZ.11 |
| SFC vote-escrow у вікні breach→slash | [`00_07`](00_07_Action_Plan_Tracker) BIZ.14 |
| Customer-facing availability-SLA (≠ `§2` — та таблиця про юр-подію→tx) | [`00_07`](00_07_Action_Plan_Tracker) BIZ.18 |
| Company-level E&O / liability (≠ INS.1 — той страхує КЛІЄНТА) | [`00_07`](00_07_Action_Plan_Tracker) BIZ.21 |
| Продукт описаний мовою інвестдоговору — securities fact-pattern | [`00_07`](00_07_Action_Plan_Tracker) BIZ.22 |

🔴 **Чому дублювання тут було небезпечнішим за звичайний drift, і це доказ, а не побоювання.** Дві заяви цієї секції встигли розійтися з трекером у бік, який шкодить: (1) вона називала підставою RWA-пілоту «двосторонній меморандум ЧНУ + СЄУ» — документ, що не підписаний, не планується і не міг би дати прав на ділянку ПЗФ, бо обидві сторони є ВНЗ, а не розпорядниками лісу; (2) вона оцінювала вікно vote-escrow у «1–5 хв», тоді як звірка з кодом показала, що бекенд-автоматизації SFC-slash **не існує взагалі**, тобто вікно невизначене. Обидві виправлені у своїх домах. **Правило, куплене цим:** сторінка, що специфікує ВІДКРИТЕ, застаріває швидше за сторінку, що описує ЗБУДОВАНЕ, — тож відкрите живе в трекері, а канон на нього вказує.

---

## 🔗 9. Міжланцюгові Залежності (Cross-Module Dependencies)

```
[05_03 Tokenomics] ──── СИНХРОНІЗОВАНО ────► [00_04 NaaS Contracts]
[§1-§7 NaaS Contracts] ── ЖИВЛЯТЬ ──► [02_06 Unit Economics & BOM]
[00_04 NaaS Contracts] ──── БЛОКУЄ ────► B2B Sales (onboarding)
[05_02 Proof of Growth] ──── ЗАБЕЗПЕЧУЄ ────► [00_04 NaaS Contracts]
```

---

## 📊 10. API Endpoints (Contracts Registry)

| Метод | URL | Авт. | Опис |
|---|---|---|---|
| `GET` | `/contracts` | Required | Перелік NaaS контрактів клієнта (Pagy) |
| `GET` | `/contracts/:id` | Required | Деталі контракту |
| `GET` | `/contracts/stats` | Required | `total_contracted`, `total_tokens_minted` (**чиста емісія орендаря**, Σmints − Σburns — ⚖️ [ARCH.103] зняв контрактну семантику; ніколи не `null`), `cluster_health` (шкала **0..1**, не відсоток — `health_index` = `1.0 - stress_index`; **nullable з [ARCH.84]**: `null` = не виміряно, і це НЕ те саме, що виміряний `0.0`), `clusters_measured` + `clusters_total` (покриття — без них середнє по одному кластеру читалось би як твердження про весь фонд), `attested_value_usd` |

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
| **DAO Governance** | 🟡 SFC `slash()`/`slashUpTo()` реалізовано, але кличе їх **лише ручний DAO/Timelock** (бекенд-автоматизації немає) → vote-power-вікно необмежене; Vote Escrow — **рекомендований** доп-захист (§8) |
| **RWA реєстрація** | 🟡 Інфраструктура є, процес не відпрацьований |
| **DB schema** | ✅ Узгоджено (`signed_at` прибрано з коду) |

---
