# 00_01: System Architecture and 12-Chain Pipeline

## 🎯 Мета

Зафіксувати 8-рівневу кіберфізичну архітектуру екосистеми Gaia 2.0 (Silken Net) та повний 12-крокового конвеєр Proof of Growth — від біохімічної реакції в дереві до криптографічної фіналізації в Ethereum L1. Цей документ є базовою конституцією для маршрутизації даних, але не містить політику резервування — для неї див. [`00_02_Resilience_and_Failover_Policy`](00_02_Resilience_and_Failover_Policy).

---

## ✅ Статус

- **Поточний TRL:** TRL 4 — Архітектура затверджена, інтеграційні компоненти тестуються локально (EBFC TRL 3→4 PASSED 2026-05-25 через Zero-Lab in-silico pipeline; програмні домени рухаються паралельно через HIL-симулятори, [`09_02`](09_02_TRL_Matrix_HIL_and_Beyond)). Відкрите System-gating (Module 01 chemistry, FW.2) → [09_06](09_06_Action_Plan_Tracker).
- **Оновлення:** Проведено півот апаратної частини. Повністю видалено рівень електрокінетики (Streaming Potential / LTC3108). Затверджено нову біохімічну базу (EBFC).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [07_01_Vision_Mission_and_Roadmap](07_01_Vision_Mission_and_Roadmap) | Бізнес-візія та slashing |
| [00_02_Resilience_and_Failover_Policy](00_02_Resilience_and_Failover_Policy) | Failover та Web3 fallback |
| [01_01_Coaxial_Gyroid_Topology_and_PEEK](01_01_Coaxial_Gyroid_Topology_and_PEEK) | Біомеханіка та тризонний анкер |
| [02_01_Hardware_Architecture_and_BOM](02_01_Hardware_Architecture_and_BOM) | Апаратура та BOM |
| [03_01_Firmware_Lifecycle_and_DMA](03_01_Firmware_Lifecycle_and_DMA) | Прошивка та Edge AI |
| [04_01_Data_Models_and_Entities](04_01_Data_Models_and_Entities) | Backend та моделі даних |
| [05_01_Multichain_Architecture](05_01_Multichain_Architecture) | Web3 мультичейн |
| [06_01_Deployment_Kamal_Terraform](06_01_Deployment_Kamal_Terraform) | DevOps та деплой |
| [07_02_Nature_as_a_Service_Contracts](07_02_Nature_as_a_Service_Contracts) | Бізнес-контракти NaaS |
| [09_06_Action_Plan_Tracker](09_06_Action_Plan_Tracker) | **Відкриті блокери** (SSOT): System TRL gated by Module 01 chemistry (HW.*) + firmware (FW.2); софт розв'язано через HIL (`09_02`) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Технічна Специфікація: 8 Рівнів Gaia 2.0](#-1-технічна-специфікація-8-рівнів-gaia-20)
- [2. Redis Infrastructure — DB Isolation](#-2-redis-infrastructure--db-isolation)
- [3. Gaia 2.0 Scaling Roadmap — Фрактальна Топологія](#-3-gaia-20-scaling-roadmap--фрактальна-топологія)
- [4. Анатомія Кіберфізичного Стану — Повний 12-Крокової Конвеєр](#-4-анатомія-кіберфізичного-стану--повний-12-крокової-конвеєр)
- [5. Ключові Параметри Системи](#-5-ключові-параметри-системи)
- [6. Топологія Мережі (High-Level)](#-6-топологія-мережі-high-level)
<!-- TOC:AUTO:END -->

---

## 📎 1. Технічна Специфікація: 8 Рівнів Gaia 2.0

Система працює за принципом безперервного, детермінованого конвеєра (Zero-Trust pipeline). Дані рухаються знизу вгору.

### 🌳 Рівень 1: Біофізика та Механіка (The Root)
- **Сутність:** **Тризонний коаксіальний анкер** (`01_01`): Zone 1 (анод-гіроїд Ti-6Al-4V 30–50 мм у заболоні) + Zone 2 (PEEK-терморозрив 40–60 мм — електричний ізолятор + thermal break + механічний демпфер) + Zone 3 (катодний фланець Ti-6Al-4V на межі кори та повітря з PTFE-GDL мембраною). Загальна довжина ~80–120 мм. Встановлення — Flush Mount step drilling + microfrezing (`01_04` §3).
- **Енергетика:** Ензимний біопаливний елемент (EBFC) — Gen 2.0 baseline (`01_03`):
  - **Анод (Zone 1, у ксилемному соку):** Одношаровий стек — деглікозильована **dgrFAD-GDH** (з *Glomerella cingulata* або *Aspergillus*) + Os redox polymer + fMWCNT у захисній **Genipin-Chitosan-CNC** матриці (нетоксичний рослинний зшивач + псевдопластика проти тигмоморфогенезу) + **Nafion-g-PSBMA** цвітеріонна мембрана (σ = 45.2 мС/см, UCST winter-lock @ 5°C). Без H₂O₂, без CODIT-тригерів.
  - **Катод (Zone 3, на межі кори/повітря):** Гібрид **Laccase + ZIF-нанозим** (nCoCuCeZIF/Lac або nCuCeAuZIF/Lac) на fMWCNT — DET через мультиметалічні Cu/Ce/Co центри (емуляція T1/T2/T3), ×10 power density, +7.5% з 0.25 М NaCl, ORR атмосферного O₂ крізь PTFE-GDL (0.2–1.0 µm пори).
- **Вихідна напруга:** >500 mV безпосередньо з метаболізму дерева. Жодних зовнішніх дротів.

### ⚙️ Рівень 2: Апаратне Забезпечення (The Capsule)
- **Сутність:** Герметична капсула з PCB, що підключається до анкера наосліп через Pogo Pins.
- **Живлення:** BQ25570 MPPT + Іоністор (0.47F / 5.5V).
- **Активація:** Акустичний п'єзо-тригер для апаратного пробудження при вібраціях.

### 🧠 Рівень 3: Прошивка та Edge AI (The Brain)
- **Ядро:** STM32WLE5JC (ARM Cortex-M4). Стан "Нульового Лагу" — `STOP2 RTC-only` mode: **300 nA** sleep current (SRAM2 retention OFF, RTC + backup registers ON). Це обов'язкова умова позитивного енергобалансу EBFC + 0.47F (`02_03 §9.6 Сценарій C` — затверджена архітектура v3).
- **Сенсорика:** Апаратний DMA-буфер мікрофона.
- **TinyML:** Нейромережа на пристрої для класифікації аудіо (Тиша / Вітер / Пилка).
- **Математика:** mruby VM розраховує Атрактор Лоренца (гомеостаз) на базі часу заряду іоністора.
- **Безпека:** Апаратне шифрування — AES-128 на LoRa-каналі (post-ARCH.42), AES-256-CBC на CoAP-каналі Queen→Rails.

### 📡 Рівень 4: Мережа (The Veins)
- **Протокол:** LoRa mesh 868 МГц (custom TTL-based, DEFAULT_TTL=3). Binary payload 21 bytes (4 DID + 1 RSSI + 16 encrypted).
- **Топологія:** Directed Mesh (Солдати передають пакети через сусідів).
- **Шлюз (Королева):** Агрегує пакети та відправляє їх у хмару (опціонально через Starlink Direct-to-Cell).
- **Резерв:** Helium Network (HNT) як fallback при втраті Queen — будь-який роутер Helium у радіусі 15 км ловить пакет ([деталі → 02_05](02_05_Queen_Hardware_and_Starlink), політика — [`00_02 §Queen Failover`](00_02_Resilience_and_Failover_Policy)).

#### Проблема Рандеву (Rendezvous Problem)

Фундаментальний виклик будь-якої енергозбережної сенсорної мережі: якщо Солдат прокинеться, "вистрілить" пакетом в ефір і знову засне, а приймач у цей момент теж спить — пакет розчинється в ефірі. Радіохвилі не вміють "висіти" в повітрі й чекати. Щоб приймач зловив дані, його радіомодуль SX1262 має бути ввімкнений у режим прийому (RX mode), а це споживає 4–5 мА — катастрофічно багато для біобатарейки EBFC.

**Поточна архітектура (TRL 6)** вирішує Рандеву на одному рівні:

| Рівень | Механізм | Статус |
|--------|----------|--------|
| **L1: Зона Королеви** | Queen `Radio.Rx(LORA_RX_INFINITE)` — ніколи не спить, приймач SX1262 завжди активний. Живиться від сонячної панелі/акумулятора. Будь-який Солдат у радіусі 150–200 м може передати в будь-яку секунду — Королева завжди зловить. | ✅ Реалізовано |
| **L2: Синхронні Вікна (TDMA)** | Координоване пробудження вузлів за RTC-розкладом. Queen beacon → Time Sync → спільне "Вікно Зв'язку" кожні 15 хвилин (2 секунди RX). Усуває необхідність постійного прослуховування. | ❌ Не реалізовано ([ARCH.26](09_06_Action_Plan_Tracker)) |
| **L3: CAD (Channel Activity Detection)** | Апаратна фіча SX1262: вузол робить короткий CAD-«нюх» ефіру на наявність LoRa-преамбули. **Cadence — НЕ «кожну секунду»** (див. ⚠️ нижче): CAD прив'язаний до TDMA-вікон L2 або грубого інтервалу. PANIC mode (chainsaw) ініціюється **відправником** через extended-preamble (preamble sampling), а не постійним прослуховуванням приймача. | ❌ Не реалізовано ([ARCH.26](09_06_Action_Plan_Tracker)) |

> **⚠️ Енергетична корекція CAD (2026-05-28):** Попереднє «прокидатися ~2 мс кожну секунду, ~0.0001% заряду» **недооцінювало вартість** і енергетично нежиттєздатне для µW-вузла на EBFC. Реальний цикл — це не лише радіо: wake MCU зі STOP2 → init SPI → конфіг SX1262 на CAD → очікування результату → знову сон. Активна фаза ≈ кілька мс при ~5 мА (MCU+SX1262), тобто десятки–сотні µJ **на один цикл**. ×86,400 циклів/добу → одиниці джоулів/добу, що **багатократно перевищує** і добовий харвест EBFC, і запас EDLC (½·0.47F·3.3² ≈ 2.56 J). Тому CAD НЕ можна робити щосекунди. Правильно: CAD **у синхронних TDMA-вікнах** (L2, кожні ~15 хв) або з грубим інтервалом; для миттєвого PANIC — **відправник** подовжує преамбулу довше за період сну приймача (LoRa preamble sampling), і низько-duty-cycle CAD-приймач її зловить. Енергобюджет CAD переглянути окремо ([ARCH.26](09_06_Action_Plan_Tracker)).

**Поточний mesh relay (Soldier↔Soldier)** працює стохастично: Солдат А TX → якщо Солдат Б випадково слухає ефір у своїх 600 мс RX-вікна (Phase 4.5) → пакет ретранслюється. Без TDMA/CAD mesh relay **ненадійний** за межами прямої видимості Королеви.

> **Деталі реалізації:** [03_01 Phase 4.5](03_01_Firmware_Lifecycle_and_DMA) (RX Window + Проблема Рандеву), [03_02 §1](03_02_Queen_Gateway_Firmware) (LoRa Reception)

### 🖥️ Рівень 5: Серверне Ядро (The Engine)
- **Стек:** Ruby on Rails 8.1 Omakase, PostgreSQL, Redis, Sidekiq (37 Workers).
- **Деплой:** Kamal, Docker, Prometheus (Observability).
- **Роль:** Декодування (L3), маршрутизація API (31 Controllers), управління бізнес-логікою контрактів (Nature-as-a-Service).
- **Вхідний шар IoT:** CoAP/UDP listener (порт 5683) — для планетарного масштабу потребує Ingress Proxy перед Rails ([деталі → 06_01](06_01_Deployment_Kamal_Terraform)).

### 🔐 Рівень 6: Мережі Даних та Верифікації (The Truth)
- **peaq Network:** Надання кожному дереву Machine DID паспорта.
- **IoTeX W3bstream:** Генерація ZK-proofs, що доводять походження даних з реального кремнію (Real Silicon).
- **Streamr & Filecoin:** P2P трансляція телеметрії та вічне зберігання на IPFS.

### 💰 Рівень 7: Фінансова Логіка (The Ledger)
- **Primary Chain:** Polygon EVM. Смарт-контракти для мінтингу SCC (Silken Carbon Coin) та SFC (Governance).
- **Оракул:** Chainlink DON (передає верифіковані бали росту з Rails у Polygon).
- **Паралельні фінанси:** Solana (мікро-нагороди лісникам), Celo (ReFi для громад), KlimaDAO (спалювання ESG).
- **Compliance:** Polygon Hadron (KYC/KYB за стандартом ERC-3643).

### 🗳️ Рівень 7.5: Governance DAO (The Parliament)
- **Контракти (Polygon):** `SilkenGovernor.sol` (OZ Governor + GovernorVotes + GovernorTimelockControl + GovernorCountingSimple + GovernorVotesQuorumFraction 4%), `SilkenTimelock.sol` (48h мінімальна затримка), `ProtocolParameters.sol` (on-chain registry 13 параметрів: Lorenz σ/ρ/β/dt/iterations/z_min/z_max/z_target, tokenomics, slashing).
- **Voting Power:** SFC (ERC20Votes) — snapshot-based `getPastVotes()` + votingDelay 43200 блоків (~1 день на Polygon) для Flash Loan defense.
- **Pipeline:** SFC Holders → `SilkenGovernor` (propose/vote) → `SilkenTimelock` (48h delay) → `ProtocolParameters` (setParameter) → `Governance::ParameterSyncWorker` (щоденний sync on-chain → `SystemParameter` модель).
- **CI/CD:** `solidity_audit.yml` — Foundry build/test/coverage + Slither static analysis на кожен push/PR.

### 🏛️ Рівень 8: Фіналізація (The Anchor)
- **Стек:** Ethereum L1.
- **Роль:** Щотижневе закріплення кореня стану (State Root — 32-byte SHA-256 hash) всієї економіки Gaia 2.0. Гарантія Rollup-рівня від катастрофічних збоїв сайдчейнів.

---

## 🗄️ 2. Redis Infrastructure — DB Isolation

Система використовує єдиний Redis-інстанс із **ізоляцією через логічні бази даних**:

| БД | Призначення | ENV-змінна | Gem |
|----|-------------|-----------|-----|
| **DB 0** | Sidekiq черги задач та планувальник | `REDIS_URL` | `sidekiq` + `redis-client` |
| **DB 1** | Kredis distributed locks (Web3 nonce management) | `KREDIS_REDIS_URL` | `kredis` + `redis` |

### Чому одночасно використовуються `redis` і `kredis` gems?

- **`sidekiq`** (8.x) використовує `redis-client` внутрішньо для черг — він **не потребує** gem `redis`.
- **`kredis`** (Rails high-level Redis data structures) залежить від gem `redis` і надає типізовані проксі (scalars, lists, sets).
- Kredis не має вбудованого distributed lock, тому `config/initializers/kredis.rb` розширює модуль через `Kredis.lock` — crash-safe `SET NX EX` lock із UUID-власністю та атомарним Lua-скриптом звільнення.

### Чому ізоляція DB є критично важливою?

Ізоляція **запобігає витісненню** (eviction) критичних Web3-даних телеметричними чергами:

> При мільйонах IoT-пакетів на годину потік телеметрії (DB 0 — Sidekiq) може заповнити пам'ять Redis, змусивши eviction policy (`allkeys-lru`) видаляти ключі. Якби Web3 nonce locks знаходилися в тій самій базі — вони б видалялися, що призвело б до **EVM nonce collisions** і вразливостей **double-spend** на Polygon. Ізоляція через логічні бази даних усуває цей ризик без додаткових Redis-інстансів.

---

## 🚀 3. Gaia 2.0 Scaling Roadmap — Фрактальна Топологія

> Поточна плоска LoRa-меш архітектура задихнеться від колізій та затримок вже на кількох тисячах вузлів. Для мільйонів дерев необхідна **фрактальна топологія**.

### Трьохрівнева ієрархія вузлів (The Fractal Stack)

> **🌳 Біонічний rename (2026-05-22):** Рівень L2 перейменовано з "Sergeant/Сержант" на **"Conductor/Провідник"** (історично "Hub Tree" — найстаріше домінуюче дерево локального кластера). Це відображає природну Scale-Free Network лісу та акцентує **передачу енергії та інформації**, а не військову ієрархію. Технічна структура (3-рівнева топологія, TDMA, CAD Preamble) залишається без змін.

```
L3: Queen Gateways (Mother Tree — Супер-вузли)
    LoRa SF12 + Starlink/LTE backbone
    ├── Inter-cluster relay (Queen ↔ Queen Backhaul Mesh)
    └── Cloud uplink (CoAP → Rails)
         │
L2: Conductor Nodes (Провідник — Hub Tree, Cluster Head) [МАЙБУТНЄ]
    Сильне зріле дерево в центрі взводу; високий потенціал EBFC + LiFePO4
    ├── Агрегує 50–200 Солдатів у "Звіт про стан кластера"
    ├── Замість 100 пакетів → 1 стиснений summary
    └── Динамічно обирається на основі `vcap` та якості зв'язку
         │
L1: Soldier Nodes (Regular Tree — Листя) — поточна архітектура
    STM32WLE5JC + EBFC (0.47F), STOP2 (300 nA)
    └── Передає стиснутий стан (lambda-exponent) найближчому Провіднику
```

**Ключова зміна:** Солдати більше не спілкуються з усім світом — лише з найближчим Провідником. Зменшення радіочастотних колізій на порядки.

> **Передумова для L2 Conductor:** Рівень Провідників потребує вирішеної Проблеми Рандеву між Солдатом і Провідником. Провідник не може бути always-on (як Queen) — його живлення обмежене, хоча й більше ніж у Солдата. Рішення: TDMA Синхронні Вікна (ARCH.26) + CAD Preamble Detection.

### H-LDSE — Ієрархічний Протокол Маршрутизації

Еволюція поточного LDSE-меш для мільйонної мережі:

| Механізм | Поточний LDSE | H-LDSE |
|----------|--------------|--------|
| Таблиця маршрутизації | Всі сусіди (OOM при >1000 вузлів) | Лише 2–3 хопи (локальна адресація) |
| Адресація | DID-based | Геохешинг (ID = координати) |
| Пошук шляху | TTL broadcast | Градієнтний потік до найближчої Queen |
| Частотні рівні | Один канал | Spatial Multiplexing (L1 → канал A, L2 → канал B) |

**Геохешинг:** Кожен супер-кластер отримує ID на основі координат. Пакет не шукає маршрут — він тече в бік зменшення градієнта до найближчої Королеви. Усуває broadcast storm.

> **⚠️ Розмежування рівнів (2026-05-28): геохешинг — це здатність L2 Conductor, НЕ L1 Soldier.** Поточна прошивка ([`03_01`](03_01_Firmware_Lifecycle_and_DMA), [`08_02`](08_02_Cybernetic_and_Mathematical_Validation)) — наївний **TTL-flood relay** (PANIC_TTL=5, DEFAULT_TTL=3) без маршрутизації. Градієнтний геохешинг вимагає, щоб вузол оперував координатами та сусідським градієнтом — це покладається на **L2 Conductor** (має RTC, більший енергобюджет, відомі координати). **L1 Soldiers залишаються TTL-flood вузлами**, які просто «кричать» у радіусі свого найближчого L2 Conductor (відповідно до фрактальної ієрархії вище). H-LDSE — це цільова еволюція рівня L2, а не зміна поведінки L1.

**Spatial Multiplexing:** L1 та L2 працюють на різних частотних підканалах 868 MHz ISM — усуває міжрівневі колізії (inter-tier interference).

### Edge Data Fusion — Стиснення Інформації

Замість передачі повних координат атрактора Лоренца, вузол передає лише **lambda-exponent** (показник хаотичності Ляпунова):

```
Поточний підхід:      16 байт payload → Z-координата Лоренца
Gaia 2.0 підхід:      2 байти lambda → описує стан всього дерева
```

> **Що зберігається:** lambda-exponent (показник Ляпунова) відображає ступінь хаотичності атрактора — достатньо для визначення "норма / стрес / аномалія". **Що втрачається:** абсолютні координати (X, Y, Z) — їх відновлення неможливе без повного ряду. Коли lambda перевищує поріг аномалії (`|λ| > λ_threshold`), Солдат автоматично переходить у режим повного стрімінгу з 16-байт payload — втрата інформації повністю усувається при критичних подіях.

**Event-Triggered Reporting:** "Тиша означає здоров'я":
- Стабільний атрактор → heartbeat раз на добу (1 пакет/24 год)
- Атрактор "зривається" (пожежа / посуха) → безперервний стрімінг (~1 пакет/хв)

Скорочення трафіку в нормальному режимі в ~24× при збереженні повної чутливості до аномалій.

### Network Sharding — Ізоляція Секторів

```
[Нормальний режим]      Cluster A ←→ Cluster B ←→ Cluster C

[Аномалія в Cluster B]  Cluster A | [B isolated] | Cluster C
                                    ↑
                         Вирубка / пожежа → шторм тривожних пакетів
                         не "кладе" сусідні кластери
```

**Queen-to-Queen Backhaul Mesh:** Королеви з'єднані між собою через LoRa SF12. Якщо одна Queen втрачає Starlink → передає дані сусідній Queen через LoRa-магістраль. Деталі — [`00_02 §Queen Failover`](00_02_Resilience_and_Failover_Policy).

### Energy-Aware Routing

Маршрутизація будується не за найкоротшим шляхом, а за **найбільш енергонадлишковим**:

```
Route metric = f(hop_count, remaining_energy, bio_potential)
```

Пакет іде через дерево з найкращим сокорухом (найбільшим біопотенціалом сьогодні) → автоматичне балансування навантаження + екологічна маршрутизація.

### Вимоги до Rails Backend (Gaia 2.0 Scale)

| Компонент | Поточний стан | Gaia 2.0 вимога |
|-----------|--------------|----------------|
| Вхідний шар | CoAP прямо в Rails | Ingress Proxy (Rust/Go) → Kafka/Pub-Sub → Rails consumers |
| БД читання | Primary + Query | Read-Only Replicas для всіх аналітичних запитів та Oracle |
| TinyML навчання | Централізоване | Federated Learning: навчання на кластерах → OTA-оновлення через `OtaPackagerService` |

---

## 🌐 4. Анатомія Кіберфізичного Стану — Повний 12-Крокової Конвеєр

> *"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."*

Цей розділ описує повний життєвий цикл одного "серцебиття" через кіберфізичний стан Silken Net — від моменту, коли дерево "дихає", до миті, коли його внесок закарбовується в Ethereum назавжди.

**12 кроків. 12 мереж. Одна жива система.** Резервування для кожної ланки — [`00_02 §Web3 Chain Fallback`](00_02_Resilience_and_Failover_Policy).

---

### 1. 🌳 Фізичний Дотик — Дерево Дихає

Дерево дихає. Ксилемний сік тече вгору, генеруючи понад 500 мВ завдяки метаболізму глюкози через тризонний анкер (`01_01`): **dgrFAD-GDH + Os** у Genipin-Chitosan-CNC матриці з Nafion-g-PSBMA цвітеріонною мембраною на аноді Zone 1 у заболоні + **Laccase/ZIF-nanozyme** гібридний DET на катоді Zone 3 на межі кори/повітря (Gen 2.0 baseline, `01_03`). BQ25570 MPPT заряджає суперконденсатор 0.47 Ф. Коли напруга досягає порогу — STM32WLE5JC Soldier прокидається зі сну STOP2 RTC-only (**300 нА**, `02_03 §9.6 Сценарій C`).

**Цикл Soldier:**
- Фаза 1: Збір сенсорних даних (температура, імпеданс, акустика, напруга суперконденсатора)
- Фаза 1.5: TinyML-класифікація звуку (тиша / вітер / кавітація / пилка)
- Фаза 2: Упаковка у 16-байтний payload
- Фаза 3: mruby Lorenz attractor → `growth_points` + `bio_status`
- Фаза 4: AES-128-ECB шифрування (transitional, post-ARCH.42; FW.2 target — AES-128-CCM) → LoRa TX (868 МГц)
- Фаза 5: Повернення у глибокий сон STOP2

```
dx/dt = σ(y - x)        σ = 10.0 + acoustic × 0.1
dy/dt = x(ρ - z) - y    ρ = 28.0 + temperature × 0.2
dz/dt = xy - βz          β = 8/3
```

Z-значення — проксі "конвективної інтенсивності" соку — визначає: дерево живе, під стресом або вмирає.

> **Прошивка:** `firmware/soldier/main.c` · **Bio-contract:** `firmware/bio_contracts/bio_contract.rb`

---

### 2. 🏗️ Незнищенне Тіло — Akash Network (Децентралізована Хмара)

Queen-шлюз (STM32 + SIM7070G) збирає LoRa-пакети від до 50 Soldiers, дедуплікує їх за **незашифрованим DID-заголовком** через алгоритм CIFO, загортає батч у CoAP та застосовує AES-256-CBC як **транспортний** шар поверх стільникового/Starlink-каналу.

> **⚠️ Транспорт через Starlink Direct-to-Cell (2026-05-28):** D2C працює за LTE-протоколами (SMS + базовий 4G) через жорсткий **Carrier-NAT**, який може блокувати вхідний UDP (а CoAP — UDP) або змінювати порти. Тому **чистий CoAP/UDP ненадійний** на D2C; архітектура має передбачати фолбек **CoAP-over-TCP** (RFC 8323) або **MQTT-SN**, а Ingress Proxy ([`06_01`](06_01_Deployment_Kamal_Terraform)) — толерувати високий jitter / packet loss супутникового LTE. HIL `realistic_mode` ([`09_02 §4.2`](09_02_TRL_Matrix_HIL_and_Beyond)) моделює ці умови.

> **🔐 Уточнення (2026-05-28): це ВКЛАДЕНЕ (layered) шифрування, НЕ повторне.** Два AES-шари захищають різні скоупи, тож тут немає «подвійного шифрування того ж plaintext» чи MITM:
> - **Внутрішній (E2EE по payload):** Soldier шифрує 16-байтовий сенсорний блок своїм **per-device AES-128** ключем (LoRa). Цей блок лишається зашифрованим **до бекенду** — backend `TelemetryUnpackerService` розгортає внутрішні AES-128 записи per-Soldier ключем (див. [`05_02`](05_02_Proof_of_Growth_Pipeline) §Pipeline B).
> - **Зовнішній (транспорт):** Queen додає **AES-256-CBC** лише як транспортну обгортку CoAP-батча (Queen→Rails). Дедуплікація CIFO потребує лише **cleartext DID** (перші 4 байти пакета), а не вмісту.
> - **Zero-Trust ціль:** внутрішній sensor-payload не має ставати plaintext на Queen. Чи Queen взагалі торкається внутрішнього блоку для edge-логіки — питання **відкладеного детального AES-пасу** (FW.2: AES-128-CCM + MIC; деталі crypto — [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security) / [`03_02`](03_02_Queen_Gateway_Firmware)).

Rails 8.1 backend отримує цей сигнал не на єдиній корпоративній хмарі, а на **Akash Network** — децентралізованому ринку обчислень. Жодна компанія не може вимкнути кіберфізичний стан. Провайдери змагаються за деплой, система автоматично мігрує у разі відмови одного.

```
Soldier (inner AES-128, per-device) → Queen (CIFO dedup за cleartext DID;
  + outer AES-256-CBC transport) → CoAP PUT → Akash (Rails) → unwrap inner AES-128
```

> **Worker:** `UnpackTelemetryWorker` (черга `uplink`, найвищий пріоритет)
> **Service:** `TelemetryUnpackerService` (декодування 21-байтного бінарного пакету)
> **Infra:** `deploy/akash/deploy.yaml` (SDL 2.0 deployment manifest)

---

### 3. 📡 Голос Лісу — Streamr (P2P Real-Time Data)

Необроблений телеметричний сигнал миттєво транслюється в peer-to-peer ефір **Streamr**-мережі. Будь-хто у світі може підписатися на серцебиття лісу з нульовою затримкою.

Трансляція неблокуюча — помилка публікації Streamr ніколи не зупиняє критичний фінансовий конвеєр.

```ruby
# Streamr::BroadcasterService
payload = {
  tree_id: tree.id,
  peaq_did: tree.peaq_did,
  z_value: telemetry.lorenz_z,
  bio_status: telemetry.bio_status,
  alerts: active_alerts
}
```

> **Worker:** `StreamrBroadcastWorker` (черга `low`, retry: 3)
> **Service:** `Streamr::BroadcasterService`

---

### 4. 🪪 Паспорт — peaq DID (Machine Identity)

Система верифікує криптографічний Decentralized Identifier дерева — його машинний паспорт, зареєстрований у мережі **peaq**.

```
did:peaq:0x{SHA256(hardware_identifier + tree_id + created_at)[0:40]}
```

DID доводить: це не підроблений сенсор, не програмний емулятор, не відтворений пакет. Це конкретний живий організм із конкретним UID STM32, записаним у кремній на заводі.

> **Worker:** `PeaqRegistrationWorker` (черга `web3`, retry: 5)
> **Service:** `Peaq::DidRegistryService`

---

### 5. 🔬 Абсолютна Істина — IoTeX W3bstream (ZK-Proofs) + Математика Лоренца + CID witness

**IoTeX W3bstream** генерує zero-knowledge proof того, що:
1. Телеметрія прийшла з **реального кремнію** (верифікація апаратного підпису)
2. Математика атрактора Лоренца підтверджує **гомеостаз** дерева
3. **Merkle-корінь архіву (`archive_root`)** є частиною ZK-witness — кожне дерево доводить inclusion свого payload у спільний корінь (§5.1), гарантуючи, що дані, які мінтить Polygon на кроці #8, посилаються на той самий незмінний Filecoin-архів (крок #11), і неможливо підмінити archive ex-post.

Серверний `SilkenNet::Attractor` незалежно обчислює те саме Z-значення у **Float64 (IEEE 754 double)** — **бітово ідентично** firmware mruby після [FW.7] (раніше було BigDecimal, що давало інший Z після 250 ітерацій). Це і дає крос-платформну детермінованість та юридичну аудитопридатність.

> Lorenz-константи (σ/ρ/β, clamps, dt, iterations) — **SSOT [`03_04 §4.1`](03_04_mruby_Lorenz_Attractor)**, не дублюються тут. Серверний `SilkenNet::Attractor` (Float64) рахує бітово ідентично firmware mruby (`8.0/3.0`, [FW.7]).

> **DCI як anti-fraud сигнал:** за бітової ідентичності Z (вище) розбіжність device↔server Z — **реальний сигнал тамперу**, а не «шум флоат-хаосу», але сама по собі вона НЕ запускає незворотних фінансових наслідків. Політика (потрібен 2-й некорельований сигнал → категорія C) і точний механізм незакритих загроз — [`05_05 §6`](05_05_Slashing_and_Risk_Policy); механіка перевірки — [`05_02 §Dual Computation Integrity`](05_02_Proof_of_Growth_Pipeline).

#### 5.1 CID як witness у ZK-proof (data integrity bridge до Filecoin)

> ⚠️ **Архітектурне посилення (2026):** Раніше Filecoin/IPFS pin (крок #11) відбувався **після** мінту в Polygon (крок #8) — це означало, що блокчейн-транзакція не мала криптографічного зв'язку з архівом. Зловмисник міг ex-post підмінити archive у Pinata (надавши новий CID), і ніхто би не помітив, що SCC-token насправді посилається на інший набір даних.

> **⚠️ Архітектурна корекція (2026-05-28): batch-CID НЕ може бути witness для per-device ZK-proof.** W3bstream доводить ZK-факт для **окремого** пристрою (`device_uid`, його Z). Якщо witness — це CID цілого batch (з `telemetry_log_ids` багатьох дерев), то: (а) CID змінюється, щойно в batch потрапляє будь-який інший лог; (б) per-device proof, що містить batch-CID, не доводить криптографічно, що payload САМЕ цього дерева включений в архів — лише що пристрій «знав» CID. Рішення — **Merkle-дерево**: листя = індивідуальні per-tree payload'и, корінь = `archive_root` (= те, що пінить Filecoin), і кожне дерево несе **Merkle inclusion proof** свого листа в корінь.

**Виправлення (Merkle-based):** archive стає масивом індивідуальних payload'ів; `archive_root` — Merkle Root над ними. Per-device ZK-witness містить **лист цього дерева + inclusion proof**:

```ruby
# Iotex::W3bstreamVerificationService — пропозиція E.60 (revised)
# 1) Per-tree leaf — детермінований CID індивідуального payload
leaf_payload = {
  telemetry_log_id: log.id,
  device_uid: tree.device_uid,
  z_value: log.z_value,
  bio_status: log.bio_status,
  created_at: log.created_at
}.to_json
leaf_cid = Filecoin::CidGenerator.cidv1(leaf_payload)   # multihash sha256 → base32

# 2) Batch Merkle Root над листям усіх дерев батча
leaves       = batch.map { |l| Filecoin::CidGenerator.cidv1(leaf_for(l)) }
archive_root = MerkleTree.root(leaves)                   # = archive_cid (batch-level)
inclusion    = MerkleTree.proof(leaves, index_of(log))   # шлях листа → корінь

# 3) Per-device witness доводить включення СВОГО листа у спільний корінь
zk_witness = {
  device_uid:     tree.device_uid,
  attractor_z:    server_z_value,
  lambda_exp:     lyapunov_exponent,
  leaf_cid:       leaf_cid,
  merkle_proof:   inclusion,
  archive_root:   archive_root   # ← стабільний корінь батча
}
proof = Iotex.generate_zk_proof(zk_witness)
log.update!(zk_proof_ref: proof.id, archive_cid: archive_root, merkle_leaf: leaf_cid)
```

На кроці #8 (Polygon mint) `archive_root` передається у `mint()` як `bytes32` metadata. На кроці #11 (Filecoin) `FilecoinArchiveWorker` пінить масив листя — обчислений Merkle Root має збігатися з `archive_root`, інакше worker fail-fast і запис іде в `manual_review`. Кожне дерево залишається незалежно верифіковним через `merkle_proof` (O(log n)), а додавання інших логів змінює лише корінь — усі proof'и одного батча посилаються на той самий `archive_root`. Це форсує **bidirectional integrity** між Polygon SCC і Filecoin archive **на рівні окремого дерева**.

> **Worker:** `IotexVerificationWorker` (черга `web3`, retry: 5)
> **Service:** `Iotex::W3bstreamVerificationService` · `SilkenNet::Attractor` · `Filecoin::CidGenerator` (новий, E.60)

---

### 6. ⚡ Нервовий Імпульс — Chainlink (Decentralized Oracle)

Децентралізований оракул **Chainlink** бере цей ZK-верифікований доказ і перекидає міст до блокчейну. Це не один бекенд, що викликає `mint()` — це децентралізована мережа оракулів, яка незалежно верифікує та диспатчує дані.

**Guard clause:** Диспатч Chainlink відбувається ЛИШЕ якщо `verified_by_iotex? == true`. Немає ZK-proof — немає оракула. Немає оракула — немає мінтингу.

```ruby
# Chainlink::OracleDispatchService
payload = {
  peaq_did: tree.peaq_did,
  lorenz_state: attractor_z_value,
  zk_proof_ref: telemetry.zk_proof_ref,
  tree_did: tree.device_uid
}
# → Chainlink Functions DON → Polygon Router contract
```

> **Worker:** `ChainlinkDispatchWorker` (черга `web3`, retry: 5)
> **Service:** `Chainlink::OracleDispatchService`

---

### 7. 💰 Мікро-Життя — Solana + Celo (Паралельні Фінансові Рейки)

Для верифікованого здоров'я лісу одночасно активуються дві паралельні фінансові рейки:

**Solana** миттєво надсилає USDC мікро-нагороди (0.01–0.1 USDC) на гаманець власника дерева. Час підтвердження ~400 мс означає, що нагорода надходить ще до початку обробки транзакції Polygon.

**Celo** депозитує ReFi-нагороду 5 cUSD безпосередньо на смартфони місцевої громади — лісників, людей, які реально захищають дерева.

```
Solana: 0.01-0.1 USDC за телеметричний пакет → власник дерева (миттєво)
Celo:   5 cUSD за здоровий кластер на добу   → місцева громада (щодня)
```

> **Worker:** `SolanaMicroRewardWorker` · `CeloRewardWorker` (черга `web3`, retry: 3)
> **Service:** `Solana::MintingService` · `Celo::CommunityRewardService`

---

### 8. 🏛️ Макро-Капітал — Polygon + Hadron (Institutional RWA)

KYC-верифікований інституційний фонд через **Polygon Hadron** (стандарт ERC-3643) отримує мінтований RWA-токен: **Silken Carbon Coin (SCC)**.

Потік мінтингу перевіряє три guard clauses:
1. `verified_by_iotex? == true` (ZK-proof з кроку 5)
2. `oracle_status == "fulfilled"` (Chainlink з кроку 6)
3. `hadron_kyc_status == "approved"` (Hadron KYC)

**Конвертація:** 10,000 верифікованих growth points = 1 SCC (ERC-20 на Polygon)

```
TokenomicsEvaluatorWorker (щогодинно)
  → lock_and_mint! (pesimistic lock)
  → BlockchainMintingService → Polygon mint(investor, amount, tree_did)
  → BlockchainConfirmationWorker (+30s) → confirm! (tx_hash)
```

> **Worker:** `MintCarbonCoinWorker` · `HadronAssetRegistrationWorker` (черга `web3`, retry: 5)
> **Service:** `BlockchainMintingService` · `Polygon::HadronComplianceService`

---

### 9. 📊 Глобальний Зір — The Graph (Subgraph Indexing)

Цей мінтинговий подія миттєво індексується **The Graph**-субграфом, оновлюючи статистику поглиненого вуглецю на дашбордах по всьому світу.

```graphql
type CarbonMintEvent @entity {
  id: ID!
  to: Bytes!
  amount: BigInt!
  treeDid: String!
  timestamp: BigInt!
  blockNumber: BigInt!
  transactionHash: Bytes!
}
```

> **Service:** `TheGraph::QueryService`
> **Config:** `subgraph/schema.graphql` · `subgraph/subgraph.yaml` · `subgraph/src/mapping.ts`

---

### 10. ♻️ Очищення — KlimaDAO (ESG Carbon Retirement)

Корпорація бере токен SCC та **спалює** його через **KlimaDAO**, назавжди компенсуючи свій вуглецевий слід для ESG-звітності.

Це двокрокова атомарна транзакція:
1. **Approve** — токен SCC дозволяється для передачі до retirement-контракту KlimaDAO
2. **Retire** — токен назавжди спалюється, баланс переходить до `esg_retired_balance`

Незворотньо. Вуглецевий кредит спожито. Праця лісу вшанована.

> **Worker:** `KlimaRetirementWorker` (черга `web3`, retry: 3)
> **Service:** `KlimaDao::RetirementService`

---

### 11. 🧊 Вічна Пам'ять — Filecoin/IPFS (Immutable Archive)

Наприкінці дня весь цей шлях — від зчитування сенсора до мінтингу токена до відставки вуглецю — архівується у децентралізованому сховищі **Filecoin**.

Кожен запис `AuditLog` містить SHA-256 `chain_hash` (хеш попереднього запису + payload), формуючи незмінний ланцюг на організацію. Запис пінується в IPFS через Pinata API та отримує унікальний CID (Content Identifier).

```ruby
# Filecoin::ArchiveService
payload = {
  audit_log: audit_log.attributes,
  organization_id: org.id,
  chain_hash: audit_log.chain_hash,
  telemetry_summary: daily_summary,
  cid: nil  # Заповнюється після IPFS pin
}
# → IPFS pin → CID → audit_log.update!(ipfs_cid: cid)
```

Навіть якщо всі сервери знищено — дані виживають у Filecoin, доступні через будь-який IPFS-шлюз, назавжди.

> **Worker:** `FilecoinArchiveWorker` · `AuditLogWorker` (черга `low`, retry: 5/3)
> **Service:** `Filecoin::ArchiveService` · `Filecoin::VerificationService`

---

### 12. ⚖️ Останній Суд — Ethereum L1 (State Root Anchoring)

Раз на тиждень — у понеділок, 03:00 UTC — після завершення всіх нічних агрегацій, перевірок здоров'я та протоколів slashing — хеш цього грандіозного процесу назавжди закарбовується в **Ethereum Mainnet**.

```ruby
# Ethereum::StateAnchorService#generate_state_root (канонічно — 05_04 §3)
state_root = Digest::SHA256.hexdigest(
  "#{total_scc}|#{total_sfc}|#{active_tree_count}|#{chain_hash}|#{anchored_at.utc.iso8601}"
)
# → StateRootAnchor.sol: store(bytes32 state_root)
```

> **⚠️ Уточнення термінології (2026-05-28): це aggregate-commitment, а НЕ Merkle Patricia Trie.** Поточний `state_root` — це SHA-256 над **агрегатами** (сумарний SCC + SFC supply + к-ть активних дерев + голова hash-ланцюга `AuditLog` + timestamp). Він криптографічно фіксує **глобальний економічний стан** і незмінну голову event-ланцюга, і дозволяє зовнішньому аудитору відтворити хеш (`EthereumAnchor#verify_state_root`, 05_04). **Але** він НЕ є State Root у сенсі блокчейну — він **не** містить per-account Merkle-дерева, тож з нього **не можна** довести стан окремого дерева («чи було дерево X здоровим на чекпоінті T») через O(log n) inclusion proof.
>
> **Цільове посилення:** для per-tree inclusion proofs — згенерувати `state_root` як **Merkle Root над станами всіх активних `Tree` + балансами `Wallet`** (листя = (tree_id, bio_status, z, …) / (wallet, scc_balance)), де кожен суб'єкт доводить включення Merkle-proof'ом. Узгоджується з batch-Merkle підходом §5.1. SSOT та as-built деталі — [`05_04`](05_04_Ethereum_L1_State_Anchor).

Це rollup-стиль фіналізації. Один запис `bytes32` на тиждень. Газ-ефективно, але абсолютно незмінно. Навіть якщо Polygon зазнає катастрофічного збою — L1-anchor Ethereum фіксує агрегатний стан економіки Silken Net у кожному тижневому чекпоінті.

> **Worker:** `EthereumAnchorWorker` (черга `web3`, retry: 3, cron: `0 3 * * 1`)
> **Service:** `Ethereum::StateAnchorService`

---

### 🔄 Повний Конвеєр

```
🌳 Дерево Дихає (>500 мВ EBFC)
 │
 ▼
🏗️ Akash (децентралізована хмара отримує CoAP)
 │
 ├──▶ 📡 Streamr (P2P real-time трансляція)
 │
 ▼
🪪 peaq DID (верифікація машинного паспорта)
 │
 ▼
🔬 IoTeX W3bstream (ZK-proof: реальний кремній + гомеостаз Лоренца)
 │
 ▼
⚡ Chainlink (децентралізований оракул → міст до блокчейну)
 │
 ├──▶ 💰 Solana (миттєва USDC мікро-нагорода → власник дерева)
 ├──▶ 💰 Celo (cUSD ReFi нагорода → місцева громада)
 │
 ▼
🏛️ Polygon + Hadron (KYC-верифікований мінтинг SCC → інституційний інвестор)
 │
 ├──▶ 📊 The Graph (індексація → глобальний вуглецевий дашборд)
 │
 ▼
♻️ KlimaDAO (ESG-відставка вуглецю → корпорація)
 │
 ▼
🧊 Filecoin/IPFS (незмінний CID-архів → вічна пам'ять)
 │
 ▼
⚖️ Ethereum L1 (тижневий state root → фінальна фіналізація)
```

---

## 📊 5. Ключові Параметри Системи

| Метрика | Значення |
|---|---|
| Інтегровано блокчейн-мереж | **12** |
| Sidekiq workers | **31** |
| Services | **29+** |
| API controllers | **28** |
| Рівнів пріоритету черг | **9** |
| Точність атрактора Лоренца | **Float64** (IEEE 754, бітово ідентично firmware — FW.7) |
| Розмір бінарного пакету | **21 байт** (outer) / **16 байт** (inner) |
| Шифрування AES | **128-bit** (LoRa, per-device, inner E2EE) + **256-bit** (CoAP transport) |
| Струм глибокого сну | **300 нА** (STOP2 RTC-only — `02_03 §9.6 Сценарій C`) |
| Генерація EBFC | **>500 мВ** |
| Поріг емісії | **10,000 growth points = 1 SCC** |
| Закріплення state root | **Щотижня** (понеділок 03:00 UTC) |
| Цільовий масштаб | **Мільйони → Мільярди → Трильйони** дерев |

---

## 🌐 6. Топологія Мережі (High-Level)

```
Soldier (Tree)         Soldier (Tree)         Soldier (Tree)
      │ LoRa                │ LoRa mesh            │ LoRa
      ▼                     ▼                      ▼
   Queen (Gateway) ◄──── Mesh Relay ────► Queen (Gateway)
      │ LTE/Starlink                          │ LTE/Starlink
      ▼                                       ▼
   ┌──────────────────────────────────────────────┐
   │  Rails Backend (Akash Network / GCP)          │
   │  CoAP Listener + Sidekiq (31 workers)         │
   │                                                │
   │  ┌── Verification ─────────────────────────┐  │
   │  │ peaq DID → IoTeX ZK-proof → Chainlink   │  │
   │  └─────────────────────────────────────────┘  │
   │                                                │
   │  ┌── Data Streams ─────────────────────────┐  │
   │  │ Streamr (P2P real-time forest pulse)     │  │
   │  └─────────────────────────────────────────┘  │
   └──────────────────┬───────────────────────────┘
                      │ Multi-RPC
       ┌──────────────┼──────────────────────────┐
       ▼              ▼                          ▼
   ┌────────┐   ┌──────────┐            ┌──────────┐
   │Polygon │   │  Solana  │            │   Celo   │
   │SCC/SFC │   │  micro-  │            │  cUSD    │
   │Hadron  │   │  rewards │            │  ReFi    │
   │Chainlnk│   └──────────┘            └──────────┘
   └───┬────┘
       │
   ┌───┴────────────────────────────────────────────┐
   │  The Graph (subgraph indexing)                  │
   │  KlimaDAO (ESG carbon retirement)              │
   │  Filecoin/IPFS (immutable archive)             │
   │  Ethereum L1 (weekly state root finality)      │
   └────────────────────────────────────────────────┘
```
