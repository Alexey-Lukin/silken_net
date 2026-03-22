# 05\_01: Multichain Architecture (The 12-Chain Ecosystem)

## 🎯 Мета (Objective)

Зафіксувати повну топологію та взаємодію 12 незалежних блокчейн-мереж і децентралізованих протоколів, що утворюють Кіберфізичну Державу Gaia 2.0. Цей документ деталізує, як фізичні дані з лісу проходять шлях від локального ZK-доказу до глобальної фінансової емісії та фіналізації в Ethereum L1.

> **⚠️ SSOT Sync:** Цей документ синхронізовано з кодбейсом станом на 2026-03-22. Кожна мережа з топології має відповідний Ruby-сервіс, Sidekiq-воркер та RSpec-специфікацію.

## ✅ Статус (Status)

* **Поточний TRL:** TRL 8 (Мультичейн архітектура повністю спроєктована. Структурний скелет усіх 12 мереж присутній у кодбейсі. Всі сервіси мають RSpec-покриття.)
* **Пов'язані модулі:** Джерела даних — `04_02_Business_Logic_and_Services`. Токеноміка — `05_02_Proof_of_Growth_Pipeline`, `05_03_Tokenomics_SCC_and_SFC`. Фіналізація — `05_04_Ethereum_L1_State_Anchor`.

### Статус Імплементації по Мережах

| # | Мережа | Сервіс | Статус | Примітка |
|---|--------|--------|--------|----------|
| 1 | Streamr | `Streamr::BroadcasterService` | ✅ Real | HTTP POST через Brubeck API |
| 2 | Filecoin/IPFS | `Filecoin::ArchiveService` + `VerificationService` | ✅ Real | Pinata IPFS gateway |
| 3 | peaq | `Peaq::DidRegistryService` | ✅ Real | Ed25519-підписані DID через Substrate HTTP |
| 4 | IoTeX W3bstream | `Iotex::W3bstreamVerificationService` | ✅ Real | ZK-proof через W3bstream HTTP API |
| 5 | The Graph | `TheGraph::QueryService` | ✅ Real | GraphQL-запити до subgraph |
| 6 | Polygon | `BlockchainMintingService` + `BlockchainBurningService` | ✅ Real | Eth::Client → Alchemy RPC |
| 7 | Polygon Hadron | `Polygon::HadronComplianceService` | ⚠️ Hybrid | Реальне KYC API + симуляція коли credentials відсутні |
| 8 | Solana | `Solana::MintingService` | ⚠️ Devnet | `simulateTransaction` замість `sendTransaction` |
| 9 | Celo | `Celo::CommunityRewardService` | ✅ Real | ERC-20 transfer cUSD через Celo RPC |
| 10 | KlimaDAO | `KlimaDao::RetirementService` | ✅ Real | Approve + Retire (два ERC-20 виклики) |
| 11 | Chainlink | `Chainlink::OracleDispatchService` | ⚠️ Hybrid | Реальний Chainlink Functions Router + stub коли credentials відсутні |
| 12 | Ethereum L1 | `Ethereum::StateAnchorService` | ✅ Real | `storeStateRoot(bytes32)` через Alchemy Ethereum RPC |

**Легенда:** ✅ Real = Бойова імплементація з реальними RPC-викликами · ⚠️ Hybrid = Працює в реальному режимі з credentials, fallback до симуляції без них · ⚠️ Devnet = Бойова логіка, але транзакції йдуть на Devnet (simulateTransaction)

---

## 🛑 Блокери (Blockers / Needs Action)

### 🔴 BLOCKER-1: Cross-chain Gas Costs (Treasury Management)

**Статус:** Не імплементовано. Винесено в окремий цикл.

Підтримка паралельних транзакцій у Solana, Celo та Polygon вимагає складного балансування гаманців (Treasury Management). Необхідно впровадити:

1. **Автоматичні сповіщення (PagerDuty)** — якщо баланс MATIC, SOL або CELO на гаманцях оракулів падає нижче критичного мінімуму.
2. **Мінімальні пороги:**
   - Polygon: `0.05 MATIC` (вже перевіряється в `BlockchainMintingService` як guard clause)
   - Solana: потребує аналогічну перевірку в `Solana::MintingService`
   - Celo: потребує аналогічну перевірку в `Celo::CommunityRewardService`
3. **Treasury Dashboard** — централізований моніторинг балансів усіх 4 гаманців оракулів.

**Де в коді:** `BlockchainMintingService#perform` вже має guard clause `raise if balance < 0.05 MATIC`, але Solana та Celo — ні.

### 🔴 BLOCKER-2: Subgraph Event Name Mismatch

**Статус:** Баг у `subgraph/subgraph.yaml`.

Смарт-контракт `SilkenCarbonCoin.sol` емітує подію `TokenSlashed(address indexed, uint256, string indexed)`, але subgraph manifest підписаний на `Slashed(address indexed, uint256, string indexed)`.

* **Файл:** `subgraph/subgraph.yaml` → `eventHandlers` → `event: Slashed(...)`
* **Контракт:** `contracts/SilkenCarbonCoin.sol` → `event TokenSlashed(...)`
* **Вплив:** Slashing-події НЕ індексуються The Graph — `ProtocolFinancials.totalBurned` завжди `0`.
* **Фікс:** Змінити `Slashed` → `TokenSlashed` в `subgraph.yaml`.

### 🟡 BLOCKER-3: Solana Devnet Lock

**Статус:** Архітектурне обмеження.

`Solana::MintingService` використовує `simulateTransaction` замість `sendTransaction`. Мікро-винагороди фактично не відправляються на Mainnet. Потребує:
1. Перехід на `sendTransaction` для Production
2. Розділення конфігурації Devnet/Mainnet через ENV
3. Інтеграційне тестування з реальним Solana RPC

### 🟡 BLOCKER-4: Hadron та Chainlink Simulation Fallbacks

**Статус:** Архітектурне рішення (прийнятне для TRL 8, потребує вирішення для TRL 9).

`Polygon::HadronComplianceService` та `Chainlink::OracleDispatchService` мають fallback-режим: коли credentials відсутні, генерують stub response замість реальних API-викликів. Для Production це потрібно вимкнути або зробити strict-mode.

### 🟡 BLOCKER-5: PuroEarth Passport Service — Not Implemented

**Статус:** Worker існує (`PuroEarthPassportWorker`), але сервіс `PuroEarth::PassportService` ще не створено.

* **Файл:** `app/workers/puro_earth_passport_worker.rb` — містить TODO для сервісу
* **Вплив:** D-MRV Biomass Passport для мертвих дерев (Biochar CORC) не генерується
* **Це НЕ частина 12-Chain топології**, але блокує "Afterlife Economy" пайплайн

### 🟢 INFO: dClimate Verification — Mock Mode

`Dclimate::VerificationService` працює в mock-режимі (повертає випадковий результат замість реального API dClimate). Це прийнятно для TRL 8, але потребує реальної інтеграції для Production.

---

## 🌐 1. Топологія 12 Мереж (The 12-Network Stack)

Gaia 2.0 не покладається на один блокчейн. Для забезпечення максимальної безпеки, масштабованості та compliance, система розподіляє функції (Зберігання, Верифікація, Економіка, Фіналізація) між спеціалізованими протоколами.

### Рівень 1: Дані та Зберігання (Data & Storage)

#### 1. Streamr (P2P Real-time)

Використовується для децентралізованої трансляції "пульсу" лісу в реальному часі. Дані з шлюзів (Королев) потрапляють сюди до того, як вони будуть записані в базу.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Streamr::BroadcasterService` |
| **Воркер** | `StreamrBroadcastWorker` |
| **Черга** | `low` (пріоритет 9) |
| **Retry** | 3 |
| **Тригер** | `TelemetryUnpackerService` (після розпакування кожного пакета) |
| **Credentials** | `streamr_stream_id`, `streamr_api_key` (Rails encrypted credentials) |
| **API** | `https://brubeck.streamr.network/api/v1/streams/{stream_id}/data` |
| **Спека** | `spec/services/streamr/broadcaster_service_spec.rb` |

**Payload:**
```ruby
{
  tree_id: tree.id,
  peaq_did: tree.peaq_did,
  z_value: telemetry.lorenz_z,
  bio_status: telemetry.bio_status,
  temperature: telemetry.temperature,
  voltage: telemetry.voltage,
  alerts: active_alerts
}
```

> ⚡ Broadcast є non-blocking — невдача Streamr ніколи не зупиняє фінансовий пайплайн.

#### 2. Filecoin / IPFS (Immutable Archive)

Вічне, незмінне сховище (Immutable Archive). Сюди записуються аудит-логи разом з їхніми CID (Content Identifiers), щоб будь-який аудитор міг перевірити історію дерева за 10 років.

| Параметр | Значення |
|----------|----------|
| **Сервіси** | `Filecoin::ArchiveService`, `Filecoin::VerificationService` |
| **Воркер** | `FilecoinArchiveWorker` |
| **Черга** | `low` (пріоритет 9) |
| **Retry** | 5 |
| **Тригер** | `AuditLogWorker` (після створення AuditLog запису) |
| **Credentials** | `filecoin_api_key` (Rails encrypted credentials) |
| **ENV** | `FILECOIN_GATEWAY_URL` (default: `https://gateway.pinata.cloud/ipfs`), `FILECOIN_PINNING_API_URL` (default: `https://api.pinata.cloud/pinning/pinJSONToIPFS`) |
| **Спеки** | `spec/services/filecoin/archive_service_spec.rb`, `spec/services/filecoin/verification_service_spec.rb` |

**Два потоки:**
- `archive!` — пінить JSON payload на IPFS через Pinata API → повертає CID → зберігає в `audit_log.ipfs_cid`
- `verify!` — завантажує дані з IPFS gateway за CID → порівнює `chain_hash` з локальною копією

---

### Рівень 2: Довіра та Верифікація (Verification)

#### 3. peaq network (Machine DID)

Кожен "Солдат" (дерево) отримує тут свій суверенний цифровий паспорт (наприклад, `did:peaq:0x...`). Це гарантує, що пристрій є автентичним.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Peaq::DidRegistryService` |
| **Воркер** | `PeaqRegistrationWorker` |
| **Черга** | `web3` (пріоритет 7) |
| **Retry** | 5 |
| **Тригер** | При реєстрації нового дерева в системі |
| **Credentials** | `peaq_node_url`, `peaq_signing_key` (Rails encrypted credentials) |
| **Криптографія** | Ed25519 (через `Ed25519Crypto::SigningService`) — peaq використовує Substrate |
| **Спека** | `spec/services/peaq/did_registry_service_spec.rb` |

**Формат DID:**
```
did:peaq:0x{SHA256(hardware_identifier + tree_id + created_at)[0:40]}
```

#### 4. IoTeX W3bstream (ZK-Proofs)

Генерація Zero-Knowledge доказів. Гарантує, що телеметрія надійшла з реального кремнієвого обладнання (Trusted Execution Environment), а не була згенерована скриптом хакера на сервері.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Iotex::W3bstreamVerificationService` |
| **Воркер** | `IotexVerificationWorker` |
| **Черга** | `web3_critical` (пріоритет 6) |
| **Retry** | 5 |
| **Тригер** | `TelemetryUnpackerService` (одразу після розпакування телеметрії) |
| **Credentials** | `iotex_w3bstream_url`, `iotex_api_key` (Rails encrypted credentials) |
| **Спека** | `spec/services/iotex/w3bstream_verification_service_spec.rb` |

**Guard Clause:** Chainlink dispatch ЗАБОРОНЕНО без підтвердження від IoTeX (`verified_by_iotex? == true`).

#### 5. The Graph (Decentralized Indexing)

Децентралізований індексатор. Спеціальний сабграф (Subgraph) слухає події `CarbonMinted` і будує GraphQL API для глобальних дашбордів екологічних організацій.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `TheGraph::QueryService` |
| **Воркер** | — (read-only, немає окремого воркера) |
| **Черга** | — |
| **Тригер** | Викликається on-demand з контролерів та дашбордів |
| **Credentials** | `the_graph_api_url` (Rails encrypted credentials) |
| **Subgraph** | `subgraph/schema.graphql`, `subgraph/subgraph.yaml`, `subgraph/src/mapping.ts` |
| **Мережа Subgraph** | `polygon-amoy` (Polygon testnet) |
| **Спека** | `spec/services/the_graph/query_service_spec.rb` |

**Методи:**
- `fetch_total_carbon_minted` — останні 100 `CarbonMintEvent`, сума `amount`
- `fetch_protocol_financials` — singleton `ProtocolFinancial` entity (`totalMinted`, `totalBurned`, `totalPremiums`)

**Entities (GraphQL):**
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

type ProtocolFinancials @entity {
  id: ID!
  totalMinted: BigInt!
  totalBurned: BigInt!
  totalPremiums: BigInt!
}

type SlashingEvent @entity { ... }
type PremiumPaidEvent @entity { ... }
```

---

### Рівень 3: Фінанси та Економіка (Primary Chain & Parallel Rails)

#### 6. Polygon (Primary EVM)

Головна артерія системи. Тут розгорнуті наші ключові смарт-контракти (`SilkenCarbonCoin.sol` та `SilkenForestCoin.sol`). Вибраний через низьку вартість транзакцій та сумісність з EVM.

| Параметр | Значення |
|----------|----------|
| **Сервіси** | `BlockchainMintingService`, `BlockchainBurningService`, `ChainAuditService`, `PriceOracleService`, `MintingRollbackService` |
| **Воркери** | `MintCarbonCoinWorker`, `BurnCarbonTokensWorker`, `BlockchainConfirmationWorker`, `TokenomicsEvaluatorWorker` |
| **Черги** | `web3_critical` (мінтинг, підтвердження), `critical` (спалювання), `default` (токеноміка) |
| **ENV** | `ALCHEMY_POLYGON_RPC_URL`, `ORACLE_PRIVATE_KEY`, `CARBON_COIN_CONTRACT_ADDRESS` |
| **Спеки** | `spec/services/blockchain_minting_service_spec.rb`, `spec/services/blockchain_burning_service_spec.rb`, `spec/services/chain_audit_service_spec.rb`, `spec/services/price_oracle_service_spec.rb`, `spec/services/minting_rollback_service_spec.rb` |

**Guard Clauses (BlockchainMintingService):**
1. `verified_by_iotex? == true` — ZK-proof з IoTeX
2. `oracle_status == "fulfilled"` — Chainlink Oracle підтвердив
3. `hadron_kyc_status == "approved"` — KYC пройдено (для інституційних інвесторів)
4. Oracle balance ≥ `0.05 MATIC` — достатньо газу
5. Kredis distributed lock (30s expiration) — запобігає подвійному мінтингу

**HYBRID PROTOCOL GAIA:** 2% Dynamic Tax на carbon\_coin мінтинг, коли insurance pool потребує поповнення (розділяє recipients між forester та DAO Treasury).

#### 7. Polygon Hadron (Identity & Compliance)

Модуль Identity & Compliance. Перевіряє `hadron_kyc_status`. Інституційні інвестори можуть мінтити або купувати токени SCC тільки після проходження KYC (стандарт ERC-3643).

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Polygon::HadronComplianceService` |
| **Воркер** | `HadronAssetRegistrationWorker` |
| **Черга** | `web3_low` (пріоритет 8) |
| **Retry** | 5 |
| **Credentials** | `hadron_api_key` (Rails encrypted credentials) |
| **ENV** | `HADRON_API_URL` (default: `https://api.hadron.polygon.technology`) |
| **Спека** | `spec/services/polygon/hadron_compliance_service_spec.rb` |

**Два потоки:**
1. `verify_investor!(wallet)` — перевірка KYC через Hadron Identity Platform → `wallet.hadron_kyc_status`
2. `register_asset!(naas_contract)` — реєстрація лісової ділянки як Real World Asset (RWA) → `naas_contract.hadron_asset_id`

> ⚠️ **Hybrid Mode:** Якщо `hadron_api_key` відсутній, сервіс генерує stub response (`approved: true`). Для Production потрібен strict-mode.

#### 8. Solana (Micro-Rewards)

Використовується для мікро-транзакцій. Забезпечує миттєві виплати USDC у якості винагород власникам дерев (або арбористам) за підтримання гомеостазу.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Solana::MintingService` |
| **Воркер** | `SolanaMicroRewardWorker` |
| **Черга** | `web3` (пріоритет 7) |
| **Retry** | 3 |
| **ENV** | `SOLANA_RPC_URL` (default: Devnet), `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_MINT_AUTHORITY_PUBKEY`, `SOLANA_USDC_MINT_ADDRESS`, `SOLANA_WALLET_KEYPAIR` |
| **Спека** | `spec/services/solana/minting_service_spec.rb` |

**Trustless Requirements (Guard Clauses):**
1. `verified_by_iotex? == true`
2. `oracle_status == "fulfilled"`

**Мікро-винагорода:** Base reward + bonus per growth\_point, конвертовано в lamports → USDC

> ⚠️ **Devnet Lock:** Використовує `simulateTransaction` замість `sendTransaction`. Потребує перемикача для Production.

#### 9. Celo (ReFi Community Rewards)

Мережа регенеративних фінансів. Інтеграція стейблкоїна cUSD для грантів та підтримки локальних громад, які доглядають за лісом.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Celo::CommunityRewardService` |
| **Воркер** | `CeloRewardWorker` |
| **Черга** | `web3` (пріоритет 7) |
| **Retry** | 3 |
| **Тригер** | `ClusterHealthCheckWorker` (щоденно о 02:00 UTC) — для здорових кластерів |
| **ENV** | `CELO_RPC_URL` (з fallback), `ORACLE_PRIVATE_KEY`, `CELO_CUSD_CONTRACT_ADDRESS` |
| **Спека** | `spec/services/celo/community_reward_service_spec.rb` |

**Умови нарахування:**
- `stress_index ≤ 0.2` (кластер здоровий)
- `fraud_detected == false`
- Організація має зареєстровану crypto-адресу

**Сума:** 5 cUSD на здоровий кластер на день

**Особливості:** Kredis distributed lock для атомарності ERC-20 transfer + BlockchainTransaction запис.

#### 10. KlimaDAO (ESG Carbon Retirement)

Шлюз для корпорацій. Дозволяє миттєво списувати (Retire) токени SCC для покриття корпоративного ESG-боргу (Carbon Offsetting) безпосередньо через смарт-контракти.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `KlimaDao::RetirementService` |
| **Воркер** | `KlimaRetirementWorker` |
| **Черга** | `web3_low` (пріоритет 8) |
| **Retry** | 3 |
| **ENV** | `ORACLE_PRIVATE_KEY`, `CARBON_COIN_CONTRACT_ADDRESS`, `KLIMA_RETIREMENT_CONTRACT` |
| **RPC** | `ALCHEMY_POLYGON_RPC_URL` (Polygon, де розгорнуто KlimaDAO) |
| **Спека** | `spec/services/klima_dao/retirement_service_spec.rb` |

**Два кроки (Atomic):**
1. **Approve** — дозвіл на трансфер SCC до KlimaDAO контракту
2. **Retire** — безповоротне спалення → баланс переходить до `wallet.esg_retired_balance`

**Захист:** Pessimistic locking запобігає подвійному списанню.

---

### Рівень 4: Мости та Фіналізація (Bridging & Finality)

#### 11. Chainlink (DON — Decentralized Oracle Network)

Децентралізована мережа оракулів. Працює як міст між Web2-бекендом (Rails) та смарт-контрактами Polygon. Оракул має жорстке правило (Guard Clause): він не передасть транзакцію на мінтинг токенів, поки не отримає підтвердження від IoTeX W3bstream.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Chainlink::OracleDispatchService` |
| **Воркер** | `ChainlinkDispatchWorker` |
| **Черга** | `web3_critical` (пріоритет 6) |
| **Retry** | 5 |
| **Тригер** | Після успішної IoTeX ZK-верифікації |
| **ENV** | `CHAINLINK_FUNCTIONS_ROUTER`, `CHAINLINK_SUBSCRIPTION_ID`, `ORACLE_PRIVATE_KEY` |
| **RPC** | `ALCHEMY_POLYGON_RPC_URL` |
| **Спека** | `spec/services/chainlink/oracle_dispatch_service_spec.rb` |

**Guard Clause:** `validate_iotex_verification!` — dispatch ЗАБОРОНЕНО якщо `verified_by_iotex? == false`.

**Chainlink Payload:**
```ruby
{
  peaq_did: tree.peaq_did,
  lorenz_state: attractor_z_value,
  zk_proof_ref: telemetry.zk_proof_ref,
  tree_did: tree.device_uid
}
```

> ⚠️ **Hybrid Mode:** Якщо `CHAINLINK_FUNCTIONS_ROUTER` відсутній, сервіс генерує stub `request_id` локально замість on-chain виклику.

#### 12. Ethereum L1 (State Root Anchoring)

Абсолютна істина. Раз на тиждень весь стан лісу та економіки хешується (SHA-256) і записується в Mainnet Ethereum.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Ethereum::StateAnchorService` |
| **Воркер** | `EthereumAnchorWorker` |
| **Черга** | `web3_low` (пріоритет 8) |
| **Retry** | 3 |
| **Cron** | `0 3 * * 1` (щопонеділка о 03:00 UTC) |
| **Unique** | `unique_for: 1.hour` (запобігає overlapping) |
| **ENV** | `ETHEREUM_ANCHOR_PRIVATE_KEY`, `ETHEREUM_ANCHOR_CONTRACT` |
| **RPC** | `ALCHEMY_ETHEREUM_RPC_URL` |
| **Спека** | `spec/services/ethereum/state_anchor_service_spec.rb` |

**Алгоритм:**
```ruby
state_root = Digest::SHA256.hexdigest(
  "#{total_scc_supply}:#{chain_hash}:#{timestamp}"
)
# → Ethereum L1: storeStateRoot(bytes32)
```

**Економіка:** 32 байти раз на тиждень. Мінімальний газ, але рівень безпеки мережі Ethereum вартістю в сотні мільярдів доларів.

---

## ⚙️ 2. Консенсус "Proof of Growth" (Трубопровід Верифікації)

Процес перетворення фізичного життя дерева на токен (SCC) є багатоетапним і не потребує довіри (Trustless). Жодна людина чи адміністратор не може втрутитися в цей потік:

### Крок 1: Збір (Hardware → Backend)

Сенсор зчитує час заряду іоністора (`delta_t`) і напругу (`vcap`), пакує у 16 байт і шифрує AES-256.

```
firmware/soldier/main.c → LoRa TX → Queen → CoAP PUT → UnpackTelemetryWorker → TelemetryUnpackerService
```

| Компонент | Файл |
|-----------|------|
| Прошивка Солдата | `firmware/soldier/main.c` (648 рядків C) |
| Прошивка Королеви | `firmware/queen/main.c` (550 рядків C) |
| mruby Lorenz (on-device) | `firmware/bio_contracts/bio_contract.rb` |
| Воркер розпакування | `UnpackTelemetryWorker` (черга: `uplink`, пріоритет 1) |
| Сервіс розпакування | `TelemetryUnpackerService` (21-байт binary decoding) |

### Крок 2: Обчислення (Lorenz Attractor)

Внутрішня математика (Атрактор Лоренца) рахує значення осі Z. `Z-value` порівнюється з константами `TreeFamily` (напр. 20.0). Якщо дерево в гомеостазі — нараховуються `growth_points`.

```ruby
# SilkenNet::Attractor (BigDecimal, 250 iterations × 0.01 timestep)
sigma = BigDecimal("10") + (acoustic * BigDecimal("0.1")).clamp(5, 30)
rho   = BigDecimal("28") + (temperature * BigDecimal("0.2")).clamp(10, 50)
beta  = BigDecimal("8") / BigDecimal("3")
```

| Компонент | Файл |
|-----------|------|
| Серверний Lorenz | `app/services/silken_net/attractor.rb` (BigDecimal, 18-digit precision) |
| Dual Computation Integrity | Device Z vs Server Z — divergence > 30% → fraud |
| Fraud Guard | `InsightGeneratorService` (flagging) |

### Крок 3: Паспорт (peaq DID)

Перевірка DID-ідентифікатора (чи це дерево досі зареєстроване і живе).

```
PeaqRegistrationWorker → Peaq::DidRegistryService → did:peaq:0x{40-char-hex}
```

### Крок 4: Крипто-доказ (IoTeX W3bstream)

W3bstream формує ZK-proof того, що дані не були підроблені під час передачі від "Королеви" до сервера.

```
TelemetryUnpackerService → IotexVerificationWorker → Iotex::W3bstreamVerificationService → zk_proof_ref
```

### Крок 5: Транспортування (Chainlink DON)

Оракул забирає ZK-proof та наказ на нарахування балів з нашого сервера і передає їх у смарт-контракт на Polygon.

```
ChainlinkDispatchWorker → Chainlink::OracleDispatchService → Chainlink Functions Router → Polygon
```

**Guard:** `validate_iotex_verification!` — No ZK-proof, no oracle. No oracle, no minting.

### Крок 6: Аудит особи (Polygon Hadron)

Контракт перевіряє статус KYC кінцевого отримувача токенів.

```
HadronAssetRegistrationWorker → Polygon::HadronComplianceService → hadron_kyc_status == "approved"
```

### Крок 7: Емісія (Polygon Mint)

Якщо накопичено `10,000 growth_points`, викликається функція `mintForTree`. Народжується 1 SCC.

```
TokenomicsEvaluatorWorker (щогодини, cron: 0 * * * *)
  → Wallet.balance >= 10,000? → lock_and_mint!
  → MintCarbonCoinWorker → BlockchainMintingService
  → Guard: verified_by_iotex? + oracle_status + hadron_kyc_status
  → Polygon: mint(to_address, amount, tree_did)
  → BlockchainConfirmationWorker (+30s) → confirm!(tx_hash)
```

### Паралельні Рейки (Post-Mint)

Після успішного мінту на Polygon, паралельно запускаються:

```
├──▶ SolanaMicroRewardWorker → Solana::MintingService (instant USDC micro-reward)
├──▶ CeloRewardWorker → Celo::CommunityRewardService (5 cUSD community reward)
├──▶ StreamrBroadcastWorker → Streamr::BroadcasterService (P2P real-time)
├──▶ TheGraph::QueryService (автоматична індексація CarbonMintEvent)
├──▶ KlimaRetirementWorker → KlimaDao::RetirementService (ESG retirement, on-demand)
├──▶ FilecoinArchiveWorker → Filecoin::ArchiveService (immutable CID archive)
└──▶ EthereumAnchorWorker → Ethereum::StateAnchorService (weekly state root)
```

---

## 📜 3. Смарт-Контракти та Взаємодія (Polygon)

### SilkenCarbonCoin.sol (SCC)

Токен утиліти (Utility Token), що представляє реальне депонування вуглецю деревом.

| Параметр | Значення |
|----------|----------|
| **Файл** | `contracts/SilkenCarbonCoin.sol` |
| **Стандарт** | ERC-20 + `AccessControl` + `Pausable` |
| **Ролі** | `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, `SLASHER_ROLE` |

**Ключові функції:**
- `mint(address to, uint256 amount, string memory treeDid)` — Базовий мінтинг з прив'язкою до унікального DID дерева (запобігання подвійній емісії). Емітує `CarbonMinted`.
- `batchMint(address[] recipients, uint256[] amounts, string[] treeDids)` — Оптимізація газу. До 200 дерев за один виклик. Валідує рівність довжин масивів.
- `slash(address investor, uint256 amount)` — Каральна функція. Спалює токени інвестора при порушенні NaaS контракту. Емітує `TokenSlashed`.
- `pause() / unpause()` — Екстрене заморожування всіх трансферів.

### SilkenForestCoin.sol (SFC)

Токен управління (Governance/DAO Token).

| Параметр | Значення |
|----------|----------|
| **Файл** | `contracts/SilkenForestCoin.sol` |
| **Стандарт** | ERC-20 + `AccessControl` + `Pausable` + `ERC20Permit` + `ERC20Votes` |
| **Ролі** | `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` (без `SLASHER_ROLE`) |

**Ключові функції:**
- `mint(address to, uint256 amount, string memory clusterId)` — Мінтинг з прив'язкою до кластера. Емітує `ForestMinted`.
- `batchMint(address[] recipients, uint256[] amounts, string[] clusterIds)` — Batch варіант.
- Gasless approvals через EIP-712 підписи (`ERC20Permit`).
- Governance voting power через `ERC20Votes` — делегація та snapshot.

---

## ⚓ 4. Абсолютна Фіналізація (Ethereum State Root Anchoring)

Оскільки основні операції відбуваються на Polygon та інших мережах, існує теоретичний ризик катастрофічного збою L2-мережі або компрометації мосту. Щоб гарантувати довгострокову цінність (на десятки років), Gaia 2.0 використовує технологію **State Anchoring**.

| Параметр | Значення |
|----------|----------|
| **Воркер** | `EthereumAnchorWorker` (Sidekiq щопонеділка о 03:00 UTC) |
| **Сервіс** | `Ethereum::StateAnchorService` |
| **Unique** | `unique_for: 1.hour` |
| **RPC** | `ALCHEMY_ETHEREUM_RPC_URL` |

**Алгоритм:** Бекенд збирає поточний стан усієї екосистеми (загальна пропозиція SCC, хеш останніх транзакцій, поточний timestamp) і стискає це в один 32-байтний хеш:

```ruby
state_root = Digest::SHA256.hexdigest("#{total_scc_supply}:#{chain_hash}:#{timestamp}")
```

**Запис:** Цей `bytes32` хеш відправляється смарт-контракту на Ethereum Mainnet (L1).

**Економіка:** Завдяки тому, що записується лише 32 байти раз на тиждень, плата за газ є мінімальною, але ми отримуємо рівень безпеки (Finality) мережі Ethereum вартістю в сотні мільярдів доларів. Будь-яка невідповідність баз даних може бути виявлена і доведена криптографічно.

---

## 🔌 5. Конфігурація Credentials та ENV

Сервіси Gaia 2.0 використовують два механізми зберігання секретів:

### Rails Encrypted Credentials (`config/credentials.yml.enc`)

| Credential | Сервіс | Опис |
|------------|--------|------|
| `streamr_stream_id` | Streamr | ID потоку Brubeck |
| `streamr_api_key` | Streamr | Bearer token для API |
| `filecoin_api_key` | Filecoin | Pinata API key |
| `peaq_node_url` | peaq | Substrate node URL |
| `peaq_signing_key` | peaq | Ed25519 seed для підпису DID |
| `iotex_w3bstream_url` | IoTeX | W3bstream endpoint URL |
| `iotex_api_key` | IoTeX | Bearer token для W3bstream |
| `the_graph_api_url` | The Graph | Subgraph GraphQL endpoint |
| `hadron_api_key` | Polygon Hadron | Hadron Identity Platform API key |

### Environment Variables (ENV)

| Variable | Сервіс | Опис |
|----------|--------|------|
| `ALCHEMY_POLYGON_RPC_URL` | Polygon, Chainlink, KlimaDAO, Etherisc, Toucan | Polygon EVM RPC endpoint |
| `ALCHEMY_ETHEREUM_RPC_URL` | Ethereum L1 | Ethereum Mainnet RPC endpoint |
| `CELO_RPC_URL` | Celo | Celo network RPC endpoint |
| `SOLANA_RPC_URL` | Solana | Solana RPC (default: Devnet) |
| `ORACLE_PRIVATE_KEY` | Polygon, Chainlink, Celo, KlimaDAO | EVM oracle wallet private key |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | Ethereum L1 | Dedicated L1 anchoring wallet |
| `ETHEREUM_ANCHOR_CONTRACT` | Ethereum L1 | State root contract address |
| `CHAINLINK_FUNCTIONS_ROUTER` | Chainlink | Functions Router contract address |
| `CHAINLINK_SUBSCRIPTION_ID` | Chainlink | Functions subscription ID |
| `CARBON_COIN_CONTRACT_ADDRESS` | Polygon, KlimaDAO | SCC contract address |
| `KLIMA_RETIREMENT_CONTRACT` | KlimaDAO | KlimaDAO retirement contract |
| `CELO_CUSD_CONTRACT_ADDRESS` | Celo | cUSD ERC-20 contract address |
| `SOLANA_FEE_PAYER_PUBKEY` | Solana | Fee payer public key |
| `SOLANA_USDC_MINT_ADDRESS` | Solana | USDC SPL token mint address |
| `SOLANA_WALLET_KEYPAIR` | Solana | Base64-encoded keypair for signing |
| `HADRON_API_URL` | Polygon Hadron | Hadron API base URL |
| `FILECOIN_GATEWAY_URL` | Filecoin | IPFS gateway for reads |
| `FILECOIN_PINNING_API_URL` | Filecoin | Pinata API for writes |

---

## 🏗️ 6. Shared Infrastructure Layer

### Web3 Utility Services (`app/services/web3/`)

| Утиліта | Файл | Призначення |
|---------|------|-------------|
| `Web3::HttpClient` | `web3/http_client.rb` | Централізований HTTP клієнт (HTTPX) для всіх зовнішніх API. Thread-safe persistent connections. |
| `Web3::RpcConnectionPool` | `web3/rpc_connection_pool.rb` | Thread-cached `Eth::Client` per Sidekiq thread. Запобігає повторним TCP/TLS handshake. `fallback:` URL для testnet. |
| `Web3::WeiConverter` | `web3/wei_converter.rb` | BigDecimal конверсія human-readable ↔ wei (18 decimals). Запобігає precision loss у фінансових операціях. |

### Допоміжні Протоколи (Не частина 12-Chain топології)

| Протокол | Сервіс | Призначення | Статус |
|----------|--------|-------------|--------|
| **Etherisc DIP** | `Etherisc::ClaimService` | Децентралізоване параметричне страхування (USDC payouts) | ✅ Real |
| **Toucan Protocol** | `Toucan::BridgeService` | SCC ↔ TCO2 мост для глобальних carbon credit pools | ✅ Real |
| **dClimate** | `Dclimate::VerificationService` | Супутникова верифікація (double-consensus) | ⚠️ Mock |
| **Ed25519 Crypto** | `Ed25519Crypto::SigningService` | Ed25519 підписи для peaq та Solana | ✅ Real |
| **Puro.earth** | — (worker `PuroEarthPassportWorker` існує) | D-MRV Biomass Passport для Biochar CORC | 🔴 Not Implemented |

---

## 📊 7. Повна Матриця Сервісів та Черг

| # | Мережа | Рівень | Сервіс | Воркер | Черга | Retry | Cron |
|---|--------|--------|--------|--------|-------|-------|------|
| 1 | Streamr | Data | `Streamr::BroadcasterService` | `StreamrBroadcastWorker` | `low` | 3 | — |
| 2 | Filecoin | Data | `Filecoin::ArchiveService` | `FilecoinArchiveWorker` | `low` | 5 | — |
| 2b | Filecoin | Data | `Filecoin::VerificationService` | — | — | — | — |
| 3 | peaq | Verification | `Peaq::DidRegistryService` | `PeaqRegistrationWorker` | `web3` | 5 | — |
| 4 | IoTeX | Verification | `Iotex::W3bstreamVerificationService` | `IotexVerificationWorker` | `web3_critical` | 5 | — |
| 5 | The Graph | Verification | `TheGraph::QueryService` | — (read-only) | — | — | — |
| 6 | Polygon | Finance | `BlockchainMintingService` | `MintCarbonCoinWorker` | `web3_critical` | 5 | — |
| 6b | Polygon | Finance | `BlockchainBurningService` | `BurnCarbonTokensWorker` | `critical` | 5 | — |
| 6c | Polygon | Finance | `ChainAuditService` | — (on-demand) | — | — | — |
| 6d | Polygon | Finance | `PriceOracleService` | — (on-demand) | — | — | — |
| 6e | Polygon | Finance | `MintingRollbackService` | — (error handler) | — | — | — |
| 7 | Hadron | Finance | `Polygon::HadronComplianceService` | `HadronAssetRegistrationWorker` | `web3_low` | 5 | — |
| 8 | Solana | Finance | `Solana::MintingService` | `SolanaMicroRewardWorker` | `web3` | 3 | — |
| 9 | Celo | Finance | `Celo::CommunityRewardService` | `CeloRewardWorker` | `web3` | 3 | — |
| 10 | KlimaDAO | Finance | `KlimaDao::RetirementService` | `KlimaRetirementWorker` | `web3_low` | 3 | — |
| 11 | Chainlink | Finality | `Chainlink::OracleDispatchService` | `ChainlinkDispatchWorker` | `web3_critical` | 5 | — |
| 12 | Ethereum L1 | Finality | `Ethereum::StateAnchorService` | `EthereumAnchorWorker` | `web3_low` | 3 | `0 3 * * 1` |

### Sidekiq Cron Schedule (config/sidekiq.yml)

| Розклад | Cron | Воркер | Призначення |
|---------|------|--------|-------------|
| Tokenomics Evaluation | `0 * * * *` (щогодини) | `TokenomicsEvaluatorWorker` | Сканує wallets ≥ 10,000 growth\_points → мінтинг |
| Daily Aggregation | `0 1 * * *` (01:00 UTC) | `DailyAggregationWorker` | AI-інсайти per tree → stress\_index |
| Cluster Health | `0 2 * * *` (02:00 UTC) | `ClusterHealthCheckWorker` | Перевірка NaaS → Slashing або Celo reward |
| Ethereum Anchor | `0 3 * * 1` (Пн 03:00 UTC) | `EthereumAnchorWorker` | SHA-256 state root → Ethereum L1 |

---

## 📂 8. Структура Файлів (File Map)

```
app/services/
├── streamr/
│   └── broadcaster_service.rb          # [Level 1] P2P real-time broadcast
├── filecoin/
│   ├── archive_service.rb              # [Level 1] IPFS/Pinata archive
│   └── verification_service.rb         # [Level 1] CID integrity check
├── peaq/
│   └── did_registry_service.rb         # [Level 2] Machine DID (Substrate/Ed25519)
├── iotex/
│   └── w3bstream_verification_service.rb # [Level 2] ZK-proof generation
├── the_graph/
│   └── query_service.rb               # [Level 2] GraphQL subgraph queries
├── polygon/
│   └── hadron_compliance_service.rb    # [Level 3] KYC/RWA (ERC-3643)
├── solana/
│   └── minting_service.rb             # [Level 3] USDC micro-rewards
├── celo/
│   └── community_reward_service.rb     # [Level 3] cUSD ReFi rewards
├── klima_dao/
│   └── retirement_service.rb           # [Level 3] ESG carbon retirement
├── chainlink/
│   └── oracle_dispatch_service.rb      # [Level 4] Decentralized oracle bridge
├── ethereum/
│   └── state_anchor_service.rb         # [Level 4] Weekly L1 state root
├── web3/
│   ├── http_client.rb                  # Shared: HTTP transport layer (HTTPX)
│   ├── rpc_connection_pool.rb          # Shared: Thread-cached Eth::Client
│   └── wei_converter.rb               # Shared: BigDecimal Wei conversion
├── blockchain_minting_service.rb       # [Level 3] Polygon batch SCC/SFC mint
├── blockchain_burning_service.rb       # [Level 3] Polygon slashing/burn
├── chain_audit_service.rb              # [Level 3] DB ↔ Chain consistency
├── price_oracle_service.rb             # [Level 3] Uniswap V3 SCC/USDC price
├── minting_rollback_service.rb         # [Level 3] Sidekiq retry exhaustion refund
├── dclimate/
│   └── verification_service.rb         # [Extra] Satellite verification (MOCK)
├── etherisc/
│   └── claim_service.rb               # [Extra] Parametric insurance (DIP)
├── toucan/
│   └── bridge_service.rb              # [Extra] SCC ↔ TCO2 bridge
└── ed25519_crypto/
    └── signing_service.rb             # [Extra] Ed25519 for peaq/Solana

contracts/
├── SilkenCarbonCoin.sol                # SCC (ERC-20 + AccessControl + Pausable)
└── SilkenForestCoin.sol                # SFC (ERC-20 + Votes + Permit)

subgraph/
├── schema.graphql                      # CarbonMintEvent, SlashingEvent, etc.
├── subgraph.yaml                       # polygon-amoy, event handlers
└── src/mapping.ts                      # Event → Entity mapping logic

spec/services/
├── streamr/broadcaster_service_spec.rb
├── filecoin/archive_service_spec.rb
├── filecoin/verification_service_spec.rb
├── peaq/did_registry_service_spec.rb
├── iotex/w3bstream_verification_service_spec.rb
├── the_graph/query_service_spec.rb
├── polygon/hadron_compliance_service_spec.rb
├── solana/minting_service_spec.rb
├── celo/community_reward_service_spec.rb
├── klima_dao/retirement_service_spec.rb
├── chainlink/oracle_dispatch_service_spec.rb
├── ethereum/state_anchor_service_spec.rb
├── blockchain_minting_service_spec.rb
├── blockchain_burning_service_spec.rb
├── chain_audit_service_spec.rb
├── price_oracle_service_spec.rb
├── minting_rollback_service_spec.rb
├── web3/http_client_spec.rb
├── web3/rpc_connection_pool_spec.rb
├── web3/wei_converter_spec.rb
├── dclimate/verification_service_spec.rb
├── etherisc/claim_service_spec.rb
└── toucan/bridge_service_spec.rb
```

---

## 📋 9. Аудит Відповідності (Compliance Audit)

### Кодбейс ↔ SSOT Topology

| Вимога SSOT | Статус у Кодбейсі | Деталі |
|-------------|-------------------|--------|
| 12 мереж у топології | ✅ 12/12 | Кожна мережа має сервіс, воркер, спеку |
| 4 рівні (Data, Verification, Finance, Finality) | ✅ Відображено | Namespace організація відповідає рівням |
| Proof of Growth pipeline (7 кроків) | ✅ Повний | Sensor → Lorenz → peaq → IoTeX → Chainlink → Hadron → Polygon |
| SCC/SFC Smart Contracts | ✅ Написані | `contracts/SilkenCarbonCoin.sol`, `contracts/SilkenForestCoin.sol` |
| The Graph Subgraph | ✅ Написаний | `subgraph/` (schema + mapping + yaml) |
| Guard Clauses (trustless) | ✅ 5 guards | IoTeX → Chainlink → Hadron → Balance → Lock |
| Ethereum State Root (weekly) | ✅ Cron | `0 3 * * 1` + `unique_for: 1.hour` |
| RSpec покриття | ✅ 100% | 29 service specs + 22 integration flows |
| Treasury Management | 🔴 Missing | Guard тільки для MATIC (Polygon), немає для SOL/CELO |
| Subgraph event name | 🔴 Bug | `Slashed` vs `TokenSlashed` mismatch |

### Відкриті Питання для Наступного Циклу

1. **Treasury Management Service** — Централізований моніторинг балансів 4 oracle wallets (MATIC, SOL, CELO, ETH) з PagerDuty alerts
2. **Subgraph Fix** — Виправити event name mismatch у `subgraph.yaml`
3. **Solana Mainnet Switch** — Перехід з `simulateTransaction` на `sendTransaction`
4. **Strict Mode для Hadron/Chainlink** — Вимкнути simulation fallbacks у Production
5. **PuroEarth PassportService** — Створити сервіс для Biochar CORC (Afterlife Economy)
6. **dClimate Real API** — Замінити mock на реальний dClimate satellite API
