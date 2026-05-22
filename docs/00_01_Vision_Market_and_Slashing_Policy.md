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
- **Криптографія:** Дані підписуються апаратним AES-256 і відправляються через LoRa mesh у децентралізовану мережу, де перетворюються на ZK-proofs (IoTeX).

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
3. **Points конвертуються в SCC токени** на Polygon (10,000 points = 1 SCC, ~$25.5).
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
| **A. Negligence / Operator fault** | Несанкціонована вирубка, незаконний випас, відсутність протипожежної смуги після алерту, неприєднання Forester'а до інциденту в SLA, втручання у hardware (tamper) | Acoustic: chainsaw class, `vandalized` scope, відсутність MaintenanceRecord після P0 alert | **Slashing активний** — спалюється до `max_slash_ratio` пропорційно `damage_ratio` |
| **B. Force Majeure / Acts of Nature** | Блискавка, лісова пожежа природного походження, землетрус, екстремальна посуха (`dClimate ≥ severe`), повінь, ураган, біопатоген | Кореляція з dClimate / NASA FIRMS / параметричні тригери; **відсутність ознак людської активності** в acoustic feed | **Slashing вимкнено** — кошти **заморожуються** у `wallet.locked_balance`, активується `InsurancePayoutWorker` через Etherisc |
| **C. Indeterminate (default safety)** | Дані недостатні для класифікації (втрата зв'язку, перерване покриття, мала вибірка) | `oracle_status_failed` для класифікаційного callback'а | **Заморозка без спалювання** — DAO голосує `peer-review` upgrade до A або B (вікно 30 днів) |

### 6.2 Slashing формула (тільки для категорії A)

```
slash_amount = locked_balance × min(damage_ratio × penalty_factor, max_slash_ratio)

damage_ratio    = (stressed_trees + dead_trees) / total_trees_in_cluster
penalty_factor  = 1.0   (negligence baseline)
                  + 0.5 (якщо є запис у `EwsAlert` з `severity=critical` 30+ хв без MaintenanceRecord)
                  + 0.5 (якщо AuditLog показує відсутність acknowledged alert'ів)
max_slash_ratio = 0.40  (DAO-governed via ProtocolParameters)
```

> Реалізація: `BlockchainBurningService` (див. §1.2 у [`04_02`](04_02_Business_Logic_and_Services)) перевіряє `cause_classification` перед викликом `slash()` на SCC контракті. Якщо `cause_classification != "A_negligence"` — burn skipped, тільки `freeze_balance!` через `Wallet.lock_and_mint!`.

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
- Якщо DAO не голосує протягом 30 днів — кошти автоматично розморожуються (default safety, на користь інвестора).

### 6.5 Anti-fraud cross-checks

Перед класифікацією `cause_classification`:

- **Hardware tamper detection** (`HardwareKey.tamper_detected_at`) — якщо встановлено: автоматично категорія A, незалежно від dClimate.
- **Dual computation integrity divergence > 30%** ([`05_02 §Dual Computation Integrity`](05_02_Proof_of_Growth_Pipeline)) — автоматично категорія A (фальсифікація device Z).
- **Streamr P2P broadcast gap** довше 24 год без MaintenanceRecord — посилення penalty_factor на +0.25.

---

## 🔒 7. "Proof of Growth" Консенсус

На відміну від Proof of Work (витрата енергії) або Proof of Stake (концентрація капіталу), Proof of Growth прив'язує емісію токенів до верифікованих біологічних процесів:

- Кожен SCC токен підкріплений сенсорно-верифікованим фотосинтезом та поглинанням вуглецю.
- On-device обчислення (mruby) запобігає підробці на рівні заліза.
- Server-side верифікація (Ruby BigDecimal) забезпечує redundant integrity checking.
- Slashing protocol (§6) гарантує економічні наслідки за деградацію через халатність, **не караючи** інвесторів за форс-мажор.

---

## 🔗 8. Cross-ref

- `docs/05_03 §Slashing` — конкретні параметри `ProtocolParameters` registry (`max_slash_ratio`, `penalty_factor_base`).
- `docs/07_01 §Insurance Pool & Etherisc` — операційні деталі парам. страхування.
- `docs/00_03 §Web3 Fallback` — як Slashing/Insurance продовжує працювати при недоступності окремих мостів.
- `docs/00_08 BIZ section` — open business questions та DAO governance backlog.
