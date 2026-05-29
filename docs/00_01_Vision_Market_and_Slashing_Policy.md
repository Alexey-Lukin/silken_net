# 00_01: Vision, Market Problem and Slashing Policy

## 🎯 Мета

Зафіксувати глобальну місію проєкту, проблеми ринку добровільних вуглецевих кредитів (VCM), бізнес-модель Nature-as-a-Service (NaaS) та — окремо — політику Slashing з чітким розмежуванням між **халатністю/недбалістю** (підлягає slashing) і **форс-мажором** (покривається параметричним страхуванням).

---

## ✅ Статус

- **Поточний TRL:** TRL 9 — Бізнес-візія та фази масштабування затверджені.
- **Pivot v3 (тризонний анкер):** Стара моноліт-«Матрьошка» переписана на тризонну архітектуру (анод-гіроїд у заболоні + PEEK-терморозрив + катодний фланець на межі кори/повітря) — деталі [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK). Усуває тепловий міст крізь титан, кисневе голодування катода і неможливий моноліт-друк Ti+PEEK.
- **Slashing v2 (травень 2026):** Жорстке "burn-on-degradation" правило з попередньої редакції замінено на **двокатегорійну модель** — окремо для людської недбалості та окремо для форс-мажору (див. §6).
- **Пов'язані модулі:**
  - 8-рівнева архітектура та конвеєр → [`00_02_System_Architecture_and_12_Chain_Pipeline`](00_02_System_Architecture_and_12_Chain_Pipeline)
  - Резервування, Failover та fallback Web3 → [`00_03_Resilience_and_Failover_Policy`](00_03_Resilience_and_Failover_Policy)
  - Стратегічна дорожня карта (TRL Matrix + HIL) → [`00_06_Strategic_Roadmap_and_HIL_Simulators`](00_06_Strategic_Roadmap_and_HIL_Simulators)
  - Мультичейн архітектура → [`05_01_Multichain_Architecture`](05_01_Multichain_Architecture)
  - Токеноміка SCC/SFC → [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC)
  - Бізнес-контракти NaaS → [`07_01_Nature_as_a_Service_Contracts`](07_01_Nature_as_a_Service_Contracts)
  - Юніт-економіка та BOM → [`07_02_Unit_Economics_and_BOM`](07_02_Unit_Economics_and_BOM)

---

## 🌍 1. Місія (The Mission)

> *"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."*

Мета **Gaia 2.0 (Silken Net)** — створити першу у світі trustless D-MRV (Digital Measurement, Reporting, and Verification) платформу. Ми замінюємо ручний, корумпований аудит вуглецевих кредитів на безперервний, автономний і криптографічно підтверджений моніторинг. Дерево перестає бути пасивним об'єктом екології і стає активним економічним агентом.

---

## 📉 2. Проблема Ринку (Market Opportunity)

Сучасний добровільний ринок вуглецевих кредитів (VCM — Voluntary Carbon Market, обсяг >$2B) зруйнований через 4 фундаментальні проблеми:

1. **Ручний аудит:** Дорого, повільно, високий фактор людської помилки.
2. **Подвійний облік (Double Counting):** Один і той самий ліс продається різним корпораціям.
3. **Ризик перманентності:** Ніхто не моніторить ліс після випуску кредитів (ліс може згоріти або бути вирубаним наступного дня).
4. **Фрод:** Намальовані ліси, завищені оцінки поглинання CO2 (Greenwashing).

**Рішення Silken Net:** Кожен токен SCC (Silken Carbon Coin) репрезентує реальне, верифіковане сенсорами, поточне поглинання вуглецю. Якщо дерево гине — система миттєво припиняє емісію.

---

## 🧬 3. Науковий Підхід (The Science)

Ми відмовилися від зовнішнього живлення та старих методів електрокінетики.

- **Живлення з метаболізму:** Тризонний коаксіальний анкер ([`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK)) — Ti-6Al-4V анод-гіроїд у заболоні з **деглікозильованою FAD-GDH** (Gen 2.0, не виробляє H₂O₂, не запускає CODIT) у захисній **Genipin-Chitosan-CNC** матриці з **Nafion-g-PSBMA** цвітеріонною мембраною + PEEK-терморозрив + Ti-катодний фланець на межі кори/повітря з **Laccase/ZIF-nanozyme** гібридом (×10 power density, chloride-tolerant) та PTFE-GDL мембраною для атмосферного O₂. Розщеплює глюкозу ксилемного соку, генеруючи >500 mV протягом 20–25 років.
- **Edge AI:** Зібрана енергія живить STM32WLE5JC, який через TinyML класифікує акустичні події (пилка, кавітація) та розраховує гомеостаз дерева через Атрактор Лоренца.
- **Криптографія:** Дані шифруються апаратним AES-128 (LoRa channel, post-ARCH.42; CoAP→Rails — AES-256) і відправляються через LoRa mesh у децентралізовану мережу, де перетворюються на ZK-proofs (IoTeX).

---

## 🚀 4. Дорожня Карта Масштабування (High-Level Roadmap)

> Детальна TRL Matrix і per-domain HIL-симулятори описані в [`00_06_Strategic_Roadmap_and_HIL_Simulators`](00_06_Strategic_Roadmap_and_HIL_Simulators).

### Phase 1: The First Breath (2025-2026) — R&D та Валідація

- **Лабораторний етап:** Партнерство з ЧНУ (TRL 1-4). Staged validation gate (`01_01` §6.1): Stage 1 (5 SLA-макетів для form & fit) → Stage 2 (10 Ti-«монет» 10×10 мм для in vitro біохімії Gen 2.0: dgrFAD-GDH + Os + Genipin-Chitosan-CNC + Nafion-g-PSBMA + Laccase/ZIF-nanozyme у синтетичному ксилемному соку) → Stage 3 (3–5 повноцінних SLM+HIP тризонних анкерів).
- **MVP Прототип:** Збірка капсули з BQ25570 та тестування "Нульового Лагу" (DMA Sleep).
- **Пілотний кластер:** Розгортання перших 100 вузлів у Холодному Яру (тільки після проходження Stages 1–3).
- **Web3 Інфраструктура:** Запуск тестової мережі (Testnet Polygon + peaq DID), відпрацювання ZK-proof верифікації.

### Phase 2: The Cyber-Physical State (2027-2028) — Регіональна Експансія

- **Масштаб:** 10+ кластерів по лісах України (тисячі дерев).
- **Mainnet:** Розгортання смарт-контрактів у Polygon Mainnet та якоріння в Ethereum L1.
- **Бізнес:** Підписання перших NaaS (Nature-as-a-Service) контрактів з інституційними інвесторами (інтеграція Hadron KYC).
- **Управління:** Запуск токена SFC (Silken Forest Coin) та активація DAO для управління параметрами емісії.
- **Інфраструктура:** Перехід на децентралізований хостинг Akash Network. Запуск мобільного додатку для лісників.

### Phase 3: Planetary Scale (2029-2030) — Глобальна Мережа

- **Масштаб:** Мільйони дерев. Міжнародні партнерства (Амазонія, Карпати, Північна Америка).
- **Зв'язок:** Повна інтеграція зі Starlink Direct-to-Cell для забезпечення Uplink'у з Королев у найвіддаленіших хащах планети.
- **База даних:** Створення найбільшої у світі мульти-видової бази калібрувань (TreeFamily Calibration Database) на базі Атрактора Лоренца.
- **Економіка:** Gaia 2.0 стає глобальним стандартом (Gold Standard) для ESG-звітності корпорацій.

---

## 🌿 5. Nature-as-a-Service (NaaS) — Бізнес-Модель

1. **Організації фінансують лісові кластери** через NaaS-контракти (`NaasContract`).
2. **Дерева заробляють growth points** через верифікований біологічний гомеостаз.
3. **Points конвертуються в SCC токени** на Polygon (10,000 points = 1 SCC). Кожен SCC підкріплений верифікованим поглинанням CO₂ — on-chain конверсія `ProtocolParameters.sol#sccPerTonneCo2()` (**2000 SCC = 1 верифікована тонна CO₂**, [`07_02`](07_02_Unit_Economics_and_BOM)). Ринкова ціна SCC визначається ліквідністю DEX та вуглецевими оракулами — у маніфесті фіатні суми НЕ фіксуються (вони застаріли б при русі ринку $10↔$100/т і виглядали б маніпулятивно).
4. **Інвестори отримують токени** пропорційно до результатів кластера.
5. **Деградація кластера** запускає **двокатегорійну реакцію** (див. §6): або slashing, або страхове відшкодування.
6. **Параметричне страхування** забезпечує автоматичні виплати при катастрофічних подіях, що виходять за рамки операторського контролю (форс-мажор).

Це створює економічний зворотний зв'язок: інвестори зацікавлені у здоров'ї лісу, а не лише у видачі вуглецевих кредитів.

---

## 🔒 6. Slashing Policy v2 — Negligence vs Force Majeure

> **Чому ця секція переписана.** У попередній редакції документа правило формулювалося як `if cluster_degradation > 20% then burn(tokens)`. Це порушує базовий принцип криптоекономіки: slashing — це **покарання за зловмисність або халатність**, а не за статистично невідворотну подію. Якщо ліс згорів від блискавки, спалювання токенів інвесторів виглядає як покарання жертви та руйнує мотивацію інвесторів брати реальні географічні ризики. Тому ми ділимо причини деградації на дві категорії.

### 6.1 Категоризація причини деградації

Кожен інцидент `cluster.degradation_event` отримує `cause_classification` (визначається `InsightGeneratorService` + Chainlink DON cross-check + DAO override):

| Категорія | Приклади | Прокся-сигнал | Реакція |
|-----------|----------|---------------|---------|
| **A. Negligence / Operator fault** | Несанкціонована вирубка, незаконний випас, відсутність протипожежної смуги після алерту, неприєднання Forester'а до інциденту в SLA, втручання у hardware (tamper) | Acoustic: chainsaw class, `vandalized` scope, відсутність MaintenanceRecord після P0 alert | **Slashing активний** — спалюється за прогресивною кривою `damage_ratio^GAMMA × penalty_factor` (до 100% при повній загибелі; §6.2) |
| **B. Force Majeure / Acts of Nature** | Блискавка, лісова пожежа природного походження, землетрус, екстремальна посуха (`dClimate ≥ severe`), повінь, ураган, біопатоген | Кореляція з dClimate / NASA FIRMS / параметричні тригери; **відсутність ознак людської активності** в acoustic feed | **Slashing вимкнено** — кошти **заморожуються** у `wallet.locked_balance`, активується `InsurancePayoutWorker` через Etherisc |
| **C. Indeterminate (default safety)** | Дані недостатні для класифікації (втрата зв'язку, перерване покриття, мала вибірка) | `oracle_status_failed` для класифікаційного callback'а | **Заморозка без спалювання** — DAO голосує `peer-review` upgrade до A або B (вікно 30 днів) |

### 6.2 Slashing формула (тільки для категорії A)

> **⚠️ Переписано (2026-05-28): прибрано «безкоштовну недбалість».** Стара формула `min(damage_ratio × penalty_factor, max_slash_ratio=0.40)` мала critical incentive-bug — жорстка стеля min() створювала **мертву зону**: при `penalty_factor=1.5` уже `damage_ratio ≥ 0.27` дає `0.405 → clamp 0.40`. Тобто загибель 27% лісу = 40% slash, але й загибель **80% чи 100%** = **теж лише 40%** — після порогу ліснику фінансово байдуже, що буде з рештою лісу (нульовий маржинальний стимул берегти ліс).

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

**Властивості нової кривої** (GAMMA=1.3, баланс «захист дрібних помилок ↔ нема стелі»):
- дрібна помилка `d=0.10, pf=1.0` → ~5% slash (інвестор захищений від катастрофи через дрібницю);
- `d=0.27, pf=1.5` → ~28% (порівнянно зі старим, але без обриву);
- **повна недбала загибель `d=1.0, pf=1.0` → 100% slash** (мертва зона ліквідована).

Монотонність гарантована: більше шкоди → завжди більший slash, аж до 100%. **Логістична крива тут гірша** за опуклу степеневу — логіста сатурує нижче 1.0 (асимптота), тобто повертає м'яку стелю, і має зайві параметри (k, d₀). Точне калібрування GAMMA / PENALTY_FACTOR_MAX — DAO-governed у [`05_03 §Slashing`](05_03_Tokenomics_SCC_and_SFC).

> **Принципал-агент (governance flag):** `locked_balance` належить **інвестору**, а недбалість зазвичай — провина **оператора (Forester)**. Чи коректно зрізати капітал інвестора за дії оператора (vs окремий operator-bond) — відкрите питання дизайну для [`05_03`](05_03_Tokenomics_SCC_and_SFC) / [`00_08` BIZ](00_08_Action_Plan_Tracker).

> Реалізація: `BlockchainBurningService` (див. §1.2 у [`04_02`](04_02_Business_Logic_and_Services)) перевіряє `cause_classification` перед викликом `slash()` на SCC контракті. Якщо `cause_classification != "A_negligence"` — burn skipped, тільки `freeze_balance!` через `Wallet.lock_and_mint!`.

#### 6.2.1 Principal-Agent resolution [BIZ.13] — рекомендація: hybrid operator-bond (confirm/adjust)

Категорія A **за визначенням** operator-attributable (chainsaw, відсутність firebreak після алерту, Forester не приєднався до SLA, tamper). Тож зрізати **інвесторський** `locked_balance` за провину **оператора** — principal-agent помилка: (1) moral hazard — оператор без skin-in-the-game; (2) інвестор тікає від гео-ризику.

| Модель | + | − |
|--------|---|---|
| **Investor-slash (статус-кво)** | проста; нуль нової механіки | principal-agent порушено; оператор без stake; інвестор демотивований |
| **Pure operator-bond** | оператор має skin-in-game; інвестор захищений | капітальний барʼєр для Forester (особливо post-war UA); sizing; Sybil |
| **Hybrid (рекомендовано)** | bond-first вирівнює оператора + інвестор захищений від рутинної недбалості, експонований лише до катастрофічного excess | трохи складніша механіка |

**Рекомендація: hybrid, attribution-driven.** Для категорії A спершу слешиться **operator-bond** (до розміру bond), і лише надлишок (катастрофа > bond) ескалює на інвесторський `locked_balance`. Категорія B — без змін (insurance). Формула §6.2 застосовується послідовно: **bond first, then locked_balance**.

**Операційні застереження:**
- **Bond sizing** — DAO-параметр у `ProtocolParameters` (напр. `bond = max(BOND_FLOOR, k × expected_cluster_reward)`).
- **Капітальний барʼєр (post-war UA foresters):** bond фінансується з накопичених PoPhW-винагород (E.20 Forester Guild) — *earned-bond*, не upfront; добра історія → менший bond (reputation-scaled).
- **Sybil:** KYC-gated (Hadron) + per-operator + geo-staking.

**🤖 Реалізація після DAO-confirm:** `OperatorBond` модель + `ProtocolParameters` (bond_size, bond_first) + `BlockchainBurningService` (слеш bond перед `locked_balance` для A) + контракт-escrow. Sync → `05_03 §Slashing`, `04_02 §1.2`.

### 6.3 Insurance Payout (тільки для категорії B)

```
ForceMajeure event → InsurancePayoutWorker
  → Etherisc::ClaimService.dispatch(policy_id, claim_amount: damage_ratio × insured_value)
  → Polygon → smart contract payout до wallet.balance
  → AuditLog action="insurance.payout.force_majeure"
```

- Параметричні тригери: `dClimate.fire_detected ≥ FRP 10MW`, `dClimate.drought_index ≥ severe`, `NOAA earthquake ≥ M6 within 10km`.
- Cap: `insurance_pool` ≥ 100,000 SCC підтримується через Dynamic Tax (2% від кожного мінту, якщо pool < threshold) — див. [`05_02`](05_02_Proof_of_Growth_Pipeline) §Dynamic Tax.

### 6.4 Indeterminate (категорія C) — DAO Peer Review

- Кошти заморожені у `wallet.locked_balance`.
- DAO ставить пропозицію `Codex(): cluster_X_event_Y → upgrade_to(A | B)` через `SilkenGovernor`.
- Quorum: 4% SFC voting power (стандарт `GovernorVotesQuorumFraction`), затримка 48 годин у `SilkenTimelock`.
- Після затвердження пропозиції — застосовується відповідна реакція (slash або insurance payout).
- **Якщо DAO не голосує протягом 30 днів — кошти ЗАЛИШАЮТЬСЯ замороженими**, статус кластера → `Field Audit Required`. Розморозка/виплата відбувається ЛИШЕ за підтвердженими даними (фізична інспекція рейнджером або підтверджена телеметрія після відновлення зв'язку).

  > **⚠️ Корекція exploit (2026-05-28): прибрано авто-розморозку по таймауту.** Попереднє «no vote → auto-unfreeze» було вектором атаки: зловмисник/недбалий оператор міг навмисно глушити LoRa чи екранувати анкери, перетворюючи явний фрод (A) на «брак даних» (C), і просто чекати 30 днів — при мільйонах дерев voter fatigue гарантує, що DAO не встигне розглянути всі кейси, і кошти порушника звільнились би автоматично. Презумпція невинуватості ≠ авто-розблокування за відсутності телеметрії.
  >
  > **Додатковий захист на етапі класифікації:** раптове «going dark» (втрата зв'язку / глушіння / екранування) **одразу після P0-алерту** саме по собі є tamper-індикатором → інцидент іде в категорію **A**, а не C. Це закриває атаку «перетворити A на C» біля джерела.
  >
  > **Phase scope:** для Phase 2 (Regional) достатньо простого статусу `Field Audit Required` (ручна інспекція). On-chain Bounty-ринок для рейнджерів/дронів (EXIF-верифікація, anti-GPS-spoofing) — окремий великий пласт, відкладено до **Phase 3 (Planetary Scale)**; план — [`08_05` Forester Guild Fallback Oracle](08_05_CHIPB_Fire_Safety_Integration).

### 6.5 Anti-fraud cross-checks

Перед класифікацією `cause_classification`:

- **Hardware tamper detection** (`HardwareKey.tamper_detected_at`) — якщо встановлено: автоматично категорія A, незалежно від dClimate.
- **Dual computation integrity divergence** ([`05_02 §Dual Computation Integrity`](05_02_Proof_of_Growth_Pipeline)) — **НЕ є самостійним тригером спалювання.**

  > **⚠️ Уточнення (2026-05-28):** Поширена помилка — вважати, що розбіжність Z «математично неминуча» через хаос Лоренца + різні FPU (Float32 ARM vs backend). Це було б правдою лише до [FW.7]. Зараз backend рахує Z у **Float64 (IEEE 754), бітово ідентично** firmware mruby (`8.0/3.0`, верифіковано 50 000 parity-тестами) — НЕ BigDecimal. Тому в чесній роботі divergence ≈ 0 за тих самих входів, і велика divergence є **реальним сигналом тамперу** (девайс рапортує Z, несумісний із заявленими входами), а не «шумом флоат-округлення».
  >
  > **Але** через дві причини divergence сам по собі НЕ повинен запускати незворотне спалювання: (1) LoRa-канал наразі AES-128-ECB **без MIC** → можливий bit-flip пакету (хибна divergence); (2) розбіжність версій прошивки після OTA (інші Lorenz-константи) теж дає divergence. Тому: divergence — **сильний доказ** категорії A лише **у поєднанні** з другим сигналом (`HardwareKey.tamper_detected_at`, chainsaw-acoustic, або підтверджена версія FW). Самостійна divergence → категорія C (заморозка + peer-review / Field Audit), а не автоматичний burn.

- **Streamr P2P broadcast gap** довше 24 год без MaintenanceRecord — посилення penalty_factor на +0.25.

### 6.6 Multi-signal slashing — Лоренц ≠ єдина правда [Lorenz de-risk, 2026-05-29]

**Принцип:** фінансовий slashing **ніколи** не спирається лише на Z-Лоренца. Роль Лоренца подвійна й обмежена: (1) **DCI / anti-fraud** (`check_z_divergence!` — device-Z vs server-Z, §6.5); (2) **один із кількох** stress-features. Мапінг «Z → здоров'я дерева» сам по собі — **недоведена гіпотеза** (потребує ground-truth — [`08_02` Lorenz↔health protocol](08_02_Cybernetic_and_Mathematical_Validation)).

**Стан (verified 2026-05-29):**
- Драйвер slashing — `stress_index` (`ContractHealthCheckService`: tree ≥0.83 / cluster >20% дерев ≥1.0).
- `stress_index` (`InsightGeneratorService#calculate_stress_index`) — **мульти-сигнальний ML** на `[temp, vcap, Z, sap_deviation, acoustic]`. Z = 1 з 5; `sap_flow` (прямий фізіологічний) — окрема ознака. ✅ Архітектурно вже не «ставка лише на Z».
- ⚠️ **GAP:** heuristic-fallback (`calculate_stress_index_heuristic`, активний доки ML-модель не натренована) спирається на `max_status` (device-Z-класифікація) + `avg_z` + temp — **ігнорує `sap_flow`/acoustic**. У no-model стані slashing де-факто спирається на недоведений Z. → **Fix:** heuristic мусить вимагати corroboration прямим сигналом перед high-stress (HW.19-аналог: не штрафувати без прямого підтвердження).
- ML-модель потребує **ground-truth калібрування** перед mainnet slashing.

**Інваріант:** доки Z↔health не підтверджено емпірично, slashing вимагає підтвердження **≥1 прямим вимірним сигналом** (sap_flow / chainsaw-acoustic / dClimate), не лише Z/device-status.

---

## 🔒 7. "Proof of Growth" Консенсус

На відміну від Proof of Work (витрата енергії) або Proof of Stake (концентрація капіталу), Proof of Growth прив'язує емісію токенів до верифікованих біологічних процесів:

- Кожен SCC токен підкріплений сенсорно-верифікованим фотосинтезом та поглинанням вуглецю.
- On-device обчислення (mruby) запобігає підробці на рівні заліза.
- Server-side верифікація (Ruby Float64, IEEE 754 — бітово ідентично firmware після [FW.7]) забезпечує redundant integrity checking.
- Slashing protocol (§6) гарантує економічні наслідки за деградацію через халатність, **не караючи** інвесторів за форс-мажор.

---

## 🔗 8. Cross-ref

- `docs/05_03 §Slashing` — конкретні параметри `ProtocolParameters` registry (`GAMMA` progress-curve, `PENALTY_FACTOR_MAX`, `penalty_factor_base`).
- `docs/07_01 §Insurance Pool & Etherisc` — операційні деталі парам. страхування.
- `docs/00_03 §Web3 Fallback` — як Slashing/Insurance продовжує працювати при недоступності окремих мостів.
- `docs/00_08 BIZ section` — open business questions та DAO governance backlog.
