# 05_01: Мультичейн Архітектура (12-Chain Ecosystem)

## 🎯 Мета

Зафіксувати повну топологію та взаємодію 12 незалежних блокчейн-мереж і децентралізованих протоколів, що утворюють Кіберфізичну Державу Gaia 2.0. Цей документ деталізує, як фізичні дані з лісу проходять шлях від локального ZK-доказу до глобальної фінансової емісії та фіналізації в Ethereum L1.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Всі 12 мереж мають відповідний Ruby-сервіс, Sidekiq-воркер та RSpec-специфікацію.
- **Синхронізація:** 2026-04-15
- **Пов'язані модулі:**
  - Proof of Growth → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)
  - Токеноміка → [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC)
  - Ethereum L1 → [`05_04_Ethereum_L1_State_Anchor`](05_04_Ethereum_L1_State_Anchor)

---

## 🏗️ 0. Модульний DePIN Стек: Рольова Карта (The Protocol Symphony)

> **Нотатка інтегрована (2026-03-25).** Архітектурне обґрунтування: ЧОМУ кожна мережа існує у стеку SilkenNet і яку унікальну функцію вона виконує. Це доповнення до таблиці імплементації (розділ 1).

SilkenNet не обирає один блокчейн. Система використовує модульний DePIN стек, де **кожна мережа вирішує конкретну проблему**, недосяжну для інших. Це не "ми скрізь" — це "ми використовуємо найкращий інструмент для кожного шару".

```
Фізичний ліс
     │ (EBFC → LoRa → Queen Gateway → Rails API)
     ▼
┌────────────────────────────────────────────────────────────────────┐
│ L1: Identity      peaq         — ХТО це? (DID машини, паспорт дерева) │
│ L2: Verification  IoTeX        — це ПРАВДА? (ZK-proof, hardware trust) │
│ L3: Oracle/Bridge Chainlink    — З'ЄДНАТИ (мультичейн доставка даних) │
│ L4: Execution     Solana       — ПЛАТИТИ (мікроплатежі, висока TPS)    │
│ L5: Memory        Filecoin     — ПАМ'ЯТАТИ (вічний незмінний архів)    │
│ L6: Finality      Polygon+L1   — ЮРИДИЧНО ЗАФІКСУВАТИ (RWA, SCC токен) │
└────────────────────────────────────────────────────────────────────┘
```

| Шар | Мережа | Унікальна Роль | Чому саме ця мережа? |
|---|---|---|---|
| **Ідентичність** | **peaq** | Паспорт дерева — Machine DID | Найкраще заточений під економіку машин (DePIN). Кожне дерево при провізіонінгу отримує незмінний `did:peaq:0x...` — ідентифікатор, що впізнається у будь-якій мережі |
| **Верифікація** | **IoTeX (W3bstream)** | Детектор брехні — ZK-proof | Hardware-to-Cloud довіра. W3bstream перевіряє, що дані прийшли саме з фізичного STM32, а не з симулятора. Без цього токени — просто цифри, з цим — Real World Assets |
| **Оракул/Міст** | **Chainlink** | Нервова система — CCIP/Functions | "Швейцарія" крипто. Забирає ZK-proof і верифіковані дані атрактора Лоренца з Rails backend та "розливає" по Solana, Polygon, Ethereum одночасно через CCIP |
| **Виконання** | **Solana** | Швидкі гроші — мікроплатежі | Єдина мережа, яка витримає потік від 100M+ дерев без захмарних комісій. Proof of Growth відбувається тут: кожен мм росту = транзакція |
| **Зберігання** | **Filecoin/IPFS** | Вічна пам'ять | `AuditLogWorker` щодня архівує всі сирі дані телеметрії в IPFS/Filecoin. Через 10 років інституційний інвестор може перевірити кожну секунду життя дерева за яке він купив SCC |
| **Фіналізація** | **Polygon + Ethereum L1** | Юридична фіксація — RWA | Polygon: SCC/SFC мінтинг (ERC-20), параметричне страхування (ERC-3643 для KYC). Ethereum L1: щотижневий SHA-256 state root anchoring — рівень безпеки вартістю сотні млрд $ |

### Відповідь на питання "Навіщо стільки мереж?"

> Коли аудитор або інвестор запитає: *"Навіщо вам 12 блокчейнів?"*, ваша відповідь:
>
> **«SilkenNet — це агностична інфраструктура. Ми не обираємо між Solana та Ethereum. peaq знає, ХТО це. IoTeX знає, що це ПРАВДА. Filecoin ПАМ'ЯТАЄ це назавжди. Solana ПЛАТИТЬ за це миттєво. Chainlink З'ЄДНУЄ це в одне ціле. Polygon ЮРИДИЧНО ФІКСУЄ цінність. Ethereum ГАРАНТУЄ незмінність на десятки років. Разом — це Протокол Життя, вищий за будь-який окремий блокчейн.»**

### Permissionless Integration (Без Гранту)

Жодна з цих інтеграцій не потребує дозволу від засновників протоколів. Всі SDK відкриті:

```ruby
# Rails 8.1 як Диригент — Blockchain::Orchestrator
# Підключення через відкриті SDK/бібліотеки:
# - ethers.rb / eth gem    → Polygon, Ethereum
# - solana-web3.js         → Solana (через Node.js bridge або HTTP API)
# - chainlink-ruby          → Chainlink Functions (або HTTP API)

# Оплата газу для 100 дерев (старт): ~$100 на всі мережі разом
```

> **Для грантових заявок:** Коли ви кажете "ми використовуємо стек Solana + peaq + Chainlink + IoTeX + Filecoin", інженери розуміють: ви не винаходите велосипед, ви будуєте хмарочос з найкращих у світі матеріалів.


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
| 8 | Solana | `Solana::MintingService` | ✅ Real | Ed25519-signed `sendTransaction` (base64). Balance guard: 0.05 SOL |
| 9 | Celo | `Celo::CommunityRewardService` | ✅ Real | ERC-20 transfer cUSD через Celo RPC |
| 10 | KlimaDAO | `KlimaDao::RetirementService` | ✅ Real | Approve + Retire (два ERC-20 виклики) |
| 11 | Chainlink | `Chainlink::OracleDispatchService` | ⚠️ Hybrid | Реальний Chainlink Functions Router + stub коли credentials відсутні |
| 12 | Ethereum L1 | `Ethereum::StateAnchorService` | ✅ Real | `storeStateRoot(bytes32)` через Alchemy Ethereum RPC |

**Легенда:** ✅ Real = Бойова імплементація з реальними RPC-викликами · ⚠️ Hybrid = Працює в реальному режимі з credentials, fallback до симуляції без них · ⚠️ Devnet = Бойова логіка, але транзакції йдуть на Devnet (simulateTransaction)

---

## 🛑 Відкриті Блокери

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

> **Режими роботи:** `WEB3_STRICT_MODE=true` → raises `ComplianceError` при відсутності credentials (Production). Без strict mode — simulation fallback для dev/test.

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
2. `oracle_status_fulfilled?` (enum method)
3. `verify_oracle_balance!` — баланс SOL ≥ 0.05 (50M lamports)

**Мікро-винагорода:** Base reward + bonus per growth\_point, конвертовано в lamports → USDC

Solana `Solana::MintingService` використовує `sendTransaction` з Ed25519-підписом. ATA отримувача резолюється динамічно через `getTokenAccountsByOwner`.

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

> **Режими роботи:** `WEB3_STRICT_MODE=true` → raises `DispatchError` при відсутності `CHAINLINK_FUNCTIONS_ROUTER`. Без strict mode — stub `request_id` для dev/test.

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
| Серверний Lorenz | `app/services/silken_net/attractor

.rb` (BigDecimal, 18-digit precision) |
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

| Параметр | Значення |
|----------|----------|
| **Файл** | `contracts/SilkenCarbonCoin.sol` |
| **Стандарт** | ERC-20 + `AccessControl` + `Pausable` + `ERC20Permit` |
| **Ролі** | `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, `SLASHER_ROLE` |

**Ключові функції:**
- `mint(address to, uint256 amount, string memory treeDid)` — Базовий мінтинг. Емітує `CarbonMinted`.
- `batchMint(address[] recipients, uint256[] amounts, string[] treeDids)` — До 200 дерев за один виклик.
- `slash(address investor, uint256 amount)` — Спалює токени при порушенні. Емітує `TokenSlashed`.
- `pause() / unpause()` — Екстрене заморожування.
- `nonces(address)` — Override для ERC20Permit/Nonces MRO сумісності.
- Gasless approvals через EIP-2612 (`ERC20Permit`) — дозволяє DEX/P2P marketplace інтеграцію без газу для власників SCC.

### SilkenForestCoin.sol (SFC)

| Параметр | Значення |
|----------|----------|
| **Файл** | `contracts/SilkenForestCoin.sol` |
| **Стандарт** | ERC-20 + `AccessControl` + `Pausable` + `ERC20Permit` + `ERC20Votes` |
| **Ролі** | `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` |

**Ключові функції:**
- `mint(address to, uint256 amount, string memory clusterId)` — Мінтинг з прив'язкою до кластера.
- `batchMint(...)` — Batch варіант.
- Gasless approvals через EIP-712 (`ERC20Permit`).
- Governance voting power (`ERC20Votes`).

---

## ⚓ 4. Абсолютна Фіналізація (Ethereum State Root Anchoring)

| Параметр | Значення |
|----------|----------|
| **Воркер** | `EthereumAnchorWorker` (Sidekiq щопонеділка о 03:00 UTC) |
| **Сервіс** | `Ethereum::StateAnchorService` |
| **RPC** | `ALCHEMY_ETHEREUM_RPC_URL` |

```ruby
state_root = Digest::SHA256.hexdigest("#{total_scc_supply}:#{chain_hash}:#{timestamp}")
```

Цей `bytes32` хеш записується в смарт-контракт на Ethereum Mainnet раз на тиждень. Рівень безпеки Ethereum (сотні мільярдів $) за мінімальну плату за газ.

---

## 🔌 5. Конфігурація Credentials та ENV

### Rails Encrypted Credentials

| Credential | Сервіс |
|------------|--------|
| `streamr_stream_id`, `streamr_api_key` | Streamr |
| `filecoin_api_key` | Filecoin/Pinata |
| `peaq_node_url`, `peaq_signing_key` | peaq |
| `iotex_w3bstream_url`, `iotex_api_key` | IoTeX |
| `the_graph_api_url` | The Graph |
| `hadron_api_key` | Polygon Hadron |

### Environment Variables

| Variable | Сервіс |
|----------|--------|
| `ALCHEMY_POLYGON_RPC_URL` | Polygon, Chainlink, KlimaDAO |
| `ALCHEMY_ETHEREUM_RPC_URL` | Ethereum L1 |
| `CELO_RPC_URL` | Celo |
| `SOLANA_RPC_URL` | Solana |
| `ORACLE_PRIVATE_KEY` | EVM oracle wallet |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | L1 anchoring wallet |
| `CARBON_COIN_CONTRACT_ADDRESS` | SCC contract |
| `CHAINLINK_FUNCTIONS_ROUTER` | Chainlink |
| `CHAINLINK_SUBSCRIPTION_ID` | Chainlink |
| `KLIMA_RETIREMENT_CONTRACT` | KlimaDAO |
| `SOLANA_USDC_MINT_ADDRESS` | Solana USDC |
| `FILECOIN_PINNING_API_URL` | Pinata |

---

## 🏗️ 6. Shared Infrastructure Layer

| Утиліта | Призначення |
|---------|-------------|
| `Web3::HttpClient` | Централізований HTTP клієнт (HTTPX), thread-safe |
| `Web3::RpcConnectionPool` | Thread-cached `Eth::Client` / `Web3::ResilientClient` per Sidekiq thread. Підтримує fallback cascade через `fallback_env_keys`. При одному URL повертає plain `Eth::Client` (без overhead); при кількох — `Web3::ResilientClient`. |
| `Web3::ResilientClient` | Circuit Breaker + RPC fallback cascade: Primary→Secondary→Public. `MAX_FAILURES=3` → `CIRCUIT_OPEN_DURATION=60s`. Розпізнає `Net::ReadTimeout`, `Errno::ECONNREFUSED`, HTTP 429. Thread-safe (Mutex). `provider_health` → Prometheus. |
| `Web3::WeiConverter` | BigDecimal конверсія human-readable ↔ wei |

---

## 📊 7. Повна Матриця Сервісів та Черг

| # | Мережа | Рівень | Воркер | Черга | Retry | Cron |
|---|--------|--------|--------|-------|-------|------|
| 1 | Streamr | Data | `StreamrBroadcastWorker` | `low` | 3 | — |
| 2 | Filecoin | Data | `FilecoinArchiveWorker` | `low` | 5 | — |
| 3 | peaq | Verification | `PeaqRegistrationWorker` | `web3` | 5 | — |
| 4 | IoTeX | Verification | `IotexVerificationWorker` + `Web3CircuitBreaker` | `web3_critical` | 5 | — |
| 5 | The Graph | Verification | — (read-only) | — | — | — |
| 6 | Polygon | Finance | `MintCarbonCoinWorker` | `web3_critical` | 5 | — |
| 6b | Polygon | Finance | `BurnCarbonTokensWorker` | `critical` | 5 | — |
| 7 | Hadron | Finance | `HadronAssetRegistrationWorker` | `web3_low` | 5 | — |
| 8 | Solana | Finance | `SolanaMicroRewardWorker` | `web3` | 3 | — |
| 9 | Celo | Finance | `CeloRewardWorker` | `web3` | 3 | — |
| 10 | KlimaDAO | Finance | `KlimaRetirementWorker` | `web3_low` | 3 | — |
| 11 | Chainlink | Finality | `ChainlinkDispatchWorker` + `Web3CircuitBreaker` | `web3_critical` | 5 | — |
| 12 | Ethereum L1 | Finality | `EthereumAnchorWorker` | `web3_low` | 3 | `0 3 * * 1` |
| 13 | Cross-chain | Treasury | `TreasuryMonitorWorker` | `web3_low` | 3 | `*/15 * * * *` |
| 14 | Polygon | Gas Optimization | `MintBatchCollectorWorker` | `web3` | 3 | `*/5 * * * *` |

---

## 📋 8. Відкриті Питання для Наступного Циклу

1. **PuroEarth PassportService** — Biochar CORC (Afterlife Economy)
2. **dClimate Real API** — Замінити mock на реальний satellite API
