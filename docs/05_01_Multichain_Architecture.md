# 05_01: Мультичейн Архітектура (12-Chain Ecosystem)

## 🎯 Мета

Зафіксувати повну топологію та взаємодію 12 незалежних блокчейн-мереж і децентралізованих протоколів, що утворюють Кіберфізичну Державу SilkenNet. Цей документ деталізує, як фізичні дані з лісу проходять шлях від локального ZK-доказу до глобальної фінансової емісії та фіналізації в Ethereum L1.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Мультичейн архітектура повністю спроєктована. Структурний скелет усіх 12 мереж присутній у кодбейсі. Всі сервіси мають RSpec-покриття.
- **Відкрите:** dClimate real API + Production credentials (S3.2), chain-outage DR (§8) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Proof of Growth (consensus, верифікація) |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | Токеноміка (SCC/SFC контракти) |
| [`05_04` — Ethereum L1 State Anchor](05_04_Ethereum_L1_State_Anchor) | Ethereum L1 фіналізація (state root) |
| [`05_05` — Slashing and Risk Policy](05_05_Slashing_and_Risk_Policy) | Slashing/burn-політика (що тригерить вилучення SCC) |
| [`05_06` — Governance and DAO](05_06_Governance_and_DAO) | DAO governance (Governor/Timelock у стеку контрактів) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Chain-сервіси (`Blockchain::Orchestrator`) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (S3.2 dClimate real-API, DR §8) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [0. Модульний DePIN Стек: Рольова Карта (The Protocol Symphony)](#-0-модульний-depin-стек-рольова-карта-the-protocol-symphony)
- [1. Топологія 12 Мереж (The 12-Network Stack)](#-1-топологія-12-мереж-the-12-network-stack)
- [2. Консенсус "Proof of Growth" (Трубопровід Верифікації)](#-2-консенсус-proof-of-growth-трубопровід-верифікації)
- [3. Смарт-Контракти та Взаємодія (Polygon)](#-3-смарт-контракти-та-взаємодія-polygon)
- [4. Абсолютна Фіналізація (Ethereum State Root Anchoring)](#-4-абсолютна-фіналізація-ethereum-state-root-anchoring)
- [5. Конфігурація Credentials та ENV](#-5-конфігурація-credentials-та-env)
- [6. Shared Infrastructure Layer](#-6-shared-infrastructure-layer)
- [7. Повна Матриця Сервісів та Черг](#-7-повна-матриця-сервісів-та-черг)
- [8. Disaster Recovery / Chain Outage Strategy (S6.11)](#-8-disaster-recovery--chain-outage-strategy-s611)
<!-- TOC:AUTO:END -->

---

## 🏗️ 0. Модульний DePIN Стек: Рольова Карта (The Protocol Symphony)

> **Архітектурне обґрунтування:** ЧОМУ кожна мережа існує у стеку SilkenNet і яку унікальну функцію вона виконує (доповнює таблицю імплементації §1).

SilkenNet не обирає один блокчейн. Система використовує модульний DePIN стек, де **кожна мережа вирішує конкретну проблему**, недосяжну для інших. Це не "ми скрізь" — це "ми використовуємо найкращий інструмент для кожного шару".

```
Фізичний ліс
     │ (EBFC → LoRa → Queen Gateway → Rails API)
     ▼
┌────────────────────────────────────────────────────────────────────┐
│ 1.  Identity      peaq         — ХТО це? (DID машини, паспорт дерева) │
│ 2.  Verification  IoTeX        — це ПРАВДА? (ZK-proof, hardware trust) │
│ 3.  Oracle/Bridge Chainlink    — З'ЄДНАТИ (мультичейн доставка даних) │
│ 4.  Execution     Solana       — ПЛАТИТИ (мікроплатежі, висока TPS)    │
│ 5.  Memory        Filecoin     — ПАМ'ЯТАТИ (вічний незмінний архів)    │
│ 6.  Finality      Polygon+L1   — ЮРИДИЧНО ЗАФІКСУВАТИ (RWA, SCC токен) │
└────────────────────────────────────────────────────────────────────┘
```

| Шар | Мережа | Унікальна Роль | Чому саме ця мережа? |
|---|---|---|---|
| **Ідентичність** | **peaq** | Паспорт дерева — Machine DID | Найкраще заточений під економіку машин (DePIN). Кожне дерево при провізіонінгу отримує незмінний `did:peaq:0x...` — ідентифікатор, що впізнається у будь-якій мережі |
| **Верифікація** | **IoTeX (W3bstream)** | Детектор брехні — ZK-proof | Hardware-to-Cloud довіра через ZK-proof. **Чесно (TRL):** сьогодні доводить цілісність pipeline + прив'язку до on-chain peaq DID (master-backed атестація), а НЕ криптодоказ «саме цей STM32». Доказ фізичного походження = true-DePIN North-Star по ladder ([`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)); RWA-легітимність доповнює ЗВТ-метрологія (STK.5). «Дані з заліза» — мета, до якої будуємось |
| **Оракул/Міст** | **Chainlink** | Нервова система — CCIP/Functions | "Швейцарія" крипто. **Vision-шар, unwired (ARCH.53-демоут):** on-chain dispatch прибрано (LINK-cost без DON-callback'а); сьогодні мінт іде PATH 2 tokenomics (чесна L0-custodial модель + ex-post clawback — [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)). Замикання PATH 1 (DON-інженерія) = post-TRL-3 рішення |
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
| 11 | Chainlink | `Chainlink::OracleDispatchService` | ⚪ Demoted | **[ARCH.53]** On-chain `sendRequest` ВИЛУЧЕНО (LINK-cost за callback, що не прилетить: DON-нога unwired — нема Functions JS-source / consumer / relayer, tx_hash≠requestId). `dispatch!` = internal correlation-marker (`chainlink_request_id` живе dedup-ключем Solana + idempotency-guard'ом); мінт іде PATH 2 tokenomics. Callback-endpoint (`/oracle_callbacks`, HMAC) лишається live для майбутнього PATH 1 / manual-fulfillment |
| 12 | Ethereum L1 | `Ethereum::StateAnchorService` | ✅ Real | `storeStateRoot(bytes32)` через Alchemy Ethereum RPC |

**Легенда:** ✅ Real = Бойова імплементація з реальними RPC-викликами · ⚠️ Hybrid = Працює в реальному режимі з credentials, fallback до симуляції без них · ⚠️ Devnet = Бойова логіка, але транзакції йдуть на Devnet (simulateTransaction)

---

## 🌐 1. Топологія 12 Мереж (The 12-Network Stack)

SilkenNet не покладається на один блокчейн. Для забезпечення максимальної безпеки, масштабованості та compliance, система розподіляє функції (Зберігання, Верифікація, Економіка, Фіналізація) між спеціалізованими протоколами.

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

Генерація Zero-Knowledge доказів цілісності pipeline + прив'язки до peaq DID (W3bstream — **НЕ** TEE). ⚠️ **Чесно про trust:** поточний рівень = L0 custodial (`hardware_signature` = backend-HKDF-derived — підтверджує цілісність шляху, але **не** доводить кремнієве походження); hardware-origin — true-DePIN North-Star (L2 trust-ladder → [`05_02`](05_02_Proof_of_Growth_Pipeline)). ZK ускладнює підробку скриптом, але origin-гарантію дає лише L2.

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
- `fetch_protocol_financials` — singleton `ProtocolFinancial` entity (`totalMinted`, `totalBurned`)

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
}

type SlashingEvent @entity { ... }
```

---

### Рівень 3: Фінанси та Економіка (Primary Chain & Parallel Rails)

#### 6. Polygon (Primary EVM)

Головна артерія системи. Тут розгорнуті наші ключові смарт-контракти (`SilkenCarbonCoin.sol`, `SilkenForestCoin.sol`, `SilkenGovernor.sol`, `SilkenTimelock.sol`, `ProtocolParameters.sol`). Вибраний через низьку вартість транзакцій та сумісність з EVM.

| Параметр | Значення |
|----------|----------|
| **Сервіси** | `BlockchainMintingService`, `BlockchainBurningService`, `ChainAuditService`, `PriceOracleService`, `MintingRollbackService` |
| **Воркери** | `MintCarbonCoinWorker`, `BurnCarbonTokensWorker`, `BlockchainConfirmationWorker`, `TokenomicsEvaluatorWorker`, `Governance::ParameterSyncWorker` |
| **Черги** | `web3_critical` (мінтинг, підтвердження), `critical` (спалювання), `default` (токеноміка), `web3_low` (governance sync) |
| **ENV** | `ALCHEMY_POLYGON_RPC_URL`, `ORACLE_MINTER_PRIVATE_KEY`, `ORACLE_SLASHER_PRIVATE_KEY` (dedicated-only — legacy `ORACLE_PRIVATE_KEY` retired [INF.22]; [E.2] розділені ключі mint/slash, blast-radius), `CARBON_COIN_CONTRACT_ADDRESS`, `PROTOCOL_PARAMETERS_CONTRACT_ADDRESS` |
| **Спеки** | `spec/services/blockchain_minting_service_spec.rb`, `spec/services/blockchain_burning_service_spec.rb`, `spec/services/chain_audit_service_spec.rb`, `spec/services/price_oracle_service_spec.rb`, `spec/services/minting_rollback_service_spec.rb`, `spec/workers/governance/parameter_sync_worker_spec.rb` |

**Governance DAO (✅ ARCH.4):**

Повний governance pipeline для зміни протокольних параметрів через SFC voting:

| Контракт | Файл | Роль |
|----------|------|------|
| `SilkenGovernor` | `contracts/SilkenGovernor.sol` | OZ Governor + GovernorVotes + GovernorTimelockControl + GovernorCountingSimple + GovernorVotesQuorumFraction (4%). votingDelay=43200 blocks (~1 day), votingPeriod=302400 blocks (~7 days), proposalThreshold=10 000 SFC (0.01% MAX_SUPPLY, anti-spam — CONTRACT.1) |
| `SilkenTimelock` | `contracts/SilkenTimelock.sol` | TimelockController з 48h мінімальною затримкою. Proposer: Governor, Executor: address(0) (permissionless після delay) |
| `ProtocolParameters` | `contracts/ProtocolParameters.sol` | On-chain registry з GOVERNANCE_ROLE. Well-known keys: 8 Lorenz (σ/ρ/β/dt/iterations/z_min/z_max/z_target — **DCI-locked**, backend свідомо не синхронізує; FW.7) + 9 економічних (emission_threshold, dynamic_tax_rate, insurance_pool_threshold, scc_per_tonne_co2, scc_fallback_price_usd, slash_threshold, stress_threshold, slash_gamma, slash_penalty_factor_max — GOV.1 read-path у [`05_06 §7`](05_06_Governance_and_DAO)). Fixed-point 18 decimals |

**Flash Loan Defense:** snapshot voting (`getPastVotes`), 1-day voting delay, 4% quorum, 48h timelock.

**Guard Clauses (BlockchainMintingService):**
1. `verified_by_iotex? == true` — ZK-proof з IoTeX (**лише Path 1**, oracle-driven з `telemetry_log`)
2. `oracle_status_fulfilled?` (enum method, prefix) — Chainlink Oracle підтвердив (**лише Path 1**)
3. `wallet.kyc_approved_for_minting?` [KYC.1] — KYC бенефіціара адреси (власна → власний статус; custodial → успадковує org), **усі шляхи**; non-approved → per-tx SKIP
4. Oracle balance ≥ `0.05 MATIC` (default; `oracle_min_balance_matic` — governance-aware [INF.22]) — достатньо газу
5. Kredis distributed lock (**120s** expiration — покриває dry-run + binary-search worst-case ~130s, [S6.5]) — запобігає подвійному мінтингу
6. **[ARCH.62]** per-token circuit-break — `mint_circuit_broken?(token_type)` (Kredis `mint:circuit_broken:<token>`, ставить `Treasury::MonitorService` при volume-аномалії за `:mint_circuit_breaker_enabled`); tripped → HOLD того токена у `:pending` (re-runnable, **НЕ** escalate), fail-open на Redis-збої. Inert default → [`00_07` ARCH.62](00_07_Action_Plan_Tracker)

**HYBRID PROTOCOL GAIA:** 2% Dynamic Tax на carbon\_coin мінтинг, коли insurance pool потребує поповнення: бенефіціар отримує `amount − tax`, а податок їде ОДНИМ агрегованим `DAO_TREASURY`-записом на підбатч (`TAX_BATCH_*`), не по одному запису на транзакцію. ⚠️ Окремого отримувача-форестера в цьому тракті НЕМАЄ — `forester_share_amount` живе на `NaasContract` і диспенс-шляху не має ([`05_05 §3.1`](05_05_Slashing_and_Risk_Policy)).

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
| **Воркер** | `SolanaMicroRewardWorker` (per-event) · `SolanaBatchPayoutWorker` (batch payout [E.61]) |
| **Черга** | `web3` (пріоритет 7) |
| **Retry** | 3 |
| **ENV** | `SOLANA_RPC_URL` (default: Devnet), `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_MINT_AUTHORITY_PUBKEY`, `SOLANA_USDC_MINT_ADDRESS`, `SOLANA_WALLET_KEYPAIR` |
| **Спека** | `spec/services/solana/minting_service_spec.rb` |

**Trustless Requirements (Guard Clauses):**
1. `verified_by_iotex? == true`
2. `oracle_status_fulfilled?` (enum method)
3. `verify_oracle_balance!` — баланс SOL ≥ 0.05 (50M lamports)

**Мікро-винагорода:** Base reward + bonus per growth\_point, конвертовано в lamports → USDC

> **⚠️ Scale (нот.4):** per-event Solana tx на КОЖЕН fulfilled telemetry на planetary-scale (мільйони verified-подій/добу) зрівнює fees з винагородою + RPC-навантаження. **Закрито batch payouts [E.61]:** при ненульовому порозі `solana_batch_threshold_usdc` (governance-aware `SystemParameter`, в USDC) `SolanaMicroRewardWorker` акумулює винагороду per-wallet у Kredis замість окремої tx; годинний `SolanaBatchPayoutWorker` (`Solana::BatchPayoutService`) виплачує накопичене одним `transferChecked` ATA→ATA, щойно сума перетне поріг. **[ARCH.45] idempotency:** durable intent-marker (signature обчислено до broadcast) + `reconcile_in_flight` (on-chain звірка `unsettled_within`) + **confirm-gated** Kredis-settle (decrement лише після on-chain confirm, за сумою самої tx → concurrent надбавки виживають) закривають double-pay crash-window — наступний годинний цикл звіряє on-chain замість сліпої повторної виплати. **Backward-compat:** поріг 0 → миттєва per-event виплата (поведінка за замовчуванням).

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
| **ENV** | `CELO_RPC_URL` ⚠️ без значення → fallback на Alfajores **TESTNET** (реальні cUSD на testnet, обходить `web3_network_guard`; E.49 → mainnet endpoint обов'язковий), **[ARCH.50]** `ORACLE_CELO_PRIVATE_KEY` (dedicated Celo-підписант, no fallback — ізолює blast-radius від Polygon-флоту), `CELO_CUSD_CONTRACT_ADDRESS` |
| **Спека** | `spec/services/celo/community_reward_service_spec.rb` |

**Умови нарахування:**
- `stress_index ≤ 0.2` (кластер здоровий)
- `fraud_detected == false`
- Організація має зареєстровану crypto-адресу

**Сума:** 5 cUSD на здоровий кластер на день

**Особливості:** **[ARCH.50]** Money-path-hardened — durable `:pending` intent ПЕРЕД broadcast + dedup на ЛОГІЧНИЙ `reward_date` ВСЕРЕДИНІ chain-prefix Kredis-lock (`lock:web3:celo:oracle:`) + Celo-aware reconcile (`CeloConfirmationWorker`, бо `BlockchainConfirmationWorker` хардкоднутий на Polygon) + deterministic-vs-transient rescue split (dedicated `ORACLE_CELO_PRIVATE_KEY`). Закрив детермінований daily double-pay (логічний ключ ≠ `created_at`-партиція). **[ARCH.64]** Той reconcile покриває лише `:sent`; застрягле `:pending` без tx_hash (transient-timeout → dedup-skip, self-masking retry) підбирає `CeloRewardReconcileWorker` cron (:25/:55) → `:manual_review` (money-safe, не blind re-pay; раніше — тиха недоплата cUSD, дім [`06_08 §2.2`](06_08_Resilience_and_Failover_Policy)).

#### 10. KlimaDAO (ESG Carbon Retirement)

Шлюз для корпорацій. Дозволяє миттєво списувати (Retire) токени SCC для покриття корпоративного ESG-боргу (Carbon Offsetting) безпосередньо через смарт-контракти.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `KlimaDao::RetirementService` |
| **Воркер** | `KlimaRetirementWorker` |
| **Черга** | `web3_low` (пріоритет 8) |
| **Retry** | 3 |
| **ENV** | `ORACLE_KLIMA_PRIVATE_KEY` (activation-gated dedicated-підписант — INF.22), `CARBON_COIN_CONTRACT_ADDRESS`, `KLIMA_RETIREMENT_CONTRACT` |
| **RPC** | `ALCHEMY_POLYGON_RPC_URL` (Polygon, де розгорнуто KlimaDAO) |
| **Спека** | `spec/services/klima_dao/retirement_service_spec.rb` |

**Два кроки (Atomic):**
1. **Approve** — дозвіл на трансфер SCC до KlimaDAO контракту
2. **Retire** — безповоротне спалення `retire(scc × 10**18)` → інкремент `wallet.esg_retired_balance` (лічильник погашених **МОНЕТ**)

**Захист:** Pessimistic locking + гард запасу монет (`net_minted_supply`, [ARCH.95]). ⚠️ «Переходу балансу» тут НЕМА і не було правильним: балансові колонки гаманця погашення не рухає взагалі — `balance` лишається gross-лічильником балів ([`04_01 §6`](04_01_Data_Models_and_Entities)), а вилучення з обігу фіксує рядок `BlockchainTransaction(direction: :burn)`.

---

### Рівень 4: Мости та Фіналізація (Bridging & Finality)

#### 11. Chainlink (DON) — ⚪ demoted до internal correlation-marker [ARCH.53]

**Чесна модель довіри:** on-chain `sendRequest` **вилучено** — DON-нога (Functions JS-source / consumer `fulfillRequest` / relayer) ніколи не існувала, тож кожен on-chain запит платив би LINK за callback, що не прилетить (ба більше, повертався `tx_hash`, а callback-lookup шукає `requestId` — вони б не збіглись). Мінт іде **PATH 2 tokenomics** (оптимістичний, L0-custodial + ex-post clawback — [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)). Замикання PATH 1 справжньою DON-інженерією = свідомо відкинуто при TRL-3; on-chain гілка (Router ABI registry + bytecode probe) воскресає з git.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Chainlink::OracleDispatchService` — local correlation-marker (без RPC) |
| **Воркер** | `ChainlinkDispatchWorker` |
| **Черга** | `web3_critical` (пріоритет 6) |
| **Retry** | 5 |
| **Тригер** | Після успішної IoTeX ZK-верифікації |
| **ENV** | `CHAINLINK_HMAC_SECRET` (лише callback-endpoint) |
| **Спека** | `spec/services/chainlink/oracle_dispatch_service_spec.rb` |

**Guard Clause:** `validate_iotex_verification!` — dispatch ЗАБОРОНЕНО якщо `verified_by_iotex? == false`.

**Що робить `dispatch!`:** генерує `chainlink-req-<hex>` маркер + `oracle_status: "dispatched"`. Маркер = dedup-ключ Solana-винагород ([ARCH.51] `unsettled_event_tx`) та idempotency-guard dispatch/callback-шляхів — тому колонка `chainlink_request_id` жива й після демоуту. Демоут-інваріант закріплено тестом: dispatch не сміє торкатись `Web3::RpcConnectionPool` (regression-guard проти воскресіння LINK-cost).

**Callback-endpoint** (`POST /api/v1/oracle_callbacks`, HMAC-SHA256) лишається live — це двері для майбутнього PATH 1 або manual-fulfillment (§8.3).

#### 12. Ethereum L1 (State Root Anchoring)

Абсолютна істина. Раз на тиждень весь стан лісу та економіки хешується (SHA-256) і записується в Mainnet Ethereum.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Ethereum::StateAnchorService` |
| **Воркер** | `EthereumAnchorWorker` |
| **Черга** | `web3_low` (пріоритет 8) |
| **Retry** | 5 |
| **Unique** | `unique_for: 7.days` (запобігає перетину тижневих циклів) |
| **ENV** | `ETHEREUM_ANCHOR_PRIVATE_KEY`, `ETHEREUM_ANCHOR_CONTRACT`, `ETHEREUM_MAX_FEE_GWEI`, `ETHEREUM_PRIORITY_FEE_GWEI`, `ETHEREUM_GAS_LIMIT` |
| **RPC** | `ALCHEMY_ETHEREUM_RPC_URL` |
| **Спека** | `spec/services/ethereum/state_anchor_service_spec.rb` |

**Формула `state_root` + флоу** — §4 нижче (6-польова версія [ARCH.97]: `total_growth_points|total_sfc|active_tree_count|chain_hash|anchored_at|total_scc_supply` — перше поле це БАЛИ офчейн-леджера, останнє чинний SCC-supply; доти обидві ролі ніс один `total_scc`); SSOT-дім формули — [`05_04`](05_04_Ethereum_L1_State_Anchor).

**Економіка:** 32 байти раз на тиждень. Мінімальний газ, але рівень безпеки мережі Ethereum вартістю в сотні мільярдів доларів.

---

## ⚙️ 2. Консенсус "Proof of Growth" (Трубопровід Верифікації)

Процес перетворення фізичного життя дерева на токен (SCC) — багатоетапний, спроектований як trustless oracle-pipeline. ⚠️ **Точніше:** основний (oracle-driven) шлях мінімізує довіру, але існують **свідомі відступи** — адмінські обходи (PATH 2 tokenomics-конвертація / PATH 5 manual mint → [`05_02`](05_02_Proof_of_Growth_Pipeline)) і поточний L0-custodial trust-origin (§ IoTeX вище). Кроки основного шляху:

### Крок 1: Збір (Hardware → Backend)

Сенсор зчитує час заряду іоністора (`delta_t`) і напругу шини живлення (`vcap` — мВ VDDA, [ARCH.99]; не заряд самого іоністора), пакує у 16 байт і шифрує **AES-128** (LoRa-канал Soldier→Queen; режими — [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)). AES-256-CBC застосовується далі, на магістралі Queen→Rails (CoAP-батч).

```
firmware/soldier/main.c → LoRa TX → Queen → CoAP PUT → UnpackTelemetryWorker → TelemetryUnpackerService
```

| Компонент | Файл |
|-----------|------|
| Прошивка Солдата | `firmware/soldier/main.c` |
| Прошивка Королеви | `firmware/queen/main.c` |
| mruby Lorenz (on-device) | `firmware/bio_contracts/bio_contract.rb` |
| Воркер розпакування | `UnpackTelemetryWorker` (черга: `uplink`, пріоритет 1) |
| Сервіс розпакування | `TelemetryUnpackerService` (binary decoding: 21B ECB / 31B CCM за `TELEMETRY_CCM_ENABLED`) |

### Крок 2: Обчислення (Lorenz Attractor)

Внутрішня математика (Атрактор Лоренца) рахує значення осі Z. `Z-value` порівнюється з константами `TreeFamily` (напр. 20.0). Якщо дерево в гомеостазі — нараховуються `growth_points`.

> **⚠️ [Lorenz de-risk]** «Z = здоров'я» — недоведена гіпотеза ([`05_05 §8`](05_05_Slashing_and_Risk_Policy)); slashing вимагає ≥1 прямого сигналу (sap_flow / VPD / acoustic), не лише Z ([`05_05 §7`](05_05_Slashing_and_Risk_Policy)). Lorenz-DCI (anti-fraud) валідний незалежно.

> Lorenz-константи (σ/ρ/β, clamps, dt, iterations) — **SSOT [`03_04 §1.2`](03_04_mruby_Lorenz_Attractor)** (firmware↔backend дзеркало, не дублюється тут). Серверний `SilkenNet::Attractor` — Float64 IEEE 754, бітово ідентично firmware mruby [FW.7].

| Компонент | Файл |
|-----------|------|
| Серверний Lorenz | `app/services/silken_net/attractor.rb` (Float, IEEE 754 — ідентично firmware mruby) |
| Dual Computation Integrity | Device Z vs Server Z — categorical comparison (homeostasis vs stress/anomaly mismatch) → fraud flag |
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

### Крок 5: Oracle-маркування (Chainlink demoted — ARCH.53)

Після IoTeX-верифікації лог маркується `dispatched` (internal correlation-marker; on-chain Router-запит вилучено — LINK-cost без DON-callback'а). PATH 1 далі latent; мінт реально йде PATH 2 tokenomics (Крок 7, Шлях Б).

```
ChainlinkDispatchWorker → Chainlink::OracleDispatchService → chainlink-req-<hex> (local marker)
```

**Guard:** `validate_iotex_verification!` — No ZK-proof, no oracle-marker.

### Крок 6: Аудит особи (Polygon Hadron)

Контракт перевіряє статус KYC кінцевого отримувача токенів.

```
HadronAssetRegistrationWorker → Polygon::HadronComplianceService → hadron_kyc_status == "approved"
```

### Крок 7: Емісія (Polygon Mint)

SCC мінтинг ініціюється двома незалежними шляхами — в обох випадках за фіксованим курсом емісії ([`05_03`](05_03_Tokenomics_SCC_and_SFC)). Детально: [`05_02 §DOC.7`](05_02_Proof_of_Growth_Pipeline).

**Шлях A — Oracle-driven (ініціюється `OracleCallbacksController`) — ⚪ latent [ARCH.53]:** callback сьогодні не прилітає (DON unwired, dispatch = local marker); шлях лишається збудованим і guard'ованим для майбутнього PATH 1 / manual-fulfillment.

```
OracleCallbacksController → oracle_status = "fulfilled"
  → MintCarbonCoinWorker → BlockchainMintingService
  → Guard: verified_by_iotex? + oracle_status_fulfilled? + wallet.kyc_approved_for_minting?
  → Polygon: mint(to_address, amount, tree_did)
  → BlockchainConfirmationWorker (+30s) → confirm!(tx_hash)
```

**Шлях Б — Tokenomics-driven (ініціюється cron-воркером):**

```
TokenomicsEvaluatorWorker (щогодини, cron: 0 * * * *)
  → EvaluateTreeBatchWorker → Wallet.available_balance >= 10,000? → lock_and_mint!  (NET — ARCH.94)
  → BlockchainMintingService.call(batch, telemetry_log: nil)
  → Guard: wallet.kyc_approved_for_minting? (тільки; бенефіціар — KYC.1)
         (verified_by_iotex? + oracle_status свідомо пропускаються —
          per-packet integrity вже забезпечена AES-CBC decrypt + valid_sensor_data?)
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
| **Ролі** | `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, `SLASHER_ROLE`, `PAUSER_ROLE` (SEC.1 — повна таблиця [`05_03`](05_03_Tokenomics_SCC_and_SFC)) |

**Ключові функції:**
- `mint(address to, uint256 amount, string memory treeDid)` — Базовий мінтинг. Емітує `CarbonMinted`.
- `batchMint(address[] recipients, uint256[] amounts, string[] treeDids)` — До 100 дерев за один виклик (`MAX_BATCH_SIZE`, дім [`05_03`](05_03_Tokenomics_SCC_and_SFC)).
- `slash(address investor, uint256 amount)` — Спалює токени при порушенні. Емітує `TokenSlashed`.
- `pause() / unpause()` — Екстрене заморожування.
- `nonces(address)` — Override для ERC20Permit/Nonces MRO сумісності.
- Gasless approvals через EIP-2612 (`ERC20Permit`) — дозволяє DEX/P2P marketplace інтеграцію без газу для власників SCC.

### SilkenForestCoin.sol (SFC)

| Параметр | Значення |
|----------|----------|
| **Файл** | `contracts/SilkenForestCoin.sol` |
| **Стандарт** | ERC-20 + `AccessControl` + `Pausable` + `ERC20Permit` + `ERC20Votes` |
| **Ролі** | `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, `SLASHER_ROLE`, `PAUSER_ROLE` (SEC.1 — повна таблиця [`05_03`](05_03_Tokenomics_SCC_and_SFC)) |

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
# Формула — дзеркало SSOT (owner [`05_04`](05_04_Ethereum_L1_State_Anchor)), правити ТАМ.
# Роздільник `|` (pipe), не `:`. [E.53/E.54] 5 полів: + total_sfc, active_tree_count.
state_root = Digest::SHA256.hexdigest("#{total_growth_points}|#{total_sfc}|#{active_tree_count}|#{chain_hash}|#{timestamp.iso8601}|#{total_scc_supply}")
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
| `ALCHEMY_POLYGON_RPC_URL` | Polygon, KlimaDAO |
| `ALCHEMY_ETHEREUM_RPC_URL` | Ethereum L1 |
| `CELO_RPC_URL` | Celo |
| `SOLANA_RPC_URL` | Solana |
| `ORACLE_MINTER_PRIVATE_KEY` / `ORACLE_SLASHER_PRIVATE_KEY` / `ORACLE_CELO_PRIVATE_KEY` | Dedicated EVM signer wallets (legacy shared key retired — INF.22) |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | L1 anchoring wallet |
| `CARBON_COIN_CONTRACT_ADDRESS` | SCC contract |
| `CHAINLINK_HMAC_SECRET` | Oracle-callback endpoint (dispatch-секрети вилучено — ARCH.53) |
| `KLIMA_RETIREMENT_CONTRACT` | KlimaDAO |
| `SOLANA_USDC_MINT_ADDRESS` | Solana USDC |
| `FILECOIN_PINNING_API_URL` | Pinata |

> **Boot guard:** `Security::Web3NetworkGuard` ([`04_02 §8`](04_02_Business_Logic_and_Services)) fail-closes at boot у production / `WEB3_STRICT_MODE`, якщо будь-який `*_RPC_URL` вище несе testnet-маркер (Amoy / devnet / Sepolia…) чи `CELO_RPC_URL` порожній при озброєному Celo-шляху (unset = тихий Alfajores-fallback у коді, E.49 — умовний гейт на присутність `ORACLE_CELO_PRIVATE_KEY`), `ORACLE_*` signer-ключ відсутній/malformed, або silent-address ENV (`DAO_TREASURY_ADDRESS`/SCC/SFC-адреси — use-сайти маскують config-баг під RPC-збій: tax тихо off, chain-audit хибне «clean», fallback-ціна) відсутній/malformed, або Solana signer-четвірка неповна (batch-payout без escalation-шляху) — розширює runtime E.47 Solana-guard (`SOLANA_RPC_URL` за замовчуванням = Devnet) на EVM + boot-time. Live `eth_chainId`-probe свідомо не робиться (нуль RPC-залежності на boot).

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
| 11 | Chainlink ⚪ | Marker (demoted ARCH.53) | `ChainlinkDispatchWorker` + `Web3CircuitBreaker` | `web3_critical` | 5 | — |
| 12 | Ethereum L1 | Finality | `EthereumAnchorWorker` | `web3_low` | 3 | `0 3 * * 1` |
| 13 | Cross-chain | Treasury | `TreasuryMonitorWorker` | `web3_low` | 3 | `*/15 * * * *` |
| 14 | Polygon | Gas Optimization | `MintBatchCollectorWorker` | `web3` | 3 | `*/5 * * * *` |
| 14b | Solana | Gas Optimization | `SolanaBatchPayoutWorker` [E.61] | `web3` | 3 | `20 * * * *` |

> **Тести.** Spec-шлях кожного сервісу — у його картці §1 (One-Home: інвентар біля підсистеми). Конвенції написання / coverage-гейт / тріаж прогалин — [`04_06`](04_06_Testing_Guide_and_Coverage).

---

## 🚨 8. Disaster Recovery / Chain Outage Strategy (S6.11)

> **Принцип:** SilkenNet залежить від 12 незалежних мереж — імовірність того, що **жодна** з них не матиме outage за рік близька до нуля. Ця секція визначає, як система деградує grace при відмові кожної мережі, яким мережам категорично не можна "впасти" без zero-downtime fallback, та які інженерні відповіді закладені в Rails backend / контракти.

### 8.1. Класифікація мереж за критичністю

| Tier | Критерій | Мережі |
|---|---|---|
| **🔴 Critical Path** | Якщо мережа `down` — Proof of Growth pipeline зупиняється, нові SCC не мінтяться, користувачі не отримують винагороду | **Polygon, IoTeX** |
| **⚪ Unwired** | Не на critical path: dispatch = local marker, DON-callback не прилітає; мінт іде PATH 2 tokenomics | **Chainlink** [ARCH.53] |
| **🟠 Important** | Outage блокує конкретний use case (винагороди, KYC), але core economics працює | **Solana, Hadron, peaq** |
| **🟢 Nice-to-have** | Outage не впливає на користувацький досвід; дані зберігаються в backend та відправляються після відновлення | **Streamr, Filecoin, The Graph, Celo, KlimaDAO, Ethereum L1** |

### 8.2. Critical Path: Polygon

**Роль:** Primary EVM — SCC/SFC мінтинг, slashing, governance, parameter registry, ProtocolParameters.

**Причини outage:** RPC overload (Alchemy/Infura down), Polygon validator stop, MATIC gas spike, contract pause (адмін multisig).

**Поточні захисти:**
- `Web3::ResilientClient` з MAX_FAILURES=3, CIRCUIT_OPEN_DURATION=60s, fallback cascade Primary→Secondary→Public RPC.
- Sidekiq retry з exponential backoff (5 retries для `web3_critical`).
- `BlockchainTransaction` AASM має стан `manual_review` коли tx_hash отримано але стан невідомий — кошти заблоковано до ручної звірки (no double-spend). **[ARCH.45]** той самий клас on-chain↔DB crash-window закрито durable intent-marker + `unsettled_within` reconcile-guard для Solana payout / burn / Etherisc (дзеркало EthereumAnchor DOUBLE-ANCHOR; [`04_02 §4/§10`](04_02_Business_Logic_and_Services)).
- `MintBatchCollectorWorker` агрегує до 100 мінтів у `batchMint` — якщо один payload poisoned, Binary Search isolation дозволяє відрахувати решту валідних.

**Graceful degradation при Polygon down:**

1. **`web3_critical` queue depth growing** → trigger Grafana alert.
2. **TelemetryLog продовжує збиратись** з `oracle_status: pending` — нічого не втрачається, бо телеметрія партиціонована та зберігається в Postgres.
3. **`MintCarbonCoinWorker`** retry до 5 разів; на 6+ потрапляє у DeadSet — **операційна задача для адміна**: перезапустити після відновлення RPC.
4. **Альтернативний RPC**: уже передбачено через `Web3::RpcConnectionPool#fallback_env_keys`. Production checklist: завжди мати **3 незалежні Polygon RPC** (Alchemy + Infura + Ankr/QuickNode/Public).
5. **Багатогодинний outage (>4h):** ручний switch на Polygon Mumbai/Amoy testnet з replay у production після відновлення (потребує адміністративного рішення; **НЕ автоматично**, бо економіка тестнету ≠ mainnet).

**Boundary case — Polygon hard fork / chain split:**
- Призупинити `MintCarbonCoinWorker` (Sidekiq pause) — **операційна процедура**.
- Дочекатись ясності: який fork буде canonical (community+exchanges).
- Replay queue після стабілізації; перевірити, що contract addresses не змінились.

### 8.3. Chainlink (Functions / DON) — ⚪ unwired, поза critical path [ARCH.53]

**Чесна роль:** dispatch = local correlation-marker (без RPC/LINK-cost) → **Chainlink-outage не існує як клас відмови** — мінт іде PATH 2 tokenomics незалежно. Колишній claim «без Chainlink callback pipeline зупиняється» був aspiration-drift: callback і так ніколи не прилітав (DON-нога unwired), а «Subscription balance моніториться через TreasuryMonitorWorker» не відповідав коду (сервіс моніторить MATIC/SOL/CELO/ETH-газ, LINK-subscription — ні).

**Що лишається live:**
- `oracle_callbacks` ендпоінт (HMAC-SHA256, replay-guard) — двері для майбутнього PATH 1 / manual-fulfillment; будь-який підписант з валідним HMAC може викликати.
- **DOC.8-інваріант діє:** cleanup НЕ видаляє `oracle_status: dispatched` записи — вони приймуть callback, якщо/коли PATH 1 замкнеться.

**PATH 1 закривати відмовлено (founder-присуд 2026-07-19, ARCH.53 §🗄️):** superseded by Merkle-lineage (ARCH.12/MRV.1 — аудитор верифікує кредит проти якорених вимірів офлайн; DON засвідчував би *обчислення*, не *походження даних*). Технічний шлях (Functions JS-source + consumer `fulfillRequest` + relayer + git-воскресіння on-chain гілки з Router ABI registry + bytecode probe + ARCH.49 nonce-lock) — історична нотатка. Manual bypass (`OracleManualFulfillmentService`, super_admin, реліз-тег для аудиту) — так само майбутнє, не реалізовано.

### 8.4. Critical Path: IoTeX W3bstream

**Роль:** ZK-proof verification — перший gate у guard clause (`verified_by_iotex?`).

**Причини outage:** W3bstream node down, prover overload, API key revoked.

**Поточні захисти:**
- `IotexVerificationWorker` + `Web3CircuitBreaker` (queue: `web3_critical`, retry 5).
- `verified_by_iotex` зберігається в TelemetryLog — після відновлення verification вмикається без перебудови pipeline.

**Graceful degradation при IoTeX down:**

1. **TelemetryLog `verified_by_iotex: false`** залишається unverified.
2. **ChainlinkDispatchWorker не запускається** (dispatch-guard `verified_by_iotex?`) — oracle-маркування (latent Path 1 [DOC.7], ARCH.53) зупиняється на початку pipeline. Це **бажана поведінка**: unverified лог не отримує навіть correlation-marker.
3. **Tokenomics-flow Path 2 продовжує працювати** (`TokenomicsEvaluatorWorker` → `EvaluateTreeBatchWorker` → `Wallet#lock_and_mint!` → `BlockchainMintingService.call(batch, telemetry_log: nil)`) — для цього шляху guards `verified_by_iotex?` / `oracle_status_fulfilled?` **свідомо пропускаються** (per-packet integrity perimeter забезпечується AES-256-CBC decrypt + `valid_sensor_data?` у `TelemetryUnpackerService`, а **єдиний обов'язковий guard** — `hadron_kyc_status == "approved"`). Cross-ref: [`05_02 §Усі Шляхи до lock_and_mint! [DOC.7]`](05_02_Proof_of_Growth_Pipeline) + [`04_02` — BlockchainMintingService](04_02_Business_Logic_and_Services).
4. **Multi-day outage policy:** для збереження user trust розглянути **temporary reduced minting** через альтернативну верифікацію — кандидатом тепер є вже відвантажений рунг **L1 Queen-attestation** (crypto-доказ, що дані пройшли крізь РЕАЛЬНУ Королеву; незалежний від IoTeX — [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)). ⚫ Колишній кандидат «Forester Guild Proof-of-Physical-Work» відкликано ⚖️ 2026-08-24 разом із гільдією-маркетплейсом ([`04_02 §Forester Guild`](04_02_Business_Logic_and_Services)). Реалізація — post-TRL 7.

### 8.5. Important Tier: Solana, Hadron, peaq

| Мережа | Outage Impact | Graceful Degradation |
|---|---|---|
| **Solana** | USDC мікро-винагороди не нараховуються | `SolanaMicroRewardWorker` retry 3 → DeadSet. Користувацький досвід зберігається — winnings накопичуються в Polygon SCC, USDC друкується retroactively через `Solana::CatchupWorker` (запланувати). **[ARCH.45]** batch payout idempotent (intent-marker + in-flight reconcile) — повторний цикл не передплачує. |
| **Hadron (KYC)** | Нові KYC submissions не верифікуються | `wallet.hadron_kyc_status: pending` → mint blocked для нового користувача, але існуючі approved wallets не зачеплено. Hot-fix: `WEB3_STRICT_MODE=false` (тимчасово, з аудиторським логом) для unblock в emergency |
| **peaq** | Нові provisioning DID не реєструються | `PeaqRegistrationWorker` retry 5; нові Soldiers/Queens отримують локальний DID `did:peaq:0x...` (deterministic SHA256(uid+created_at)), реєстрація push-up при відновленні |

### 8.6. Nice-to-have Tier (Streamr, Filecoin, The Graph, Celo, Klima, L1)

Outage цих мереж **не блокує** core flow:
- **Streamr** — broadcast retry на `low` queue; підписники downstream втратять live feed, але дані зберігаються в Postgres.
- **Filecoin/IPFS** — IPFS pinning через Pinata fallback; outage означає затримку довготривалого архіву на дні.
- **The Graph** — read-only; UI показує `cached_data` або `stale` indicator.
- **Celo** — community rewards (cUSD) затримуються; `CeloRewardWorker` retry 3.
- **KlimaDAO** — ESG retirement затримується; non-blocking для основного pipeline.
- **Ethereum L1 anchoring** — щотижневий, толерантний до 3-5 днів затримки; `EthereumAnchorWorker` cron `0 3 * * 1` спрацює наступного тижня.

### 8.7. Cross-cutting Recommendations

1. **Treasury per-chain** з 30-day operational gas reserve. `TreasuryMonitorWorker` (`*/15 * * * *`) тригерить alert при < 7-day reserve.
2. **Per-chain RPC redundancy:** мінімум **3 RPC providers** для кожного `Web3::ResilientClient` (Primary/Secondary/Public).
3. **Status page** (Grafana Cloud public dashboard або Statuspage.io) — публічний індикатор для community + B2B клієнтів. Автоматично оновлюється з `silkennet_rpc_circuit_breaker_open` метрики.
4. **Chaos Engineering** (E.27): post-TRL 7 — періодично симулювати chain outage в canopy (`SOLANA_RPC_URL=invalid`), фіксувати behaviour, тримати runbook актуальним.
5. **Runbook per chain:** для кожної з 12 мереж задокументовано: detection signal, Grafana alert, immediate action (≤15 min), escalation (>1h), recovery procedure. **Ця частина — операційна (адмін)**, не код.

### 8.8. Summary Matrix

| Мережа | Tier | Single Point of Failure? | Auto-recovery? | Manual escalation |
|---|---|---|---|---|
| Polygon | 🔴 Critical | Mitigated by `Web3::ResilientClient` cascade | Yes (RPC fallback + Sidekiq retry) | Multi-day outage → admin investigation |
| Chainlink | ⚪ Unwired [ARCH.53] | — (local marker, без зовнішньої залежності) | — | PATH 1 закривати відмовлено (founder 2026-07-19, ARCH.53 §🗄️) |
| IoTeX | 🔴 Critical | Yes | Sidekiq retry | Multi-day → temporary minting freeze |
| Solana | 🟠 Important | Mitigated by `SOLANA_RPC_URL_FALLBACK` cascade [INF.22] | Yes (RPC fallback + Sidekiq retry) | Catchup worker after restore |
| Hadron | 🟠 Important | Yes | No | Strict-mode override (emergency) |
| peaq | 🟠 Important | No (local DID generation) | Yes | — |
| Streamr | 🟢 Nice | No | Yes | — |
| Filecoin | 🟢 Nice | Pinata fallback | Yes | — |
| The Graph | 🟢 Nice | No (read-only) | Yes | — |
| Celo | 🟢 Nice | RPC fallback | Yes | — |
| KlimaDAO | 🟢 Nice | No | Yes | — |
| Ethereum L1 | 🟢 Nice | No | Yes (cron retry) | — |

