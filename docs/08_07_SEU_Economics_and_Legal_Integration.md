# 08_07: СЄУ — Економічна Валідація, Правова Архітектура та Промисловий Дизайн

## 🎯 Мета

Формалізація академічної та прикладної співпраці з **Східноєвропейським університетом імені Рауфа Аблязова (СЄУ)** за п'ятьма напрямами:

1. **Макроекономічна валідація токеноміки NaaS** — наукове обґрунтування дефляційної природи SCC-емісії через Proof of Growth; аудит `DYNAMIC_TAX_RATE`, `INSURANCE_POOL_THRESHOLD` та `ProtocolParameters.sol` на відповідність класичним макроекономічним моделям
2. **Unit-економіка та ESG-облік** — побудова бухгалтерського фреймворку для корпоративних інвесторів, що купують SCC для ESG-звітності; інтеграція `esg_retired_balance` (KlimaDAO retirement), мікро-нагород Solana/Celo та Dynamic Tax 2% у стандартну фінансову звітність
3. **Правова архітектура RWA-токенізації** — юридичне оформлення токенізації лісових ділянок через Polygon Hadron (ERC-3643) згідно з українським та міжнародним законодавством (MiCA); закриття BLOCKER-1 (`07_01`: відсутні KYC/Legal Templates)
4. **Промисловий дизайн PEEK-радому та біомімікрія** — розробка зовнішньої форми антивандальної капсули (Деталь 4, IP67 з conformal Parylene C) для мімікрування під кору дерева **з обов'язковим виступом ≥ 3 мм + super-hydrophobic coating як anti-overgrowth shield** (`01_04 §5.5`); оптимізація ергономіки **польової інсталяції** (заводський press-fit з barbs виконує завод, не forester)
5. **UX/візуалізація даних для B2B-інтерфейсу** — трансформація кіберпанк-естетики Phlex UI у преміальний інвесторський дашборд; композиційне кодування фінансових звітів (`financial_summary`, `carbon_absorption`) для корпоративних ESG-аудиторів

СЄУ — приватний університет у Черкасах, що поєднує **економічні науки**, **юриспруденцію** та **дизайн**. П'ять попередніх академічних партнерів (ЧНУ — фізико-хімічна верифікація хардверу; ЧНУ ФОТІУС — кіберфізична валідація firmware/backend; ЧДТУ — Data Science, RF-верифікація, акустика; ЧІПБ — пожежна безпека, параметричне страхування, SOP; ЧМА — біохімія EBFC, токсикологія металів) покривають повний цикл від анкера до блокчейну, але **жоден з них не має компетенції в макроекономічній теорії токеноміки, корпоративному ESG-обліку, правовій архітектурі RWA та промисловому дизайні**. СЄУ закриває цю критичну прогалину — перетворює "діючий технічний прототип" у "юридично та економічно обґрунтований продукт для інституційних інвесторів".

> **Контекст:** Silken Net має діючий технічний стек (TRL 8 backend, TRL 9 смарт-контракти), але BLOCKER-1 [`07_01`](07_01_Nature_as_a_Service_Contracts) — відсутні юридичні шаблони NaaS-контрактів (Term Sheet, MSA). BLOCKER [`07_01` §4](07_01_Nature_as_a_Service_Contracts) — немає ESG Accounting Framework для корпоративних клієнтів. Без цих артефактів інституційні інвестори не можуть юридично підписати контракт і бухгалтерськи відобразити купівлю SCC. СЄУ як університет з профільною економіко-юридичною експертизою закриває обидва блокери.

---

## ✅ Статус

- **Поточний TRL:** TRL 3 — контакти ідентифіковані, формальну співпрацю не розпочато
- **Стратегічний пріоритет:** P1 — без макроекономічної валідації та юридичних шаблонів NaaS-контракти залишаються нелегітимними для інституційних інвесторів; без промислового дизайну PEEK-радому хардвер не готовий до серійного виробництва
- **Пов'язані модулі:**
  - NaaS контракти та юридичні шаблони → [`07_01_Nature_as_a_Service_Contracts`](07_01_Nature_as_a_Service_Contracts) (BLOCKER-1: KYC/Legal Templates)
  - Юніт-економіка та BOM → [`07_02_Unit_Economics_and_BOM`](07_02_Unit_Economics_and_BOM)
  - Трекер грантів → [`07_03_Grant_Applications_Tracker`](07_03_Grant_Applications_Tracker) (Horizon Europe, Ethereum Foundation)
  - Токеноміка SCC/SFC → [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC)
  - Proof of Growth → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)
  - Мультичейн архітектура → [`05_01_Multichain_Architecture`](05_01_Multichain_Architecture) (Hadron, Solana, Celo, KlimaDAO)
  - PEEK-радом та гіроїдна топологія → [`01_01_Coaxial_Gyroid_Topology_and_PEEK`](01_01_Coaxial_Gyroid_Topology_and_PEEK) (Деталь 4)
  - Phlex UI дизайн-система → [`04_04_Phlex_UI_and_Tailwind`](04_04_Phlex_UI_and_Tailwind)
  - ЧНУ протоколи → [`08_01_University_R_and_D_Protocols`](08_01_University_R_and_D_Protocols)
  - ФОТІУС кіберфізика → [`08_02_Cybernetic_and_Mathematical_Validation`](08_02_Cybernetic_and_Mathematical_Validation)
  - Публікації та IP → [`08_03_Joint_Publications_and_IP_Strategy`](08_03_Joint_Publications_and_IP_Strategy)
  - ЧДТУ Data Science → [`08_04_CHDTU_Data_Science_Collaboration`](08_04_CHDTU_Data_Science_Collaboration)
  - ЧІПБ пожежна безпека → [`08_05_CHIPB_Fire_Safety_Integration`](08_05_CHIPB_Fire_Safety_Integration)
  - ЧМА біохімія → [`08_06_CHMA_Biomedical_Integration`](08_06_CHMA_Biomedical_Integration)

---

## 🛑 Блокери

- **Верифікація посад та наукових профілів** — дані про поточні посади, наукові ступені та спеціалізацію ідентифікованих дослідників потребують підтвердження через офіційний сайт СЄУ. Інформація базується на попередній ідентифікації та може містити неточності
- **Формальна зустріч з ректоратом СЄУ** — узгодження формату партнерства (міжкафедральна тема, спільні публікації, юридичні консультації)
- **Меморандум про співпрацю** — юридичне оформлення між СЄУ та проєктом Silken Net
- **Координація з іншими університетами** — СЄУ працює на "надбудовному" рівні (економіка, право, дизайн); результати hard-science університетів (ЧНУ, ЧДТУ, ЧМА) є входом для СЄУ-аналізу, не навпаки
- **Доступ до правових баз** — для аналізу MiCA, українського законодавства про цифрові активи та ESG-регуляцій ЄС

---

## 👥 1. Ключові Наукові Партнери СЄУ

> **Важливо:** Наведені нижче дані про посади та спеціалізацію потребують верифікації через офіційний сайт СЄУ. Інформація базується на попередній ідентифікації та може містити неточності. Назви кафедр та наукові ступені потребують підтвердження.

### 1.1. Чудаєва Ія Борисівна — Макроекономічне Обґрунтування Токеноміки NaaS

**Посада (потребує верифікації):** Ректор СЄУ
**Науковий ступінь (потребує верифікації):** Доктор економічних наук, професор
**Спеціалізація:** Макроекономічне моделювання, економіка природних ресурсів

**Точка перетину зі Silken Net:**

Silken Net емітує SCC-токени через Proof of Growth pipeline ([`05_02`](05_02_Proof_of_Growth_Pipeline)): кожні 10,000 `growth_points` = 1 SCC. Інституційні інвестори (DAO, ESG-фонди, корпорації) перед купівлею SCC вимагають **науково обґрунтовану фінансову модель**, що доводить: емісія токенів прив'язана до реальних фізичних процесів (ріст біомаси дерева), а не "надрукована з повітря".

**Обов'язкове читання перед початком роботи:**
- [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC) — повна специфікація dual-token системи (SCC utility + SFC governance), ієрархія ролей (MINTER/SLASHER/ADMIN), Dynamic Tax механізм, потік мінтингу та slashing, Subgraph індексація
- [`05_01_Multichain_Architecture`](05_01_Multichain_Architecture) §0 — модульний DePIN стек (12 мереж): чому кожна мережа існує, рольова карта від peaq Identity до Ethereum L1 Finality
- [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline) — повний trustless пайплайн від EBFC до on-chain SCC, 4 рівні верифікації, конверсія 10,000 growth_points = 1 SCC
- [`05_04_Ethereum_L1_State_Anchor`](05_04_Ethereum_L1_State_Anchor) — щотижнева SHA-256 фіналізація state_root в Ethereum Mainnet, reproducible verification

**Поточний стан у кодбейсі:**

```ruby
# app/services/blockchain_minting_service.rb — Dynamic Tax (детально: 05_03 §Dynamic Tax)
DYNAMIC_TAX_RATE = BigDecimal("0.02")           # 2% від емісії → DAO Treasury
INSURANCE_POOL_THRESHOLD = 100_000               # SCC; якщо pool < поріг — Tax ON
INSURANCE_POOL_THRESHOLD_WEI = INSURANCE_POOL_THRESHOLD * 10**18

# contracts/ProtocolParameters.sol — on-chain параметри (governance-controlled, 05_03 §Governance)
# KEY_EMISSION_THRESHOLD     — скільки growth_points = 1 SCC (default: 10,000)
# KEY_DYNAMIC_TAX_RATE       — ставка Dynamic Tax (default: 2%, 18 decimals)
# KEY_INSURANCE_POOL_THRESHOLD — поріг Insurance Pool (default: 100,000 SCC)
# KEY_SCC_PER_TONNE_CO2      — еквівалент SCC у тоннах CO₂ (D-MRV mapping)
# KEY_SCC_FALLBACK_PRICE_USD_CENTS — governance-controlled fallback ціна SCC

# contracts/SilkenCarbonCoin.sol — MAX_SUPPLY = 1,000,000,000 SCC (1B)
# contracts/SilkenForestCoin.sol — MAX_SUPPLY = 100,000,000 SFC (100M)

# SilkenGovernor.sol (05_01 §6 Governance DAO):
#   votingDelay = 43200 blocks (~1 день Polygon)
#   votingPeriod = 302400 blocks (~7 днів)
#   proposalThreshold = 100 SFC
#   quorum = 4% від totalSupply
#   Flash Loan Defense: snapshot voting (getPastVotes), 48h timelock
```

**Проблема:** Поточна модель побудована інженером (Архітектор), а не макроекономістом. Інвестори запитують:
- Чи не інфляційна емісія SCC при масштабуванні на мільйони дерев?
- Як Dynamic Tax 2% впливає на рівновагу попит/пропозиція?
- Чи стійка модель при різних сценаріях (бичачий/ведмежий ринок)?
- Яка фундаментальна вартість 1 SCC відносно 1 тонни CO₂?

**Конкретний R&D-запит:**

**Завдання А: Макроекономічне обґрунтування Proof of Growth**

```
Контекст: SCC = utility token, прив'язаний до біологічного росту (growth_points).
  Емісія обмежена MAX_SUPPLY = 1B SCC.
  Slashing (BlockchainBurningService) скорочує пропозицію при деградації.
  Dynamic Tax 2% перерозподіляє до DAO Treasury при недофінансуванні.

Завдання Чудаєвої:
  1. Побудова макроекономічної моделі SCC-ринку:
     - Пропозиція: f(growth_points, MAX_SUPPLY, slash_rate)
     - Попит: f(ESG_obligation, carbon_price, corporate_demand)
     - Рівновага: за яких умов P(SCC) стабілізується?
  2. Stress-тестування моделі:
     Сценарій A: 1M дерев, 80% homeostasis → яка річна емісія SCC?
     Сценарій B: 1M дерев, 50% stress → масовий slashing → як P(SCC) реагує?
     Сценарій C: 10M дерев → чи створює це інфляційний тиск?
  3. Порівняння з Verra/Gold Standard:
     В чому SCC фундаментально відрізняється від VCU (Verified Carbon Units)?
     Аргументація для whitepaper: "SCC ≠ speculative token; SCC = D-MRV-verified asset"
  4. Рекомендації щодо ProtocolParameters:
     - Оптимальний EMISSION_THRESHOLD (зараз 10,000)
     - Оптимальний DYNAMIC_TAX_RATE (зараз 2%)
     - Оптимальний INSURANCE_POOL_THRESHOLD (зараз 100,000 SCC)
  5. Результат: Economic Whitepaper для seed-раунду та Web3-грантів
```

**Завдання Б: Антиінфляційний аудит DAO Governance**

```
Контекст: SFC holders (SilkenGovernor.sol) можуть голосувати за зміну
  ProtocolParameters (EMISSION_THRESHOLD, DYNAMIC_TAX_RATE, SLASH_THRESHOLD).
  Теоретично можуть проголосувати за зниження EMISSION_THRESHOLD до 1,000
  → × 10 емісія → інфляція.

Завдання:
  1. Визначити "безпечні діапазони" для кожного параметра ProtocolParameters
  2. Оцінити ризики governance attack:
     чи може whale-voter маніпулювати емісією?
  3. Рекомендації: які параметри мають бути immutable (не governance-controlled)?
```

---

### 1.2. Ус Галина Олександрівна — Unit-Економіка та ESG-Облік

**Посада (потребує верифікації):** Завідувачка кафедри економіки, маркетингу, обліку і оподаткування, СЄУ
**Науковий ступінь (потребує верифікації):** Доктор економічних наук, професор
**Спеціалізація:** Бухгалтерський облік, цифрова економіка, фінансова звітність

**Точка перетину зі Silken Net:**

Корпорації, що купують SCC для ESG-звітності, стикаються з фундаментальною бухгалтерською проблемою: **як провести через баланс купівлю утилітарного токена на Polygon, мікро-нагороди у USDC на Solana та виплати у cUSD на Celo?** Жоден із 5 існуючих університетських партнерів не має компетенції в корпоративному обліку та податковій оптимізації.

**Обов'язкове читання:**
- [`05_01`](05_01_Multichain_Architecture) §8 (Solana Micro-Rewards), §9 (Celo ReFi), §10 (KlimaDAO ESG) — повна специфікація трьох платіжних потоків, що потребують бухгалтерського mapping
- [`05_03`](05_03_Tokenomics_SCC_and_SFC) §Dynamic Tax — механізм 2% відрахування при `batchMint`, умови активації (`insurance_pool_requires_funding?`), кешування 15 хв
- [`05_03`](05_03_Tokenomics_SCC_and_SFC) §Потік Slashing — як `BurnCarbonTokensWorker` автоматично спалює SCC при >20% stressed trees, що впливає на баланс інвестора

**Поточний стан у кодбейсі:**
validates :balance, numericality: { greater_than_or_equal_to: 0 }         # growth_points
validates :locked_balance, numericality: { greater_than_or_equal_to: 0 }   # заблоковано для мінтингу
validates :esg_retired_balance, numericality: { greater_than_or_equal_to: 0 } # KlimaDAO retired
validates :toucan_bridged_balance, numericality: { greater_than_or_equal_to: 0 } # Toucan TCO2

# app/services/klima_dao/retirement_service.rb — ESG retirement
# @wallet.decrement!(:balance, @amount_to_retire)
# @wallet.increment!(:esg_retired_balance, @amount_to_retire)
# → Creates BlockchainTransaction with status: :retired

# app/services/solana/minting_service.rb — мікро-нагороди
# DEFAULT_MICRO_REWARD_LAMPORTS = 10_000  # 0.01 USDC per telemetry packet
# Growth bonus: growth_points × 100 lamports

# app/services/celo/community_reward_service.rb — ReFi нагороди
# REWARD_AMOUNT = "5.0"  # 5 cUSD за здоровий кластер / добу
# MAX_STRESS_INDEX = 0.2  # поріг для отримання нагороди
```

**Конкретний R&D-запит:**

**Завдання А: ESG Accounting Framework — модель SPV (корпорація НЕ тримає токени)**

```
⚠️ Засаднича корекція (2026-05-28): помилково ставити питання "як корпорація
  (BMW) відобразить на балансі токени на Polygon + USDC на Solana + cUSD на
  Celo". Жодна серйозна корпорація НЕ заводитиме криптогаманці, custody-сервіс
  і не платитиме податки за кожну зміну курсу USDC на трьох блокчейнах.
  Корпорації купують ПОСЛУГУ або СЕРТИФІКАТ, а не крипту.

Правильна архітектура — SPV (Special Purpose Vehicle):
  - Компанія-оператор Silken Net виступає SPV.
  - Корпоративний клієнт платить SPV звичайний фіат (€/$) за договором NaaS —
    для клієнта це виглядає як SaaS-підписка / купівля послуги.
  - SPV самостійно мінтить SCC, акумулює Solana/Celo мікро-нагороди, робить
    retirement (спалювання) від імені клієнта.
  - Клієнт отримує лише фінальний PDF-сертифікат із транзакцією спалювання
    (Proof of Retirement, on-chain tx hash) для свого ESG-звіту (CSRD/GRI/TCFD).
  Уся крипто-складність лишається ВСЕРЕДИНІ SPV; клієнт її не бачить.

Завдання Ус (бухгалтерська модель ТІЛЬКИ для SPV):
  1. Accounting Bridge на рівні SPV: mapping кожної on-chain операції
     (mint SCC / Solana USDC / Celo cUSD / KlimaDAO retirement / Dynamic Tax 2%)
     → МСФЗ (IFRS) категорія в книгах SPV
  2. Облік виручки SPV: фіатний дохід за NaaS-договором (просто, IFRS 15)
     vs собівартість (крипто-операції, газ, custody)
  3. Сторона клієнта (просто): фіатна купівля послуги вуглецевого retirement →
     операційна витрата + Proof-of-Retirement сертифікат для ESG-звіту.
     НЕ потребує крипто-обліку, custody чи податку на курсові різниці.
  4. Податкова класифікація на рівні SPV: SCC як utility token у ЄС,
     USDC/cUSD як operational inflow, Dynamic Tax як cost of goods
  5. Результат: SPV Accounting Framework + клієнтський Proof-of-Retirement шаблон
     (додаток до NaaS Term Sheet, 07_01 BLOCKER-1)

Примітка: крипто-нативні інвестори (DAO, ReFi-фонди, KlimaDAO-учасники) МОЖУТЬ
  тримати SCC напряму у власному гаманці (поточна wallet/hadron_kyc архітектура).
  SPV-модель — основний шлях для традиційних корпорацій; direct-wallet —
  вторинний шлях для крипто-нативних покупців.
```

**Завдання Б: ROI-модель для unit-економіки кластера**

```
Контекст: docs/07_02 фіксує BOM ($37-$46/Soldier, $234-$280/Queen),
  але фінансова модель окупності потребує академічної валідації.

Завдання:
  1. Рецензія ROI-моделі 07_02 з позиції корпоративних фінансів
  2. Sensitivity analysis: при яких carbon_price модель окупна за 3/5/10 років?
  3. Порівняння з конкурентами (Pachama, Dendra, Open Forest Protocol)
  4. Рекомендації щодо ціноутворення NaaS-підписки
```

---

### 1.3. Аблязов Денис Едуардович — Правова Архітектура RWA-Токенізації

**Посада (потребує верифікації):** Віце-президент СЄУ, в.о. завідувача кафедри права
**Науковий ступінь (потребує верифікації):** Кандидат юридичних наук
**Спеціалізація:** Міжнародне публічне та європейське право, правове регулювання цифрових активів

**Точка перетину зі Silken Net:**

Silken Net токенізує лісові ділянки як Real World Assets (RWA) через Polygon Hadron Identity Platform ([`05_01`](05_01_Multichain_Architecture) §7). Це створює юридичний ланцюг: дерево в Черкаському борі → Machine DID (peaq) → SCC токен (Polygon ERC-20) → KYC/KYB (Hadron ERC-3643) → гаманець інвестора в Берліні. Кожна ланка потребує правового "заземлення" в юрисдикції — українській та європейській.

**Обов'язкове читання:**
- [`05_01`](05_01_Multichain_Architecture) §7 (Polygon Hadron) — два потоки: `verify_investor!` (KYC) та `register_asset!` (RWA); `WEB3_STRICT_MODE` поведінка
- [`05_01`](05_01_Multichain_Architecture) §6 (Polygon Primary EVM) — Guard Clauses (verified_by_iotex + oracle_status + hadron_kyc), Governance DAO pipeline
- [`05_03`](05_03_Tokenomics_SCC_and_SFC) §Ієрархія Ролей — MINTER_ROLE, SLASHER_ROLE, DEFAULT_ADMIN_ROLE та їх розділення
- [`07_01`](07_01_Nature_as_a_Service_Contracts) §1.1 (B2B Corporate) — KYC/KYB через Hadron, INSURANCE_PREMIUM_RATE 5%

**Поточний стан у кодбейсі:**
class HadronComplianceService
  # verify_investor!(wallet) — перевіряє KYC → wallet.hadron_kyc_status = "approved"/"rejected"
  # register_asset!(naas_contract) — реєструє лісову ділянку як RWA → naas_contract.hadron_asset_id

  # Guard clause в BlockchainMintingService (рядок 94):
  # unless recipient_wallet.hadron_kyc_status == "approved"
  #   raise "Compliance Breach: Wallet is not Hadron KYC approved"
  # end
end

# app/models/naas_contract.rb — NaaS контракт (AASM: draft → active → fulfilled/breached/cancelled)
# INSURANCE_PREMIUM_RATE = BigDecimal("0.05")  # 5% від total_funding → Insurance Pool
# BLOCKER-1 (07_01): KYC/Legal Templates — ВІДСУТНІ

# db/structure.sql — стовпець hadron_kyc_status
# hadron_kyc_status character varying DEFAULT 'pending'::character varying
# CREATE INDEX index_wallets_on_hadron_kyc_status ON public.wallets (hadron_kyc_status)
```

**Конкретний R&D-запит:**

**Завдання А: Legal Framework для RWA-токенізації лісу**

```
Контекст: Polygon Hadron — це compliance layer (ERC-3643).
  Silken Net реєструє лісові ділянки як RWA через register_asset!().
  Але юридична структура цієї реєстрації — відсутня.

Правові питання (Аблязов Д.):
  1. Українське законодавство:
     - Чи може лісова ділянка (державна/приватна) бути токенізована?
     - Чи потрібен дозвіл ДП "Ліси України" для встановлення анкерів?
     - Як Machine DID (peaq) співвідноситься з кадастровим номером?
  2. Європейське законодавство (MiCA):
     - SCC = utility token чи security token за MiCA?
     - Чи потрібна реєстрація CASP (Crypto-Asset Service Provider)?
     - Як ESG-токенізація лісу вписується в EU Taxonomy Regulation?
  3. ERC-3643 (T-REX) compliance — НЕ плутати інструмент із регуляторною сутністю:
     - Polygon Hadron — це лише сервіс перевірки документів; він НЕ робить
       інвестора легальним. ERC-3643 (T-REX) вимагає on-chain identity
       (ONCHAINID), яку видає ліцензований Identity Issuer + Compliance
       contract з правилами трансферу.
     - Завдання Аблязова: розробити Compliance Rulebook, що визначає критерії
       Identity Issuer — які саме документи потрібні, щоб смарт-контракт
       дозволив володіти/приймати SCC:
         · KYC (фізособи): паспорт, AML/CFT скринінг, sanctions list
         · KYB (юрособи / ESG-фонди): витяг з реєстру, кінцеві бенефіціари
           (UBO), джерело коштів, корпоративна AML-перевірка
     - Для B2B NaaS (корпоративний клієнт) KYC недостатній — потрібен жорсткий
       KYB. Hadron виконує перевірку; легітимність дає Rulebook + Identity Issuer.
  4. Шаблони юридичних документів (→ закриття BLOCKER-1 у 07_01):
     - NaaS Term Sheet (корпоративна підписка)
     - Master Service Agreement (MSA)
     - Carbon Credit Purchase Agreement
     - Data Processing Agreement (GDPR)
  5. Результат: Legal Opinion + 4 юридичних шаблони
```

**Завдання Б: Юридичний аналіз cross-border slashing**

```
Контекст: BlockchainBurningService автоматично спалює SCC
  при деградації кластера (>20% дерев зі stress_index ≥ 1.0).
  Це АВТОМАТИЧНА втрата активу інвестора.

Правове питання:
  1. Чи є автоматичний slashing юридично допустимим у ЄС?
  2. Як оформити slashing clause у NaaS-контракті?
  3. Який механізм оскарження (dispute resolution) для інвестора?
  4. Чи потрібна арбітражна клауза (ICC/UNCITRAL)?
```

---

### 1.4. Аблязова Наталія Рауфівна — Консорціум та Грантова Стратегія

**Посада (потребує верифікації):** Президент СЄУ
**Науковий ступінь (потребує верифікації):** Кандидат економічних наук, доцент
**Спеціалізація:** Управління підприємствами, інноваційний менеджмент

**Точка перетину зі Silken Net:**

Silken Net має 6 університетських партнерів (ЧНУ, ФОТІУС, ЧДТУ, ЧІПБ, ЧМА, СЄУ), технологічного партнера (ActiveBridge) та мережу з 7 Web3-грантів ([`07_03`](07_03_Grant_Applications_Tracker)). Для переходу від TRL 3-4 до TRL 7-8 потрібне **структуроване консорціумне управління** та **грантове фінансування**. Існуюча модель "Потрійної Спіралі" (наука + бізнес + держава) описана в [`08_02` §23](08_02_Cybernetic_and_Mathematical_Validation), але не формалізована юридично.

**Конкретний R&D-запит:**

**Завдання А: Формалізація Потрійної Спіралі (Triple Helix)**

```
Контекст: 08_02 §23 (Осауленко) описує Triple Helix як концепцію.
  Потрібно перетворити концепцію на юридичну та операційну структуру.

Завдання Аблязової Н.:
  1. Юридична форма консорціуму:
     - 6 університетів + ActiveBridge + Silken Net
     - Який юридичний формат? (асоціація / договір про спільну діяльність / ГО)
  2. Розподіл ролей:
     ЧНУ = hard science (фізика, хімія, біоценологія) + ректорат-парасоль (Кирилюк Є.М. — підпис MoU, WP-Bioeconomy ко-PI; Спрягайло О.В. — WP-Biodiversity ко-PI, ПЗФ-канал до Черкаської ОДА; деталі: [`08_01` §1.3–§1.4](08_01_University_R_and_D_Protocols), [`08_03` §1G](08_03_Joint_Publications_and_IP_Strategy))
     ФОТІУС = cybernetics (firmware, backend, math)
     ЧДТУ = data (statistics, RF, acoustics)
     ЧІПБ = safety (fire, SOP, ДСНС)
     ЧМА = biomedical (EBFC, toxicology)
     СЄУ = economics & legal (tokenomics, RWA, design)
     ActiveBridge = implementation (software development)
     Silken Net = IP holder & system integrator
  3. Governance структура:
     Хто ухвалює рішення про напрям R&D?
     Як розподіляються ресурси між 6 університетами?
```

**Завдання Б: Грантова стратегія Horizon Europe**

```
Контекст: 07_03 фіксує 7 Web3-грантів (peaq, IoTeX, Chainlink, Filecoin,
  Giveth, Solana, Polygon). Але відсутні заявки на:
  - Horizon Europe CLUSTER 6 (Climate, Energy, Mobility)
  - Horizon Europe EIC Pathfinder / Accelerator
  - NFDI (National Research Data Infrastructure)
  - NRFU (National Research Foundation of Ukraine)
  - Ethereum Foundation Academic Grants

Завдання:
  1. Mapping Silken Net → Horizon Europe calls:
     Який call найкраще підходить? (estimated: CLUSTER 6, Topic: biodiversity monitoring)
  2. Вимоги до консорціуму:
     Скільки партнерів з ЄС потрібно? (мін. 3 країни)
     Як ЧНУ/ЧДТУ/СЄУ вписуються як українські партнери?
  3. Бюджетне планування:
     Типовий бюджет Horizon Europe RIA = €3-5M на 4 роки
     Розподіл: WP1 (координація, СЄУ), WP2-WP5 (R&D, інші ВНЗ), WP6 (dissemination)
  4. Результат: Pre-proposal для Horizon Europe + NRFU заявка
```

---

### 1.5. Гедз Михайло Йосипович — Аудит Методології D-MRV

**Посада (потребує верифікації):** Проректор з якості освіти СЄУ
**Науковий ступінь (потребує верифікації):** Доктор економічних наук, професор
**Спеціалізація:** Управління якістю, аудит, сертифікація процесів

**Точка перетину зі Silken Net:**

Silken Net позиціонує себе як D-MRV (Digital Measurement, Reporting, Verification) — цифрову альтернативу Verra VCS та Gold Standard. Для визнання SCC-кредитів на добровільному вуглецевому ринку потрібна **академічна сертифікація методології збору даних**. Гедз як фахівець з аудиту та управління якістю може розробити ISO-подібний фреймворк для D-MRV.

**Обов'язкове читання:**
- [`05_02`](05_02_Proof_of_Growth_Pipeline) — повна схема trustless пайплайну від Soldier → Queen → Rails → peaq → IoTeX → Chainlink → Polygon → Solana; ключовий інваріант (всі guard clauses)
- [`05_04`](05_04_Ethereum_L1_State_Anchor) — SHA-256 state_root = `"#{total_scc}|#{total_sfc}|#{active_tree_count}|#{chain_hash}|#{anchored_at}"`, reproducible verification, MIN_ANCHOR_INTERVAL = 6 днів
- [`05_03`](05_03_Tokenomics_SCC_and_SFC) §Потік Мінтингу — від TokenomicsEvaluatorWorker до BlockchainConfirmationWorker; Guard Clauses (IoTeX ZK + Chainlink Oracle + Hadron KYC)
- [`05_01`](05_01_Multichain_Architecture) §0 — модульний DePIN стек: 6 рівнів довіри (Identity → Verification → Oracle → Execution → Memory → Finality)

**Поточний стан у кодбейсі:**
# 1. TelemetryUnpackerService — AES-256-CBC decrypt, 21-byte decode, Lorenz server-side
# 2. IotexVerificationWorker — IoTeX W3bstream ZK-proof (verified_by_iotex: true)
# 3. ChainlinkDispatchWorker — Oracle consensus (oracle_status: "fulfilled")
# 4. BlockchainMintingService — Guard clauses (iotex + oracle + hadron_kyc)
#
# Dual Computation Integrity:
# SilkenNet::Attractor (Float64, IEEE 754 — ідентично firmware [FW.7]) vs device Z (Float64)
# Divergence > 30% → fraud flag (FRAUD_DEVIATION_THRESHOLD)
```

**Конкретний R&D-запит:**

**Завдання А: Мапінг D-MRV на Verra-методологію (delta_t ↔ біомаса), ISO 14064 як backbone**

```
Контекст: Verra VCS та Gold Standard мають акредитовані аудиторські
  процедури. Silken Net замінює ручний аудит на автоматичний (IoTeX ZK-proofs,
  Chainlink oracles, Dual Computation Integrity). Але ЦЕ НЕ ВИЗНАНО
  міжнародними реєстрами як еквівалент.

⚠️ Корекція стандарту (2026-05-28): ISO 14064 — НЕ головний стандарт для
  лісового carbon removal. ISO 14064-2/-3 корисні як БЕКБОН процесу
  верифікації (project-level quantification + validation/verification), але
  вони НЕ є кредитною методологією. Щоб SCC-кредити визнавалися на ринку,
  потрібно мапити параметри Silken Net на ЗАТВЕРДЖЕНУ реєстром методологію
  Verra VCS:
    · VM0003 — Improved Forest Management (IFM, керований ліс)
    · AR-ACM0003 / VM0047 — Afforestation, Reforestation & Revegetation (ARR)
  Ці методології диктують baseline, additionality, leakage, permanence та
  ПРОТОКОЛ ВИМІРЮВАННЯ (алометричні рівняння біомаси через DBH — Diameter at
  Breast Height). Автоматичний D-MRV стане легітимним лише коли доведено, що
  телеметрія еквівалентна тому, що Verra вимагає міряти рулеткою.

Завдання Гедза:
  1. 🎯 ЯДРО: довести наукову еквівалентність delta_t ↔ приріст біомаси.
     delta_t (час заряду іоністора) ∝ ксилемний потік ∝ фотосинтетична
     активність ∝ річний приріст DBH/біомаси. Вивести передавальну функцію
     delta_t → ΔDBH → tCO₂, валідовану на ground-truth обмірах (спільно з
     біо-хабом ЧНУ та ЧДТУ-статистикою, 08_04). Це і є місток D-MRV ↔ Verra.
  2. Mapping Silken Net D-MRV → методологія Verra (VM0003 IFM / VM0047 ARR):
     які параметри методології закриваються телеметрією автоматично,
     які лишаються потребувати ручного/супутникового аудиту (Бушин, 08_02)
  3. ISO 14064-2/-3 + ICROA як backbone якості процесу:
     відповідність ICROA Code of Best Practice; 14064-3 для validation/verification
  4. Розробка Silken Net Quality Management System (QMS):
     - Процедура збору даних (від Soldier до TelemetryLog)
     - Процедура верифікації (IoTeX + Chainlink + Dual Computation)
     - Процедура мінтингу (Guard clauses + Dynamic Tax)
     - Процедура slashing (ContractHealthCheckService, 20% threshold)
  5. Сертифікаційний roadmap: шлях до Verra-валідації методології + які
     ISO/ICROA-сертифікати потрібні для входу на добровільний ринок
  6. Результат: D-MRV Methodology Document (мапінг на Verra VM0003/VM0047)
```

---

### 1.6. Денисенко Юрій Миколайович — Промисловий Дизайн PEEK-Радому

**Посада (потребує верифікації):** В.о. завідувача кафедри дизайну СЄУ
**Науковий ступінь (потребує верифікації):** Кандидат архітектури, доцент
**Спеціалізація:** Промисловий дизайн, архітектурне проектування, біомімікрія

**Точка перетину зі Silken Net:**

Деталь 4 ([`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK) §Деталь 4) — PEEK-радом (∅20–30 мм), IP68, радіопрозорий купол над SMD-антеною 868 МГц. Поточний дизайн — суто інженерний (циліндр/купол). Потрібен **промисловий дизайн**, що:
- Мімікрує під кору дерева (camouflage) для антивандальності
- Витримує механічні навантаження стовбура (розширення/стиснення від температур)
- Забезпечує ергономічну press-fit збірку (R&D-персоналом у польових умовах)
- Має естетичний вигляд для демонстрацій інвесторам та медіа

**Конкретний R&D-запит:**

**Завдання А: Біомімікрічний дизайн PEEK-радому з Anti-Overgrowth Shield (REVISED 2026-05-16)**

```
Контекст: docs/01_01, §Деталь 4 + docs/01_04 §5.5 (NEW Anti-Overgrowth Shield).
  PEEK (поліефірефіркетон) — біоінертний, радіопрозорий, IP67.
  Радом має бути непомітним на стовбурі Pinus sylvestris,
  але ОДНОЧАСНО повинен виступати ≥ 3 мм над корою як механічний
  захист від обростання катода калюсом (інакше через 5+ років
  природний приріст кори накриває PTFE-GDL → EBFC мертва).

  📌 Архітектурний парадокс: «непомітний радом» (естетика) vs
  «виступаючий dome» (функція anti-overgrowth) — це робота Денисенка
  розв'язати через дизайн (camouflage texture + smooth bell geometry,
  яка зливається з природним наростом кори навколо).

Завдання Денисенка (revised):
  1. Фотофіксація кори Pinus sylvestris (Черкаський бір):
     текстура, колір, рельєф, тріщини, лишайники
  2. 3D-моделювання PEEK-радому з біомімікрією + ANTI-OVERGROWTH:
     - CAD-модель (SolidWorks / Rhino / Blender)
     - Геометрія: ∅20–30 мм, ВИСТУП ≥ 3 мм над зовнішньою корою,
       радіус заокруглення вершини ≥ 5 мм (smooth bell — клітини
       калюсу не можуть «зачепитися» за гладку поверхню)
     - Товщина стінки ≥ 2 мм, O-ring канавка на стику з катодом
     - Кріплення: різьба M6 на ДЕТАЛЬ 3 = КАТОД Zone 3 (НЕ Анод!
       — раніше документ помилково писав «Деталь 3 (Анод)», виправлено
       2026-05-16, див. `02_01 §5.2` SSOT-fix)
     - 🫁 КРИТИЧНО — ВЕНТИЛЯЦІЯ КАТОДА (NEW 2026-05-28): Катод Zone 3 — це
       ПОВІТРОДИХАЛЬНИЙ електрод. У центрі фланця — мікропориста PTFE-GDL
       мембрана, через яку атмосферний O₂ дифундує до лакази/ZIF для реакції
       ORR (O₂ + 4H⁺ + 4e⁻ → 2H₂O). Якщо накрутити суцільний PEEK-купол на M6
       поверх фланця — доступ O₂ перекривається, катод задихається, EBFC гине
       за хвилини. Тому радом ОБОВ'ЯЗКОВО має:
         · бічні вентиляційні канали (louvers/vents) для циркуляції повітря
           під куполом, АБО гідрофобну дихальну ePTFE-вставку (Gore-style vent)
         · ці канали пропускають O₂, але блокують пряму воду/бруд/комах
         · збереження повітряного об'єму над PTFE-GDL (не герметизувати!)
       O-ring ущільнює лише різьбовий стик з катодом, НЕ повітряний тракт.
     - 3D RF Keep-Out: антена має overhang за периметр Ti-фланця;
       Z-clearance ≥ 8 мм над Ti (`02_01 §5.3` revised); антена розміщується
       НАД вентиляційними каналами, не перекриваючи їх
  3. Координація з Теліженко (§1.7): селекція super-hydrophobic
     coating (Fluoropel PFC-1601V, CA > 150°) — surface treatment
     на зовнішньому боці dome для blocking адгезії клітин
  4. Прототип: FDM-друк (PEEK-like: ULTEM 9085 або PEKK) для польового тесту
  5. Оцінка stress concentration factor (K_t) при текстурованій поверхні
     + creep behavior через 10 років (FEM моделювання у пари з Гусаком,
     ANSYS LS-DYNA Prony series — див. `08_03 §1F` Стаття 19 revised)
  6. Результат: 3D CAD-модель + FDM-прототип + візуалізація для pitch deck
     + 12-місячний польовий тест anti-overgrowth shield на тестовому дереві
```

**Завдання Б: Ергономіка польової інсталяції (REVISED — складніший press-fit)**

```
Контекст: docs/02_02 — Blind-Mate Pogo Pin Interface +
  docs/01_01 §3 (REVISED 2026-05-16: 8-step assembly з mechanical lock).

  ⚠️ ВАЖЛИВО: Поточна збірка (v3) НЕ призначена для польової інсталяції!
  Анкер збирається на ЗАВОДІ через nano-precision press-fit:
  - PEEK 150°C (>T_g 143°C) → softened state
  - Контрольована сила 800–1200 N для barb engagement (§4.3 A)
  - Після охолодження — встановлення DIN 471 retaining rings
  - Це НЕМОЖЛИВО зробити в лісі ручним інструментом.

  Польова інсталяція — лише ВКРУЧУВАННЯ заводським анкером
  у заздалегідь висвердлений канал (Flush Mount step drilling,
  `01_04 §3.1`) + накручування Радому (Деталь 4) на катод (Деталь 3).

Завдання Денисенка (revised):
  1. Аналіз ергономіки:
     - Заводська збірка (factory) vs польова інсталяція (forester) —
       чітке розмежування, що робить хто
     - Інструменти для forester: hex driver M6, micro-mill,
       calibrated torque wrench для накручування Радому
  2. Дизайн монтажного набору (field kit) — ТІЛЬКИ польова частина:
     - Коронка для мікрофрезерування (∅8 мм, глибина 120 мм)
     - Hex driver M6 для встановлення анкера
     - Torque wrench (0.5–2 Nm) для накручування Радому без overstress O-ring
     - Захисний ковпачок для транспортування
     - **NEW (anti-overgrowth maintenance, `01_04 §5.5 C`):** micro-shaver
       для periodic cleaning приростаючої тканини навколо виступу Радому
       раз на 5–7 років
  3. Дизайн заводського press-fit стенда (factory kit) — координація
     з Гусаком (ЧНУ) щодо контролю sily 800–1200 N + температури 150°C
  4. Результат: Exploded view + дві інструкції (factory + field)
     + 5-year forester maintenance protocol
```

---

### 1.7. Теліженко Олександра Василівна — UX/Візуалізація Даних для B2B

**Посада (потребує верифікації):** Доцент кафедри дизайну СЄУ
**Науковий ступінь / звання (потребує верифікації):** Заслужений художник України
**Спеціалізація:** Візуальне мистецтво, композиція, кольорове кодування, UX/UI естетика

**Точка перетину зі Silken Net:**

Phlex UI ([`04_04`](04_04_Phlex_UI_and_Tailwind)) — кіберпанк-естетика (matrix-rain, dark theme, hex alphabet, `bg-gaia-surface`). Це ідеально для розробників та IoT-інженерів, але **не для директора ESG-відділу BMW чи менеджера Carbon Fund**. Корпоративний інвестор має побачити:
- Преміальний інтерфейс з чистою типографікою
- Фінансові графіки (ROI, carbon absorption, esg_retired_balance)
- Довірливий (trustworthy) дизайн, що відповідає B2B SaaS-стандартам

**Поточний стан компонентів:**

```
app/views/components/
├── reports/
│   ├── financial_summary.rb    ← Фінансовий звіт (balance, transactions)
│   ├── carbon_absorption.rb    ← Поглинання CO₂ (growth_points → SCC)
│   └── index.rb
├── dashboard/
│   ├── home.rb                 ← Головний дашборд
│   ├── map_node.rb             ← Leaflet map node
│   └── event_row.rb
├── contracts/
│   ├── show.rb                 ← NaaS контракт
│   └── index.rb
└── wallets/
    ├── balance.rb              ← Баланс гаманця
    └── metadata_frame.rb       ← Метадані (esg_retired_balance)
```

```javascript
// app/javascript/controllers/matrix_rain_controller.js
// Hex rain на canvas (~16 fps) — декоративний ефект для developer audience
// Alphabet: "0123456789ABCDEF"
// НЕ підходить для B2B investor dashboard
```

**Конкретний R&D-запит:**

**Завдання А: B2B інвесторський дашборд (UX/UI концепт)**

```
Контекст: Поточна дизайн-система (04_04) використовує токени:
  bg-gaia-surface, text-gaia-text, border-gaia-border — dark theme
  Phlex components: ApplicationComponent < Phlex::HTML
  TailwindMerge: tokens(*static, **conditional)

Завдання Теліженко:
  1. Мудборд (mood board) для B2B investor interface:
     - Кольорова палітра: довіра (синій/зелений) vs кіберпанк (чорний/зелений)
     - Типографіка: serif (довіра) vs mono (tech) — баланс
     - Іконографіка: іконки для ESG, carbon, slashing, growth
  2. Wireframes для ключових Phlex-компонентів:
     - financial_summary.rb → фінансовий дашборд (pie charts, bar charts)
     - carbon_absorption.rb → графік поглинання CO₂ (timeline, cumulative)
     - contracts/show.rb → NaaS контракт (статус, KPI, milestones)
  3. Рекомендації щодо дизайн-токенів:
     Чи потрібна друга палітра (investor theme) поруч із gaia-theme?
     Або адаптувати існуючу палітру для обох аудиторій?
  4. Результат: Figma/Adobe XD прототип + рекомендації для Phlex-розробників
```

---

## 🤝 2. Міжуніверситетська Синергія (СЄУ × Інші Партнери)

### 2.1. СЄУ × ЧДТУ (Карапетян): Статистична Валідація Токеноміки

| СЄУ (Економіка) | ЧДТУ (Data Science) | Результат |
|------------------|---------------------|-----------|
| Чудаєва: макроекономічна модель SCC-ринку | Карапетян: Monte Carlo симуляція 10K сценаріїв | Stress-tested Economic Whitepaper |
| Ус: ROI-модель кластера | Карапетян: sensitivity analysis (R/Python) | Validated Unit Economics для інвесторів |
| Гедз: delta_t ↔ DBH/біомаса + mapping на Verra VM0003/VM0047 (ISO 14064-2/-3 як backbone) | Карапетян: статистичний аналіз достовірності D-MRV | Сертифікаційний документ для Verra |

**Тип зв'язку:** Послідовний — СЄУ будує економічну модель → ЧДТУ валідує статистично на реальних/симульованих даних

### 2.2. СЄУ × ФОТІУС (Осауленко): Формалізація Потрійної Спіралі

| СЄУ (Менеджмент) | ФОТІУС (Системний аналіз) | Результат |
|-------------------|---------------------------|-----------|
| Аблязова Н.: юридична структура консорціуму | Осауленко: математична модель несилової взаємодії (08_02 §22) | Governance framework з формальною верифікацією |
| Аблязова Н.: розподіл ресурсів між 6 ВНЗ | Осауленко: кластерний аналіз R&D-портфеля (08_02 §21) | Оптимальний розподіл бюджету Horizon Europe |

**Тип зв'язку:** Комплементарний — СЄУ: бізнес-архітектура, ФОТІУС: математична формалізація

### 2.3. СЄУ × ЧІПБ: Актуарне Обґрунтування Параметричного Страхування

| СЄУ (Облік/Право) | ЧІПБ (Пожежна безпека) | Результат |
|--------------------|------------------------|-----------|
| Ус: бухгалтерський облік страхових виплат | Зобенко (ЧІПБ): QRA тригерів, актуарне моделювання (08_05 §1.4) | ESG-compliance страхового пулу |
| Аблязов Д.: юридична рамка parametric insurance | Куліца (ЧІПБ): fire model, калібрування тригерів (08_05 §1.3) | Юридично валідний страховий контракт |

**Тип зв'язку:** Комплементарний — ЧІПБ: технічне обґрунтування тригерів, СЄУ: юридичне та бухгалтерське оформлення

### 2.4. СЄУ × ЧНУ: Дизайн Капсули та Біомімікрія

| СЄУ (Дизайн) | ЧНУ (Фізика/Хімія) | Результат |
|---------------|---------------------|-----------|
| Денисенко: 3D-модель PEEK-радому, біомімікрія кори + **anti-overgrowth dome ≥ 3 мм** (`01_04 §5.5`) | Гусак (ЧНУ): FEM stress-strain + **PEEK creep ANSYS LS-DYNA 10y simulation** (Prony series, `01_01 §4.3`) | Протестований на міцність + creep + anti-overgrowth біомімікрічний радом |
| Денисенко: ергономіка field kit | Спрягайло (ЧНУ): ботаніка, характеристики кори Pinus sylvestris | Інструкція інсталяції, адаптована під конкретну породу |

**Тип зв'язку:** Послідовний — ЧНУ: матеріалознавчі обмеження → СЄУ: дизайн у межах обмежень

---

## 📊 3. Стратегічна Роль СЄУ в Архітектурі Партнерств

```
           ┌──────────────────────────────────────────────────────┐
           │                 Silken Net (IP Owner)                 │
           │              System Integration & Tech                │
           └──────────────┬───────────────────┬───────────────────┘
                          │                   │
          ┌───────────────┴───────┐   ┌───────┴───────────────┐
          │   HARD SCIENCE LAYER  │   │   BUSINESS LAYER      │
          │                       │   │                        │
          │  ЧНУ   — Фізика/Хімія│   │  СЄУ — Економіка/Право│ ← NEW
          │  ФОТІУС — Кібернетика │   │         Промдизайн     │
          │  ЧДТУ   — Data/RF     │   │         UX/Візуалізація│
          │  ЧІПБ   — Пожежна б-ка│   │                        │
          │  ЧМА    — Біохімія    │   │                        │
          └───────────────────────┘   └────────────────────────┘
```

**Принцип розподілу:**
- Hard Science Layer (5 ВНЗ): генерують ДАНІ та МОДЕЛІ (лабораторні результати, формальні верифікації, статистичні аналізи)
- Business Layer (1 ВНЗ — СЄУ): перетворює дані у АРТЕФАКТИ ДЛЯ ІНВЕСТОРІВ (whitepaper, legal opinion, accounting framework, design mockup)

Це означає, що СЄУ є "downstream consumer" результатів інших 5 ВНЗ. Вона не дублює їхню роботу, а **переводить наукові результати мовою інвесторів, юристів та дизайнерів**.

---

## 🎓 4. Студентські Роботи СЄУ

| Рівень | Тема | Науковий керівник | Кодбейс-інтеграція |
|--------|------|-------------------|--------------------|
| **Магістерська** | "Макроекономічне моделювання токеноміки Nature-as-a-Service" | Чудаєва | `ProtocolParameters.sol`, `BlockchainMintingService` |
| **Магістерська** | "ESG Accounting Framework для блокчейн-верифікованих вуглецевих кредитів" | Ус | `KlimaDao::RetirementService`, `esg_retired_balance` |
| **Магістерська** | "Правові аспекти токенізації Real World Assets у контексті MiCA" | Аблязов Д. | `HadronComplianceService`, NaaS Term Sheet |
| **Магістерська** | "Управління мультидисциплінарними консорціумами за моделлю Потрійної Спіралі" | Аблязова Н. | `07_03`, Horizon Europe заявка |
| **Бакалаврська** | "Промисловий дизайн антивандальної капсули для лісового IoT" | Денисенко | `01_01` Деталь 4, PEEK-радом |
| **Бакалаврська** | "UX-дизайн B2B дашборду для ESG-інвесторів" | Теліженко | Phlex components, `04_04` |
| **Бакалаврська** | "Аудит методології D-MRV: мапінг delta_t на Verra VM0003/VM0047 (ISO 14064-2/-3 backbone)" | Гедз | `05_02`, Proof of Growth Pipeline |
| **Курсова** | "Sensitivity analysis юніт-економіки IoT-кластера" | Ус | `07_02`, BOM |
| **Курсова** | "Порівняльний аналіз SCC та Verra VCU" | Чудаєва | `05_03`, Tokenomics |

---

## 🚀 5. Стратегія Входу

### Відмінність від інших ВНЗ

СЄУ — **приватний університет**. На відміну від державних ЧНУ/ЧДТУ/ЧІПБ, СЄУ має більш гнучку структуру прийняття рішень та зацікавленість у прикладних проєктах, що підвищують рейтинг ВНЗ. Ключова мотивація:

1. **Для ректорату:** Silken Net = реальний deep-tech кейс для студентських робіт + перспектива Scopus-публікацій + Horizon Europe грант = рейтинг ВНЗ
2. **Для кафедри економіки (Чудаєва/Ус):** Web3-токеноміка + ESG = новий актуальний напрям досліджень, якого бракує в класичній українській економічній науці
3. **Для кафедри права (Аблязов Д.):** RWA-токенізація + MiCA = передова юридична проблематика для публікацій у Journal of Financial Regulation (Q1)
4. **Для кафедри дизайну (Денисенко/Теліженко):** Промисловий дизайн біомімікрічної капсули = портфоліо для міжнародних конкурсів промислового дизайну (Red Dot, iF Design Award)

### Фрейм розмови

> _"Шановна Іє Борисівно, я — CTO проєкту Silken Net, першої в Україні децентралізованої платформи моніторингу лісів з токенізацією вуглецевих кредитів. Ми маємо 5 академічних партнерів у Черкасах для верифікації хардверу та алгоритмів, але жоден з них не має компетенції в макроекономіці токенів, корпоративному ESG-обліку та правовій архітектурі RWA. Це саме зона СЄУ. Пропоную партнерство: ваші економісти та юристи допоможуть нам створити Economic Whitepaper та Legal Framework для інституційних інвесторів. Натомість — готовий R&D-полігон для магістерських робіт, спільні публікації Scopus та участь у грантах Horizon Europe."_

---

## 🤖 6. Pitch-документ для ректора СЄУ (UNI.8)

> Структурований pitch для першої зустрічі з ректором СЄУ Чудаєвою І.Б. Акцент: чому СЄУ — критичний 6-й партнер (закриває economic + legal gap).

### Pitch Outline (10 хвилин)

**Вступ (1 хв):**

> *"Шановна Іє Борисівно, дякую за зустріч. Я — Олексій Лукін, CTO міжнародного deep-tech проєкту Silken Net. Ми будуємо першу в світі систему реального часу для моніторингу здоров'я лісів з автоматичною верифікацією вуглецевих кредитів через блокчейн. У нас 5 академічних партнерів у Черкасах (ЧНУ, ЧДТУ, ЧІПБ, ЧМА), але жоден з них не покриває макроекономіку, юридичну архітектуру та промисловий дизайн. Саме тому я прийшов до СЄУ."*

**Блок 1 — Проблема та ринок (2 хв):**

```
Voluntary Carbon Market = $2B (2023) → $50B (2030, McKinsey)
Проблема: 90% carbon credits — без digital verification (D-MRV)
  → Greenwashing, подвійний облік, відсутність прозорості
  → Інституційні інвестори (EU Taxonomy, CSRD) потребують ВЕРИФІКОВАНИХ кредитів

Silken Net = Digital MRV (Measurement, Reporting, Verification):
  → Інструментуємо РЕПРЕЗЕНТАТИВНІ КЛАСТЕРИ, а не кожне дерево лісу:
    1 кластер (MVFC ≈ 100 вузлів + 1 Queen, ~$5,100, 07_02) на репрезентативну
    ділянку/гектар. Щільні per-tree дані кластера = ground truth, що КАЛІБРУЄ
    супутникову екстраполяцію (CNN + NDVI, Бушин 08_02) на решту насадження.
  → CAPEX масштабується з кількістю гектарів/кластерів, а НЕ з кількістю дерев
    (інакше 1M дерев × ~$50 = $50M — нереалістично; кластерна вибірка ÷100)
  → Дані верифікуються через 4 рівні (IoTeX ZK-proof → Chainlink Oracle → on-chain)
  → Carbon credits (SCC) мінтяться автоматично на Polygon (ERC-20)
  → Інституційні інвестори отримують ЮРИДИЧНО ЧИСТИЙ carbon asset
```

> **Note для економіста (anti-«перегрів»):** на питання «скільки коштує
> моніторинг 1M дерев?» відповідь — НЕ «1M датчиків × $50». Silken Net застосовує
> macro-micro модель: інструментована вибірка кластерів + супутникова
> екстраполяція (08_02). Юніт-економіка рахується на кластер/гектар (07_02),
> що робить CAPEX керованим і фінансову модель реалістичною.

**Блок 2 — Що побудовано (1 хв):**

```
✅ Backend: Rails 8.1 + PostgreSQL — TRL 8 (production-ready)
✅ Smart Contracts: 6 контрактів на Solidity, 178 тестів, аудит Slither
✅ Firmware: STM32WLE5JC, 137+ тестів, LoRa mesh, AES-128-ECB (transitional → CCM)
✅ Web3 Pipeline: 12 блокчейн-мереж (Polygon, Ethereum, Solana, Celo...)
✅ Hardware design: Ti-6Al-4V gyroid, EBFC Gen 2.0 (**TRL 4**, Zero-Lab L1-L4 PASSED), BQ25570 MPPT
❌ ВІДСУТНЄ: Economic Whitepaper, Legal Framework, ESG Accounting, Industrial Design
   → Це саме зона СЄУ
```

**Блок 3 — 5 напрямів для СЄУ (3 хв):**

```
1. МАКРОЕКОНОМІКА ТОКЕНОМІКИ (Чудаєва І.Б.)
   → Обґрунтування Proof of Growth: чи не інфляційна емісія SCC?
   → Stress-testing: 1M/10M дерев, bull/bear сценарії
   → Порівняння SCC vs Verra VCU — для whitepaper
   → Результат: Economic Whitepaper для seed-раунду ($500K-2M)

2. ESG-ОБЛІК (Ус Г.О.)
   → Бухгалтерський фреймворк: як провести SCC через МСФЗ?
   → Dynamic Tax 2% → класифікація для податкової
   → Solana/Celo мікро-нагороди → як задекларувати?
   → Результат: Accounting Bridge — шаблон для корпоративних клієнтів

3. ПРАВОВА АРХІТЕКТУРА RWA (Аблязов Д.Е.)
   → MiCA compliance для SCC-токена (ЄС регулятор)
   → ERC-3643 (Polygon Hadron) — KYC/AML framework
   → NaaS контракти: Term Sheet + MSA шаблони
   → Результат: Legal Framework — закриває BLOCKER-1 з 07_01

4. ПРОМИСЛОВИЙ ДИЗАЙН (Денисенко, Теліженко)
   → PEEK-радом: біомімікрія під кору дерева (IP68)
   → Press-fit ергономіка Zero-Touch Assembly
   → Результат: портфоліо для Red Dot / iF Design Award

5. UX/ВІЗУАЛІЗАЦІЯ (Теліженко)
   → B2B дашборд для ESG-інвесторів (трансформація кіберпанк → premium)
   → Financial reports UI: carbon absorption, treasury balance
   → Результат: інвесторський дашборд для demo та seed pitch
```

**Блок 4 — Що отримає СЄУ (2 хв):**

```
📈 Для рейтингу ВНЗ:
  → 5+ спільних публікацій Scopus (макроекономіка, право, ESG)
  → 4 магістерські + 2 бакалаврські + 2 курсові (повний pipeline)
  → Horizon Europe грантова заявка (спільна з 5 іншими ВНЗ)

🎓 Для студентів:
  → Робота з реальним deep-tech проєктом (не абстрактна курсова)
  → Досвід: Solidity, Polygon, Chainlink, ESG-reporting
  → Публікація → конкурентна перевага на ринку праці

💼 Для кафедр:
  → Новий актуальний напрям: Web3 токеноміка + ESG accounting
  → Юридична проблематика: MiCA, RWA, ERC-3643 — передовий edge
  → Промисловий дизайн: реальний продукт → міжнародні конкурси

🤝 Для СЄУ як інституції:
  → СЄУ = "економічний та юридичний backbone" глобальної climate-tech платформи
  → Унікальна позиція серед українських ВНЗ
```

**Заключення та CTA (1 хв):**

> *"Іє Борисівно, пропоную наступний крок: підписати Меморандум про співпрацю між СЄУ та Silken Net. Потім організувати 3 зустрічі: (1) з Вами та Ус Г.О. — макроекономічна модель, (2) з Аблязовим Д.Е. — правова архітектура, (3) з Денисенком — промисловий дизайн PEEK-капсули. Це не коштуватиме СЄУ жодних грошей — лише інтелектуальний ресурс. А результат — спільні Scopus-публікації та грант Horizon Europe."*

### Матеріали для зустрічі

| Матеріал | Формат | Статус |
|----------|--------|--------|
| Pitch presentation (цей документ) | PDF/Google Slides | 🤖 ✅ Готовий |
| One-pager: Silken Net для ректорату | PDF A4 | 👤 Підготувати |
| GitHub repository (публічний) | URL | ✅ `github.com/Alexey-Lukin/silken_net` |
| System Architecture Diagram | PDF/PNG з `00_01` | ✅ Існує |
| Tokenomics Summary | PDF з `05_03` | ✅ Існує |
| Список 5 академічних партнерів | Таблиця | ✅ У `08_01`-`08_06` |

> **Cross-ref:** [00_08 UNI.8](00_08_Action_Plan_Tracker) — підготовка pitch для ректора СЄУ ✅
