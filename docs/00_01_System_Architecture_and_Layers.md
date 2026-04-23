# 00_01: System Architecture and Layers

## 🎯 Мета
Зафіксувати 8-рівневу кіберфізичну архітектуру екосистеми Gaia 2.0 (Silken Net). Цей документ є базовою конституцією для маршрутизації даних від біохімічної реакції в дереві до криптографічної фіналізації в Ethereum L1.

## ✅ Статус
* **Поточний TRL:** TRL 4 (Архітектура затверджена, інтеграційні компоненти тестуються локально).
* **Оновлення:** Проведено півот апаратної частини. Повністю видалено рівень електрокінетики (Streaming Potential / LTC3108). Затверджено нову біохімічну базу (EBFC).

## 🛑 Блокери
* Відсутні на рівні макроархітектури. Успіх системи залежить від розблокування TRL 4 у хіміків (Модуль 01).

---

## 📎 Технічна Специфікація: 8 Рівнів Gaia 2.0

Система працює за принципом безперервного, детермінованого конвеєра (Zero-Trust pipeline). Дані рухаються знизу вгору.

### 🌳 Рівень 1: Біофізика та Механіка (The Root)
* **Сутність:** Коаксіальний титановий імплантат (Ti-6Al-4V) із гіроїдною пористістю. Розділений діелектриком PEEK.
* **Енергетика:** Ензимний біопаливний елемент (EBFC). Глюкозооксидаза на аноді генерує >500 mV безпосередньо з метаболізму дерева. Жодних зовнішніх дротів.

### ⚙️ Рівень 2: Апаратне Забезпечення (The Capsule)
* **Сутність:** Герметична капсула з PCB, що підключається до анкера наосліп через Pogo Pins.
* **Живлення:** BQ25570 MPPT + Іоністор (0.47F / 5.5V). 
* **Активація:** Акустичний п'єзо-тригер для апаратного пробудження при вібраціях.

### 🧠 Рівень 3: Прошивка та Edge AI (The Brain)
* **Ядро:** STM32WLE5JC (ARM Cortex-M4). Стан "Нульового Лагу" (Deep sleep STOP2: 2.1 µA).
* **Сенсорика:** Апаратний DMA-буфер мікрофона.
* **TinyML:** Нейромережа на пристрої для класифікації аудіо (Тиша / Вітер / Пилка).
* **Математика:** mruby VM розраховує Атрактор Лоренца (гомеостаз) на базі часу заряду іоністора.
* **Безпека:** Апаратне шифрування AES-256 (пакети EwsAlert).

### 📡 Рівень 4: Мережа (The Veins)
* **Протокол:** LoRa mesh 868 МГц (custom TTL-based, DEFAULT_TTL=3). Binary payload 21 bytes (4 DID + 1 RSSI + 16 encrypted).
* **Топологія:** Directed Mesh (Солдати передають пакети через сусідів).
* **Шлюз (Королева):** Агрегує пакети та відправляє їх у хмару (опціонально через Starlink Direct-to-Cell).
* **Резерв:** Helium Network (HNT) як fallback при втраті Queen — будь-який роутер Helium у радіусі 15 км ловить пакет ([деталі → 02_05](02_05_Queen_Hardware_and_Starlink)).

### 🖥️ Рівень 5: Серверне Ядро (The Engine)
* **Стек:** Ruby on Rails 8.1 Omakase, PostgreSQL, Redis, Sidekiq (31+ Workers).
* **Деплой:** Kamal, Docker, Prometheus (Observability).
* **Роль:** Декодування (L3), маршрутизація API (28 Controllers), управління бізнес-логікою контрактів (Nature-as-a-Service).
* **Вхідний шар IoT:** CoAP/UDP listener (порт 5683) — для планетарного масштабу потребує Ingress Proxy перед Rails ([деталі → 06_01](06_01_Deployment_Kamal_Terraform)).

---

## 🚀 Gaia 2.0 Scaling Roadmap — Фрактальна Топологія

> Поточна плоска LoRa-меш архітектура задихнеться від колізій та затримок вже на кількох тисячах вузлів. Для мільйонів дерев необхідна **фрактальна топологія**.

### Трьохрівнева ієрархія вузлів (The Fractal Stack)

```
L3: Queen Gateways (Супер-вузли)
    LoRa SF12 + Starlink/LTE backbone
    ├── Inter-cluster relay (Queen ↔ Queen Backhaul Mesh)
    └── Cloud uplink (CoAP → Rails)
         │
L2: Sergeant Nodes (Кластер-хеди) [МАЙБУТНЄ]
    Більший запас енергії (сонячна панель + EBFC)
    ├── Агрегує 50–200 Солдатів у "Звіт про стан кластера"
    └── Замість 100 пакетів → 1 стиснений summary
         │
L1: Soldier Nodes (Листя) — поточна архітектура
    STM32WLE5JC + EBFC (0.47F)
    └── Передає стиснутий стан (lambda-exponent) найближчому Сержанту
```

**Ключова зміна:** Солдати більше не спілкуються з усім світом — лише з найближчим Сержантом. Зменшення радіочастотних колізій на порядки.

### H-LDSE — Ієрархічний Протокол Маршрутизації

Еволюція поточного LDSE-меш для мільйонної мережі:

| Механізм | Поточний LDSE | H-LDSE |
|----------|--------------|--------|
| Таблиця маршрутизації | Всі сусіди (OOM при >1000 вузлів) | Лише 2–3 хопи (локальна адресація) |
| Адресація | DID-based | Геохешинг (ID = координати) |
| Пошук шляху | TTL broadcast | Градієнтний потік до найближчої Queen |
| Частотні рівні | Один канал | Spatial Multiplexing (L1 → канал A, L2 → канал B) |

**Геохешинг:** Кожен супер-кластер отримує ID на основі координат. Пакет не шукає маршрут — він тече в бік зменшення градієнта до найближчої Королеви. Усуває broadcast storm.

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

**Queen-to-Queen Backhaul Mesh:** Королеви з'єднані між собою через LoRa SF12. Якщо одна Queen втрачає Starlink → передає дані сусідній Queen через LoRa-магістраль.

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

### 🔐 Рівень 6: Мережі Даних та Верифікації (The Truth)
* **peaq Network:** Надання кожному дереву Machine DID паспорта.
* **IoTeX W3bstream:** Генерація ZK-proofs, що доводять походження даних з реального кремнію (Real Silicon).
* **Streamr & Filecoin:** P2P трансляція телеметрії та вічне зберігання на IPFS.

### 💰 Рівень 7: Фінансова Логіка (The Ledger)
* **Primary Chain:** Polygon EVM. Смарт-контракти для мінтингу SCC (Silken Carbon Coin) та SFC (Governance).
* **Оракул:** Chainlink DON (передає верифіковані бали росту з Rails у Polygon).
* **Паралельні фінанси:** Solana (мікро-нагороди лісникам), Celo (ReFi для громад), KlimaDAO (спалювання ESG).
* **Compliance:** Polygon Hadron (KYC/KYB за стандартом ERC-3643).

### 🗳️ Рівень 7.5: Governance DAO (The Parliament)
* **Контракти (Polygon):** `SilkenGovernor.sol` (OZ Governor + GovernorVotes + GovernorTimelockControl + GovernorCountingSimple + GovernorVotesQuorumFraction 4%), `SilkenTimelock.sol` (48h мінімальна затримка), `ProtocolParameters.sol` (on-chain registry 13 параметрів: Lorenz σ/ρ/β/dt/iterations/z_min/z_max/z_target, tokenomics, slashing).
* **Voting Power:** SFC (ERC20Votes) — snapshot-based `getPastVotes()` + votingDelay 43200 блоків (~1 день на Polygon) для Flash Loan defense.
* **Pipeline:** SFC Holders → `SilkenGovernor` (propose/vote) → `SilkenTimelock` (48h delay) → `ProtocolParameters` (setParameter) → `Governance::ParameterSyncWorker` (щоденний sync on-chain → `SystemParameter` модель).
* **CI/CD:** `solidity_audit.yml` — Foundry build/test/coverage + Slither static analysis на кожен push/PR.

### 🏛️ Рівень 8: Фіналізація (The Anchor)
* **Стек:** Ethereum L1.
* **Роль:** Щотижневе закріплення кореня стану (State Root — 32-byte SHA-256 hash) всієї економіки Gaia 2.0. Гарантія Rollup-рівня від катастрофічних збоїв сайдчейнів.

---

## 🗄️ Redis Infrastructure — Архітектурне Рішення (DB Isolation)

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

## 🌐 Анатомія Кіберфізичного Стану Gaia 2.0 — Повний 12-Крокової Конвеєр

> *"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."*

Цей розділ описує повний життєвий цикл одного "серцебиття" через кіберфізичний стан Silken Net — від моменту, коли дерево "дихає", до миті, коли його внесок закарбовується в Ethereum назавжди.

**12 кроків. 12 мереж. Одна жива система.**

---

### 1. 🌳 Фізичний Дотик — Дерево Дихає

Дерево дихає. Ксилемний сік тече вгору, генеруючи понад 500 мВ завдяки метаболізму глюкози через ферменти GOx/Laccase в титановому гіроїдному анкері (Ti-6Al-4V). BQ25570 MPPT заряджає суперконденсатор 0.47 Ф. Коли напруга досягає порогу — STM32WLE5JC Soldier прокидається зі сну STOP2 (2.1 µА).

**Цикл Soldier:**
- Фаза 1: Збір сенсорних даних (температура, імпеданс, акустика, напруга суперконденсатора)
- Фаза 1.5: TinyML-класифікація звуку (тиша / вітер / кавітація / пилка)
- Фаза 2: Упаковка у 16-байтний payload
- Фаза 3: mruby Lorenz attractor → `growth_points` + `bio_status`
- Фаза 4: AES-256-ECB шифрування → LoRa TX (868 МГц)
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

Queen-шлюз (STM32 + SIM7070G) збирає LoRa-пакети від до 50 Soldiers, пакетує їх через алгоритм CIFO, шифрує AES-256-CBC та передає через CoAP PUT через Starlink Direct-to-Cell або LTE.

Rails 8.1 backend отримує цей сигнал не на єдиній корпоративній хмарі, а на **Akash Network** — децентралізованому ринку обчислень. Жодна компанія не може вимкнути кіберфізичний стан. Провайдери змагаються за деплой, система автоматично мігрує у разі відмови одного.

```
Queen (LoRa RX) → AES-256-CBC → CoAP PUT → Akash (Rails 8.1 + Sidekiq)
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

### 5. 🔬 Абсолютна Істина — IoTeX W3bstream (ZK-Proofs) + Математика Лоренца

**IoTeX W3bstream** генерує zero-knowledge proof того, що:
1. Телеметрія прийшла з **реального кремнію** (верифікація апаратного підпису)
2. Математика атрактора Лоренца підтверджує **гомеостаз** дерева

Серверний `SilkenNet::Attractor` незалежно обчислює те саме Z-значення з **BigDecimal** (18-значна точність) — для крос-платформної детермінованості та юридичної аудитопридатності.

```ruby
# SilkenNet::Attractor (BigDecimal, 250 ітерацій × 0.01 timestep)
sigma = BigDecimal("10") + (acoustic * BigDecimal("0.1")).clamp(5, 30)
rho   = BigDecimal("28") + (temperature * BigDecimal("0.2")).clamp(10, 50)
beta  = BigDecimal("8") / BigDecimal("3")
```

Якщо Z-значення пристрою відхиляється від серверного більш ніж на 30%, `InsightGeneratorService` позначає це як **шахрайство** — запобігання підробці на математичному рівні.

> **Worker:** `IotexVerificationWorker` (черга `web3`, retry: 5)
> **Service:** `Iotex::W3bstreamVerificationService` · `SilkenNet::Attractor`

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
# Ethereum::StateAnchorService
state_root = Digest::SHA256.hexdigest(
  "#{total_scc_supply}:#{chain_hash}:#{timestamp}"
)
# → Ethereum L1: store(bytes32 state_root)
```

Це rollup-стиль фіналізації. Один запис `bytes32` на тиждень. Газ-ефективно, але абсолютно незмінно. Навіть якщо Polygon зазнає катастрофічного збою — L1-anchor Ethereum доводить стан всієї економіки Silken Net у кожному тижневому чекпоінті.

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

### 📊 Ключові Параметри Системи

| Метрика | Значення |
|---|---|
| Інтегровано блокчейн-мереж | **12** |
| Sidekiq workers | **31** |
| Services | **29+** |
| API controllers | **28** |
| Рівнів пріоритету черг | **9** |
| Точність атрактора Лоренца | **18 знаків** (BigDecimal) |
| Розмір бінарного пакету | **21 байт** (outer) / **16 байт** (inner) |
| Шифрування AES | **256-bit** (апаратно-прив'язані ключі) |
| Струм глибокого сну | **2.1 µА** (STOP2) |
| Генерація EBFC | **>500 мВ** |
| Поріг емісії | **10,000 growth points = 1 SCC** |
| Закріплення state root | **Щотижня** (понеділок 03:00 UTC) |
| Цільовий масштаб | **Мільйони → Мільярди → Трильйони** дерев |
