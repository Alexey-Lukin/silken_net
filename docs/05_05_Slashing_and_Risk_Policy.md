# 05_05: Slashing & Risk Policy — Політика Штрафів і Ризиків

## 🎯 Мета

Канонічний дім **політики Slashing & Risk**: класифікація причини деградації (**халатність** vs **форс-мажор** vs **невизначеність**), прогресивна формула штрафу (категорія A), параметричне страхування (категорія B), DAO peer-review (категорія C), anti-fraud cross-checks і multi-signal de-risk-інваріант. Документ описує **політику й принципи**; механіка реалізації живе у своїх домах і **реферується** звідси: контрактна — `05_03`, pipeline-детекція — `05_02`/`04_02`, страхування — `07_01`, governance — `05_06`.

> **Чому окремий документ.** Slashing — це **risk/penalty-шар**, концептуально окремий від emission-токеноміки (`05_03`). До 2026-05-30 політика жила в `00_01 §6` (візійна сторінка) і була розпорошена по `05_03`/`07_01`/`05_02`/`04_02` з прихованими дублями. Консолідовано сюди як один SSOT-дім (`00_06 §2`).

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — політика затверджена; backend-механіка реалізована частково (convex-формула `BlockchainBurningService#calculate_slash_ratio` + blackout-routing `ContractHealthCheckService#flag_data_blackout!`, RSpec-покрито). **Відкрите:** formal `cause_classification` A/B/C-gate (SLASH-1), operator-bond (BIZ.13), DAO-confirm перед mainnet → [00_07](00_07_Action_Plan_Tracker).
- **Slashing v2:** жорстке "burn-on-degradation" замінено двокатегорійною моделлю (негілентність / форс-мажор) + safety-default (невизначеність) — травень 2026.
- **De-risk інваріант:** фінансовий slashing **ніколи** не спирається лише на Z-Лоренца — потрібен ≥1 прямий некорельований сигнал (sap_flow / VPD / acoustic).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [00_01_Vision_Mission_and_Roadmap](00_01_Vision_Mission_and_Roadmap) | Vision-рівень: місія, NaaS, філософія negligence-vs-force-majeure |
| [05_02_Proof_of_Growth_Pipeline](05_02_Proof_of_Growth_Pipeline) | Anti-fraud DCI (`SEC.11`, `check_z_divergence!`); `stress_index` pipeline |
| [05_03_Tokenomics_SCC_and_SFC](05_03_Tokenomics_SCC_and_SFC) | `slash()` контракт; Dynamic Tax (insurance-pool funding); `ProtocolParameters` (GAMMA, PENALTY_FACTOR_MAX) |
| [05_06_Governance_and_DAO](05_06_Governance_and_DAO) | DAO peer-review (категорія C): `SilkenGovernor`/`SilkenTimelock`/quorum |
| [07_01_Nature_as_a_Service_Contracts](07_01_Nature_as_a_Service_Contracts) | Insurance Layer mechanics (Etherisc, два режими); NaaS breach terms; SFC voting after slash |
| [04_02_Business_Logic_and_Services](04_02_Business_Logic_and_Services) | `BlockchainBurningService`, `ContractHealthCheckService`, `InsightGeneratorService#stress_index`; divergence registry §11 |
| [08_02_Academic_Institutions_Registry](08_02_Academic_Institutions_Registry) | Партнерський ростер ФОТІУС/ЧНУ + академічний вихід для ground-truth протоколу (сам протокол — §8) |
| [00_07_Action_Plan_Tracker](00_07_Action_Plan_Tracker) | **Відкрите** (SSOT): SLASH-1 cause-gate, BIZ.13 operator-bond |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Філософія — Negligence vs Force Majeure](#-1-філософія--negligence-vs-force-majeure)
- [2. Категоризація причини деградації](#2-категоризація-причини-деградації)
- [3. Slashing формула (тільки для категорії A)](#3-slashing-формула-тільки-для-категорії-a)
- [4. Insurance Payout (тільки для категорії B)](#4-insurance-payout-тільки-для-категорії-b)
- [5. Indeterminate (категорія C) — DAO Peer Review](#5-indeterminate-категорія-c--dao-peer-review)
- [6. Anti-fraud cross-checks](#6-anti-fraud-cross-checks)
- [7. Multi-signal slashing — Лоренц ≠ єдина правда](#7-multi-signal-slashing--лоренц--єдина-правда-lorenz-de-risk)
- [8. Ground-Truth Validation Protocol — Z↔health](#-8-ground-truth-validation-protocol--zhealth-lorenz-de-risk)
<!-- TOC:AUTO:END -->

---

## 🔒 1. Філософія — Negligence vs Force Majeure

У попередній редакції правило формулювалося як `if cluster_degradation > 20% then burn(tokens)`. Це порушує базовий принцип криптоекономіки: slashing — це **покарання за зловмисність або халатність**, а не за статистично невідворотну подію. Якщо ліс згорів від блискавки, спалювання токенів інвесторів виглядає як покарання жертви та руйнує мотивацію інвесторів брати реальні географічні ризики. Тому ми ділимо причини деградації на категорії.

## 2. Категоризація причини деградації

Кожен інцидент `cluster.degradation_event` отримує `cause_classification` (визначається `InsightGeneratorService` + Chainlink DON cross-check + DAO override):

| Категорія | Приклади | Прокся-сигнал | Реакція |
|-----------|----------|---------------|---------|
| **A. Negligence / Operator fault** | Несанкціонована вирубка, незаконний випас, відсутність протипожежної смуги після алерту, неприєднання Forester'а до інциденту в SLA, втручання у hardware (tamper) | Acoustic: chainsaw class, `vandalized` scope, відсутність MaintenanceRecord після P0 alert | **Slashing активний** — спалюється за прогресивною кривою `damage_ratio^GAMMA × penalty_factor` (до 100% при повній загибелі; §3) |
| **B. Force Majeure / Acts of Nature** | Блискавка, лісова пожежа природного походження, землетрус, екстремальна посуха (`dClimate ≥ severe`), повінь, ураган, біопатоген | Кореляція з dClimate / NASA FIRMS / параметричні тригери; **відсутність ознак людської активності** в acoustic feed | **Slashing вимкнено** — кошти **заморожуються** у `wallet.locked_balance`, активується `InsurancePayoutWorker` через Etherisc (§4) |
| **C. Indeterminate (default safety)** | Дані недостатні для класифікації (втрата зв'язку, перерване покриття, мала вибірка) | `oracle_status_failed` для класифікаційного callback'а | **Заморозка без спалювання** — DAO голосує `peer-review` upgrade до A або B (§5, вікно 30 днів) |

## 3. Slashing формула (тільки для категорії A)

> **⚠️ Прибрано «безкоштовну недбалість».** Стара формула `min(damage_ratio × penalty_factor, max_slash_ratio=0.40)` мала critical incentive-bug — жорстка стеля min() створювала **мертву зону**: при `penalty_factor=1.5` уже `damage_ratio ≥ 0.27` дає `0.405 → clamp 0.40`. Тобто загибель 27% лісу = 40% slash, але й загибель **80% чи 100%** = **теж лише 40%** — після порогу ліснику фінансово байдуже, що буде з рештою лісу (нульовий маржинальний стимул берегти ліс).

```
slash_ratio  = clamp( damage_ratio^GAMMA × min(penalty_factor, PENALTY_FACTOR_MAX), 0, 1.0 )
slash_amount = locked_balance × slash_ratio

damage_ratio       = (stressed_trees + dead_trees) / total_trees_in_cluster   ∈ [0,1]
GAMMA              = 1.3   # прогресивна (опукла) крива: м'яко на дрібних помилках,
                          # без мертвої зони, монотонно → 1.0 при повній загибелі
penalty_factor     = 1.0  (negligence baseline)
                   + 0.5  (EwsAlert severity=critical 30+ хв без MaintenanceRecord)
                   + 0.5  (AuditLog: відсутність acknowledged alert'ів)
PENALTY_FACTOR_MAX = 2.0   # стеля застосовується до МНОЖНИКА (penalty_factor),
                          # а НЕ до фінального slash_ratio (DAO-governed)
# max_slash_ratio ВИДАЛЕНО — стеля на фінальному результаті і була джерелом мертвої зони
```

**Властивості кривої** (GAMMA=1.3, баланс «захист дрібних помилок ↔ нема стелі»):
- дрібна помилка `d=0.10, pf=1.0` → ~5% slash (інвестор захищений від катастрофи через дрібницю);
- `d=0.27, pf=1.5` → ~28% (порівнянно зі старим, але без обриву);
- **повна недбала загибель `d=1.0, pf=1.0` → 100% slash** (мертва зона ліквідована).

Монотонність гарантована: більше шкоди → завжди більший slash, аж до 100%. **Логістична крива тут гірша** за опуклу степеневу — логіста сатурує нижче 1.0 (асимптота), тобто повертає м'яку стелю, і має зайві параметри (k, d₀). Точне калібрування `GAMMA` / `PENALTY_FACTOR_MAX` — DAO-governed через `ProtocolParameters` ([`05_03 §Slashing`](05_03_Tokenomics_SCC_and_SFC)).

> Реалізація: `BlockchainBurningService#calculate_slash_ratio` (див. [`04_02 §BlockchainBurningService`](04_02_Business_Logic_and_Services)) перевіряє `cause_classification` перед викликом `slash()` на SCC-контракті ([`05_03`](05_03_Tokenomics_SCC_and_SFC)). Якщо `cause_classification != "A_negligence"` — burn skipped, тільки `freeze_balance!`.

### 3.1 Principal-Agent resolution [BIZ.13] — рекомендація: hybrid operator-bond

Категорія A **за визначенням** operator-attributable (chainsaw, відсутність firebreak після алерту, Forester не приєднався до SLA, tamper). Тож зрізати **інвесторський** `locked_balance` за провину **оператора** — principal-agent помилка: (1) moral hazard — оператор без skin-in-the-game; (2) інвестор тікає від гео-ризику.

| Модель | + | − |
|--------|---|---|
| **Investor-slash (статус-кво)** | проста; нуль нової механіки | principal-agent порушено; оператор без stake; інвестор демотивований |
| **Pure operator-bond** | оператор має skin-in-game; інвестор захищений | капітальний барʼєр для Forester (особливо post-war UA); sizing; Sybil |
| **Hybrid (рекомендовано)** | bond-first вирівнює оператора + інвестор захищений від рутинної недбалості, експонований лише до катастрофічного excess | трохи складніша механіка |

**Рекомендація: hybrid, attribution-driven.** Для категорії A спершу слешиться **operator-bond** (до розміру bond), і лише надлишок (катастрофа > bond) ескалює на інвесторський `locked_balance`. Категорія B — без змін (insurance). Формула §3 застосовується послідовно: **bond first, then locked_balance**.

**Операційні застереження:**
- **Bond sizing** — DAO-параметр у `ProtocolParameters` (напр. `bond = max(BOND_FLOOR, k × expected_cluster_reward)`).
- **Капітальний барʼєр (post-war UA foresters):** bond фінансується з накопичених PoPhW-винагород (E.20 Forester Guild) — *earned-bond*, не upfront; добра історія → менший bond (reputation-scaled).
- **Sybil:** KYC-gated (Hadron) + per-operator + geo-staking.

**🤖 Реалізація після DAO-confirm:** `OperatorBond` модель + `ProtocolParameters` (bond_size, bond_first) + `BlockchainBurningService` (слеш bond перед `locked_balance` для A) + контракт-escrow. Tracked → [`00_07` BIZ.13/SLASH-1](00_07_Action_Plan_Tracker).

## 4. Insurance Payout (тільки для категорії B)

```
ForceMajeure event → InsurancePayoutWorker
  → Etherisc::ClaimService.dispatch(policy_id, claim_amount: damage_ratio × insured_value)
  → Polygon → smart contract payout до wallet.balance
  → AuditLog action="insurance.payout.force_majeure"
```

- Параметричні тригери: `dClimate.fire_detected ≥ FRP 10MW`, `dClimate.drought_index ≥ severe`, `NOAA earthquake ≥ M6 within 10km`.
- Cap: `insurance_pool` ≥ 100,000 SCC підтримується через **Dynamic Tax** (2% від кожного `batchMint`, якщо pool < threshold) — механіка [`05_03 §Dynamic Tax`](05_03_Tokenomics_SCC_and_SFC).
- Mechanics виплати (Internal mode vs Etherisc Oracle mode, guard clauses, `ParametricInsurance`) — дім [`07_01 §7 Insurance Layer`](07_01_Nature_as_a_Service_Contracts).

## 5. Indeterminate (категорія C) — DAO Peer Review

- Кошти заморожені у `wallet.locked_balance`.
- DAO ставить пропозицію `Codex(): cluster_X_event_Y → upgrade_to(A | B)` через `SilkenGovernor` (механіка governance — [`05_06 Governance & DAO`](05_06_Governance_and_DAO)).
- Quorum: 4% SFC voting power (стандарт `GovernorVotesQuorumFraction`), затримка 48 годин у `SilkenTimelock`.
- Після затвердження пропозиції — застосовується відповідна реакція (slash або insurance payout).
- **Якщо DAO не голосує протягом 30 днів — кошти ЗАЛИШАЮТЬСЯ замороженими**, статус кластера → `Field Audit Required`. Розморозка/виплата відбувається ЛИШЕ за підтвердженими даними (фізична інспекція рейнджером або підтверджена телеметрія після відновлення зв'язку).

  > **⚠️ Прибрано авто-розморозку по таймауту.** Попереднє «no vote → auto-unfreeze» було вектором атаки: зловмисник/недбалий оператор міг навмисно глушити LoRa чи екранувати анкери, перетворюючи явний фрод (A) на «брак даних» (C), і просто чекати 30 днів — при мільйонах дерев voter fatigue гарантує, що DAO не встигне розглянути всі кейси, і кошти порушника звільнились би автоматично. Презумпція невинуватості ≠ авто-розблокування за відсутності телеметрії.
  >
  > **Додатковий захист на етапі класифікації:** раптове «going dark» (втрата зв'язку / глушіння / екранування) **одразу після P0-алерту** саме по собі є tamper-індикатором → інцидент іде в категорію **A**, а не C. Це закриває атаку «перетворити A на C» біля джерела.
  >
  > **Phase scope:** для Phase 2 (Regional) достатньо простого статусу `Field Audit Required` (ручна інспекція). On-chain Bounty-ринок для рейнджерів/дронів (EXIF-верифікація, anti-GPS-spoofing) — окремий великий пласт, відкладено до **Phase 3 (Planetary Scale)**; план — [`08_02 §3` Forester Guild Fallback Oracle](08_02_Academic_Institutions_Registry).

  > **Escape з deadlock (нот.11):** «вічна заморозка» — свідомий вибір (краще заморожено, ніж авто-release фроду по таймауту). Для **чесного** кластера є два виходи, тож це не глухий кут інвестора: (1) **відновлення зв'язку** → підтверджена телеметрія авто-розморожує (вище); (2) **будь-яка сторона** (інвестор-беніфіціар, forester, DAO-делегат) може **ініціювати** `Field Audit Required` — а не лише пасивно чекати голосування DAO. Незворотний deadlock вимагає ОДНОЧАСНО: постійної втрати зв'язку + відмови всіх сторін від інспекції — і саме цей залишок автоматизує Phase-3 bounty-ринок.

## 6. Anti-fraud cross-checks

Перед класифікацією `cause_classification`:

- **Hardware tamper detection** (`HardwareKey.tamper_detected_at`) — якщо встановлено: автоматично категорія A, незалежно від dClimate.
- **Dual computation integrity divergence** ([`05_02 §SEC.11 Dual Computation Integrity`](05_02_Proof_of_Growth_Pipeline)) — **НЕ є самостійним тригером спалювання.**

  > **⚠️ Уточнення:** Поширена помилка — вважати, що розбіжність Z «математично неминуча» через хаос Лоренца + різні FPU (Float32 ARM vs backend). Це було б правдою лише до [FW.7]. Зараз backend рахує Z у **Float64 (IEEE 754), бітово ідентично** firmware mruby (`8.0/3.0`, верифіковано 50 000 parity-тестами) — НЕ BigDecimal. Тому в чесній роботі divergence ≈ 0 за тих самих входів, і велика divergence є **реальним сигналом тамперу** (девайс рапортує Z, несумісний із заявленими входами), а не «шумом флоат-округлення».
  >
  > **Але** через дві причини divergence сам по собі НЕ повинен запускати незворотне спалювання: (1) **LoRa-канал наразі AES-128-ECB без MIC.** ⚠️ Хибно пояснювати це як «bit-flip пакету → хибна divergence»: ECB має **avalanche-ефект** — переворот одного біта шифротексту спотворює **весь 16-байтний блок** на decrypt, тож `vcap`/`temp`/`delta_t` стають сміттям і пакет відхиляється в `TelemetryUnpackerService.valid_sensor_data?` (vcap поза `0..5000` мВ або temp поза `-45..90` °C) **ще до** порівняння Z. Тому bit-flip майже ніколи не дає тихої Z-only divergence. Реальна незакрита загроза ECB-без-MIC — **whole-block replay/substitution**: повтор раніше захопленого «здорового» 16-байтного блоку (в ECB немає per-packet freshness), який `valid_sensor_data?` пропускає, а категоріальна `check_z_divergence!` бачить як узгоджені device-nibble↔server-Z. Саме replay, а не bit-flip, перемагає divergence-as-tamper; (2) розбіжність версій прошивки після OTA (інші Lorenz-константи) теж дає divergence. Тому: divergence — **сильний доказ** категорії A лише **у поєднанні** з другим сигналом (`HardwareKey.tamper_detected_at`, chainsaw-acoustic, або підтверджена версія FW). Самостійна divergence → категорія C (заморозка + peer-review / Field Audit), а не автоматичний burn.
  >
  > **🛡️ Post-FW.2 (AES-128-CCM):** причина (1) зникає повністю — MIC закриває bit-flip *і* підміну блоку, а Frame Counter закриває replay (канон режимів — [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security); backend `process_ccm_chunk` під `TELEMETRY_CCM_ENABLED`, реєстр divergence — [`04_02 §11`](04_02_Business_Logic_and_Services)). Лишиться тільки причина (2), що дає підставу переглянути, чи може divergence ескалювати самостійно, коли CCM активний.

- **Streamr P2P broadcast gap** довше 24 год без MaintenanceRecord — посилення penalty_factor на +0.25. **⚠️ Тільки tree-side (нот.12):** застосовується ЛИШЕ коли gap корелює з втратою tree-side зв'язку (LoRa/CoAP теж мовчать). **Backend-side збій Streamr-API** (дані дійшли до Rails, але `StreamrBroadcastWorker` не зміг ре-броадкаст → `streamr_undelivered` Kredis) — **НЕ** вина дерева → **0 penalty**. Streamr — публічний спостерігач (нот.3), доступність його API не є сигналом здоров'я дерева.
- **Correlated comms-loss guard [SLASH-SAFETY].** Сигнали втрати зв'язку **не є незалежними** і не повинні складатися: «немає ack» (+0.5), «Streamr gap» (+0.25) та «daily_insights порожні» мають **один root-cause** — недоступність вузла/шлюзу. **Одночасна втрата даних по ВСЬОМУ кластеру** (усі дерева «згасли» разом) — це сигнатура **відмови шлюзу / Starlink-блекауту** (force-majeure → B/insurance або C/peer-review), а НЕ per-tree недбалість (A). Класифікувати масовий blackout як A = карати лісника за збитий машиною / вкрадений шлюз. Той самий де-ризик-принцип, що VPD-confounder (`02_01 §3.4`) і Lorenz (§7): незворотний фінансовий вирок вимагає **прямого, некорельованого** підтвердження халатності.

  > **🟡 Code↔doc divergence (формула + blackout закрито):** (1) ✅ `BlockchainBurningService` палить за **§3 convex-кривою** `clamp(damage_ratio^GAMMA × min(pf, PENALTY_FACTOR_MAX), 0, 1)` (`#calculate_slash_ratio`; GAMMA=1.3/PF_MAX=2.0 DAO-governed через `SystemParameter` ← `ProtocolParameters.sol`), а **не лінійно**; (2) ✅ blackout більше НЕ палить — `ContractHealthCheckService#flag_data_blackout!` (cluster-wide empty → Field Audit, force-majeure, no burn). **Лишилось (🟡 → DAO/founder):** формальний `cause_classification` A/B/C-термін у коді ще відсутній + cause-driven `penalty_factor` uplift (Streamr gap/repeat) + signal de-correlation. → tracked: [`00_07` SLASH-1](00_07_Action_Plan_Tracker); реєстр divergence — [`04_02 §11`](04_02_Business_Logic_and_Services).

## 7. Multi-signal slashing — Лоренц ≠ єдина правда [Lorenz de-risk]

**Принцип:** фінансовий slashing **ніколи** не спирається лише на Z-Лоренца. Роль Лоренца подвійна й обмежена: (1) **DCI / anti-fraud** (`check_z_divergence!` — device-Z vs server-Z, §6); (2) **один із кількох** stress-features. Мапінг «Z → здоров'я дерева» сам по собі — **недоведена гіпотеза** (потребує ground-truth — протокол **§8** нижче).

**Стан (verified):**
- Драйвер slashing — `stress_index` (`ContractHealthCheckService`: tree ≥0.83 / cluster >20% дерев ≥1.0).
- `stress_index` (`InsightGeneratorService#calculate_stress_index`) — **мульти-сигнальний ML** на `[temp, vcap, Z, sap_deviation, acoustic]`. Z = 1 з 5; `sap_flow` (прямий фізіологічний) — окрема ознака. ✅ Архітектурно вже не «ставка лише на Z».
- ✅ **GAP closed (heuristic):** heuristic-fallback (`calculate_stress_index_heuristic`, активний доки ML-модель не натренована) тепер вмонтовує обидва прямі сигнали: **sap** (`sap_stress_contribution`, signed below-baseline) + **acoustic/cavitation** (`acoustic_stress_contribution` — count лише **стрес-класів** TinyML: cavitation/chainsaw, **НЕ** вітер (клас-1) чи тиша (клас-0); нот.13 — акустика категоріальна (клас 0-3), тож для ML вона one-hot, для евристики — клас-фільтр, а не лінійний count усіх подій) — обидва **inert доки калібрування не задасть** ENV (`STRESS_SAP_*` / `STRESS_ACOUSTIC_*`); кожен обмежений так, що **корелює, але не слешить сам** (status-0 ≈0.2 ≪ 0.83), а sap+acoustic беруться через **max(), не суму** (correlated drought — SLASH-SAFETY §6). Лишилось: **on-device TinyML-класифікація** (`Run_Inference` — firmware) + ground-truth калібрування порогів (протокол **§8**; lab-партнер `08_02 §4 Завдання В`). Деталі реалізації — [`04_02`](04_02_Business_Logic_and_Services).
- ML-модель потребує **ground-truth калібрування** перед mainnet slashing.

**Інваріант:** доки Z↔health не підтверджено емпірично, slashing вимагає підтвердження **≥1 прямим вимірним сигналом** (sap_flow / chainsaw-acoustic / dClimate), не лише Z/device-status.

**Прямі сигнали (corroboration set):** `sap_flow`/`delta_t` (метаболізм), chainsaw-acoustic (TinyML), dClimate (супутник), і **VPD з BME280** [ADR `02_01 §3.4`] (t°+RH): прямий фізіологічний confounder, що відрізняє падіння сокоруху через погоду (дощ/туман, RH≈100%) від хвороби. VPD — апаратне втілення цього інваріанта: вбиває False Slashing біля джерела. ⚠️ VPD живе на slashing/confounder-шарі, **НЕ** в Lorenz-Z (DCI-guard, `03_04`). Разом з «correlated comms-loss guard» (§6) це формує повний принцип: **не штрафувати за недоведений Z, за погоду, ані за втрату зв'язку** — лише за прямо підтверджену халатність.

## 🔬 8. Ground-Truth Validation Protocol — Z↔health [Lorenz de-risk]

**Проблема:** ланцюг Z-атрактор → `stress_index` → slashing **елегантний, але емпірично недоведений** (§7). Потрібен ground-truth, щоб (а) підтвердити/спростувати предиктивність Z, (б) калібрувати ML-`stress_index`, (в) безпечно виставити slashing-пороги (§3). Це закриває найбільший науковий ризик проєкту: без цього доказу bio-частина стоїть на гіпотезі.

**Дизайн** (польова валідація — ЧНУ біо-хаб + Data Science Карапетян + лабораторія Гусака; партнерський ростер і академічний вихід → [`08_02`](08_02_Academic_Institutions_Registry)):
- **Когорта:** 20–30 дерев (Черкаський бір), SilkenNet-анкер + **незалежний ground-truth**: еталонний sap-flow сенсор (незалежний від EBFC `delta_t`), дендрометр (приріст), періодичний NDVI/leaf-area, експертний бал стану + події смертності/хвороби.
- **Тривалість:** ≥1 вегетаційний сезон (захопити стрес-події: посуха, шкідники).
- **Збір:** щоденні `stress_index` + компоненти (`Z`, `sap_flow`, `acoustic`, `temp`, `vcap`, **`RH`/`VPD`** [BME280, [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM)]), `growth_points`, ground-truth.
- **Аналіз** (backend-харнес `SilkenNet::LorenzValidationService` — ✅ реалізовано, `app/services/silken_net/`, RSpec-покрито):
  1. Кореляція `stress_index` ↔ ground-truth decline (Spearman ρ).
  2. **Incremental value Z:** чи додає Z предиктивність ПОНАД прямі сигнали (sap_flow)? Якщо ні → демоут Z до **DCI-only**.
  3. Agreement device `bio_status` (Z-derived) vs експертний бал (Cohen's κ).
  4. ROC детекції стресу + false-positive rate (slashing-safety).
  5. **VPD-confounder:** частка sap_flow-drops, пояснених погодою (high VPD) vs хворобою — валідує False-Slashing guard (§6, BME280 `02_01 §3.4`).
- **Критерії приймання (proposed):** ρ(`stress_index`, decline) ≥ 0.6; Z дає incremental ΔAUC > 0.05 над sap_flow-baseline (інакше Z = лише DCI); FPR < 5% на операційному порозі.
- **Вихід:** калібровані ваги ML-`stress_index` + heuristic + slashing-пороги (DAO-tunable — [`00_07` BIZ.4](00_07_Action_Plan_Tracker)); рішення про роль Z (predictive vs DCI-only).

> **DCI лишається валідним незалежно.** Навіть якщо валідація демоутить Z до **DCI-only** (anti-fraud, §6), fraud-детекція не страждає — Лоренц-DCI не залежить від доведеності гіпотези «Z = здоров'я».
