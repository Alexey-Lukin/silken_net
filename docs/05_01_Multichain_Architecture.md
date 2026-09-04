# 05_01: Мультичейн Архітектура (11-Chain Ecosystem)

## 🎯 Мета

Зафіксувати повну топологію та взаємодію 11 незалежних блокчейн-мереж і децентралізованих протоколів, що утворюють Кіберфізичну Державу SilkenNet. Цей документ деталізує, як фізичні дані з лісу проходять шлях від локального ZK-доказу до глобальної фінансової емісії та фіналізації в Ethereum L1.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Мультичейн архітектура повністю спроєктована. Структурний скелет усіх 11 мереж присутній у кодбейсі. Всі сервіси мають RSpec-покриття.
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
- [1. Топологія 11 Мереж (The 11-Network Stack)](#-1-топологія-11-мереж-the-11-network-stack)
- [2. Консенсус "Proof of Growth" — РОЛЬОВА карта мереж (кроки → (05_02_Proof_of_Growth_Pipeline))](#-2-консенсус-proof-of-growth--рольова-карта-мереж-кроки--05_0205_02_proof_of_growth_pipeline)
- [3. Смарт-Контракти на Polygon — де вони живуть (поверхня → (05_03_Tokenomics_SCC_and_SFC))](#-3-смарт-контракти-на-polygon--де-вони-живуть-поверхня--05_0305_03_tokenomics_scc_and_sfc)
- [4. Абсолютна Фіналізація (Ethereum State Root Anchoring)](#-4-абсолютна-фіналізація-ethereum-state-root-anchoring)
- [5. Конфігурація Credentials та ENV](#-5-конфігурація-credentials-та-env)
- [6. Shared Infrastructure Layer](#-6-shared-infrastructure-layer)
- [7. Повна Матриця Сервісів та Черг](#-7-повна-матриця-сервісів-та-черг)
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

> Коли аудитор або інвестор запитає: *"Навіщо вам 11 блокчейнів?"*, ваша відповідь:
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

🔑 **Колонка «Статус» судить НАШ КОД, і читається як твердження про ЧУЖИЙ КАНАЛ — розрізняй при кожному новому рядку [ARCH.118].** `✅ Real` означає «інтеграцію написано й вона не заглушка», ніколи «ендпоінт відповідає». Ціна злиття виміряна 2026-09-04: тут стояло Filecoin `✅ Real`, тоді як [`06_08 §2.2`](06_08_Resilience_and_Failover_Policy) того самого репозиторію про той самий сервіс казав `ACTIVATION-GATED` після 97 подій Sentry за чотири хвилини. **Досяжність вендора — окреме твердження й окремий вимір**; коли він зроблений, він і його дата стоять у «Примітці», а не в статусі.

| # | Мережа | Сервіс | Статус | Примітка |
|---|--------|--------|--------|----------|
| 1 | Filecoin/IPFS | `Filecoin::ArchiveService` + `VerificationService` | ⚠️ Activation-gated | Pinata IPFS gateway. **[ARCH.118] З 2026-09-03 без ключа `configured?` = false і enqueue не робиться зовсім** — доти кожен `AuditLog` палив retry:5 у нікуди (97 подій Sentry за 4 хв). Дім механіки — [`06_08 §2.2`](06_08_Resilience_and_Failover_Policy), запис Filecoin/IPFS; ⚠️ тут стояло `✅ Real`, що прямо суперечило тому запису |
| 2 | peaq | `Peaq::DidRegistryService` | ⚠️ Activation-gated | Ed25519-підписані DID через Substrate HTTP. **[ARCH.119] З 2026-09-04 без обох значень (`PEAQ_NODE_URL`+`PEAQ_SIGNING_KEY`) `configured?` = false: enqueue не робиться, воркер виходить WARN'ом; ре-арм — `PeaqBackfillWorker`** |
| 3 | IoTeX W3bstream | `Iotex::W3bstreamVerificationService` | ⚠️ Activation-gated | HTTP POST до W3bstream (хост із `.env.example` не має DNS-запису — [`00_07`](00_07_Action_Plan_Tracker) ARCH.118) |
| 4 | The Graph | `TheGraph::QueryService` | ⚠️ Activation-gated | GraphQL-запити до subgraph. **[ARCH.119] Без `THE_GRAPH_API_URL` обидва контролерні сайти віддають «не виміряно» й НАЗИВАЮТЬ ногу в логах; гейт стоїть усередині `Rails.cache.fetch`, бо виняток у блоці не кешується взагалі.** ⛔ Ре-арму немає й не треба — read-only |
| 5 | Polygon | `BlockchainMintingService` + `BlockchainBurningService` | ✅ Real | Eth::Client → Alchemy RPC |
| 6 | Polygon Hadron | `Polygon::HadronComplianceService` | ⚫ Без адресата | **[ARCH.118]** Продукту «Polygon Hadron» публічно НЕ ІСНУЄ — `api.hadron.polygon.technology` без `A`/`CNAME` при живому `polygon.technology` (перевимір 2026-09-04); клас той самий, що в рядка 3, але тут упала не досяжність, а **сам вендор**. Сервіс лишається fail-closed заявкою без адресата (порожній ключ RAISE-ить у проді — свідомо [INF.11]), але з **[ARCH.119, 2026-09-04]** той raise більше не є робочим станом, а останнім рубежем: enqueue гейтований `verification_reachable?`, тож у проді без ключа джоба не ставиться взагалі; KYC-провайдера **не обрано** → [`00_07`](00_07_Action_Plan_Tracker) `BIZ.20` (Sumsub/Veriff/Onfido/Persona — ⛔ НЕ «Hadron»), і той самий присуд відкриває перейменування `hadron_*` у схемі й коді |
| 7 | Solana | `Solana::MintingService` | ✅ Real | Ed25519-signed `sendTransaction` (base64). Balance guard: 0.05 SOL |
| 8 | Celo | `Celo::CommunityRewardService` | ✅ Real | ERC-20 transfer cUSD через Celo RPC |
| 9 | KlimaDAO | `KlimaDao::RetirementService` | ✅ Real | Approve + Retire (два ERC-20 виклики) |
| 10 | Chainlink | `Chainlink::OracleDispatchService` | ⚪ Demoted | **[ARCH.53]** On-chain `sendRequest` ВИЛУЧЕНО (LINK-cost за callback, що не прилетить: DON-нога unwired — нема Functions JS-source / consumer / relayer, tx_hash≠requestId). `dispatch!` = internal correlation-marker (`chainlink_request_id` живе dedup-ключем Solana + idempotency-guard'ом); мінт іде PATH 2 tokenomics. Callback-endpoint (`/oracle_callbacks`, HMAC) лишається live для майбутнього PATH 1 / manual-fulfillment |
| 11 | Ethereum L1 | `Ethereum::StateAnchorService` | ✅ Real | `storeStateRoot(bytes32)` через Alchemy Ethereum RPC |

**Легенда:** ✅ Real = Бойова імплементація з реальними RPC-викликами · ⚠️ Hybrid = Працює в реальному режимі з credentials, fallback до симуляції без них · ⚠️ Devnet = Бойова логіка, але транзакції йдуть на Devnet (simulateTransaction)

---

## 🌐 1. Топологія 11 Мереж (The 11-Network Stack)

SilkenNet не покладається на один блокчейн. Для забезпечення максимальної безпеки, масштабованості та compliance, система розподіляє функції (Зберігання, Верифікація, Економіка, Фіналізація) між спеціалізованими протоколами.

### Рівень 1: Дані та Зберігання (Data & Storage)

> ⚫ **Streamr знято 2026-09-03** (⚖️ founder, [`00_07`](00_07_Action_Plan_Tracker) ARCH.118 — won't-do роду КОНСТРУКЦІЯ, не дефект): у Streamr 1.0 центрального REST-хоста немає (`brubeck` data-api мертвий з 2026-08-30), публікація лише через ВЛАСНИЙ broker-вузол або SDK — тобто ціна утримання = ще один вузол у стеку заради спостерігача, що нічого не гейтить, а під критерієм місії ([`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap)) він дублював наше ж свідчення (Postgres + Turbo-стрічка + Prometheus) і не додавав незалежного. Знято тим самим комітом: сервіс, воркер, метрика `silkennet_streamr_broadcast_failures_total`, `PF_STREAMR_GAP` (guarded hook, що завжди віддавав 0 — [`05_05 §6`](05_05_Slashing_and_Risk_Policy)), креденшели й ENV; §7-матриця та цей перелік перенумеровано. Стек відтоді **11-ланковий**.

#### 1. Filecoin / IPFS (Immutable Archive)

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

#### 2. peaq network (Machine DID)

Кожен "Солдат" (дерево) отримує тут свій суверенний цифровий паспорт (наприклад, `did:peaq:0x...`). Це гарантує, що пристрій є автентичним.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Peaq::DidRegistryService` |
| **Воркер** | `PeaqRegistrationWorker` + ре-арм `PeaqBackfillWorker` (черга `low`, cron `56 4 * * *`, `BATCH_LIMIT` 500) |
| **Черга** | `web3` (пріоритет 7) |
| **Retry** | 5 |
| **Активація** | **ACTIVATION-GATED [ARCH.119]** — `Peaq::DidRegistryService.configured?` (обидва: `PEAQ_NODE_URL` + `PEAQ_SIGNING_KEY`, ENV-first із credentials-фолбеком). Без них ані enqueue, ані виконання; `peaq_did` чесно лишається `nil`, і саме він є маркером ре-арму (окремої outbox-колонки не заведено — форма IoTeX) |
| **Тригер** | При реєстрації нового дерева в системі (ОДИН enqueue-сайт: провіжн-контролер, після коміту) |
| **Credentials** | `peaq_node_url`, `peaq_signing_key` (Rails encrypted credentials) |
| **Криптографія** | Ed25519 (через `Ed25519Crypto::SigningService`) — peaq використовує Substrate |
| **Спека** | `spec/services/peaq/did_registry_service_spec.rb` |

**Формат DID:**
```
did:peaq:0x{SHA256("<hardware_identifier>:<tree_id>:<created_at.to_i>")[0:40]}   # роздільник `:` несучий
```

#### 3. IoTeX W3bstream (ZK-Proofs)

Генерація Zero-Knowledge доказів цілісності pipeline + прив'язки до peaq DID (W3bstream — **НЕ** TEE). ⚠️ **Чесно про trust:** поточний рівень = L0 custodial (`hardware_signature` = backend-HKDF-derived — підтверджує цілісність шляху, але **не** доводить кремнієве походження); hardware-origin — true-DePIN North-Star (L2 trust-ladder → [`05_02`](05_02_Proof_of_Growth_Pipeline)). ZK ускладнює підробку скриптом, але origin-гарантію дає лише L2.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Iotex::W3bstreamVerificationService` |
| **Воркер** | `IotexVerificationWorker` |
| **Черга** | `web3_critical` (пріоритет 6) |
| **Retry** | 5 |
| **Тригер** | `TelemetryUnpackerService` — лише коли `Iotex::W3bstreamVerificationService.configured?` [ARCH.118/OPS.37, 2026-09-02]; незаведена пара = жодної джоби й жодного ре-арму |
| **Credentials** | `IOTEX_W3BSTREAM_URL`/`IOTEX_API_KEY` (ENV-first, credentials-фолбек — SEC.22); хост `w3bstream-api.iotex.io` з `.env.example` не має DNS-запису (2026-09-02) |
| **Спека** | `spec/services/iotex/w3bstream_verification_service_spec.rb` |

**Guard Clause:** Chainlink dispatch ЗАБОРОНЕНО без підтвердження від IoTeX (`verified_by_iotex? == true`).

#### 4. The Graph (Decentralized Indexing)

Децентралізований індексатор. Спеціальний сабграф (Subgraph) слухає події `CarbonMinted` і будує GraphQL API для глобальних дашбордів екологічних організацій.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `TheGraph::QueryService` |
| **Воркер** | — (read-only, немає окремого воркера) |
| **Черга** | — |
| **Тригер** | Викликається on-demand з контролерів та дашбордів |
| **Активація** | **ACTIVATION-GATED [ARCH.119]** — `TheGraph::QueryService.configured?` на ОБОХ контролерних сайтах, усередині `Rails.cache.fetch`. Без `THE_GRAPH_API_URL` виклику не робиться взагалі, і кожен сайт НАЗИВАЄ несконфігуровану ногу в логах, відрізняючи її від «вендор лежить». ⚠️ Фолбеки РІЗНІ за типом: скаляр `nil` (дашборд) ⊥ три ключі `NETWORK_EMISSION_DEFAULTS` (звіт) |
| **Credentials** | `the_graph_api_url` (Rails encrypted credentials) |
| **Subgraph** | `subgraph/schema.graphql`, `subgraph/subgraph.yaml`, `subgraph/src/mapping.ts` |
| **Мережа Subgraph** | `polygon-amoy` (Polygon testnet) |
| **Спека** | `spec/services/the_graph/query_service_spec.rb` |

**Методи:**
- `fetch_total_carbon_minted` — останні 100 `CarbonMintEvent`, сума `amount`
- `fetch_protocol_financials` — singleton `ProtocolFinancials` entity

**Entities (GraphQL) — SSOT у `subgraph/schema.graphql`, тут НЕ дзеркалимо.** 🔴 Доти на цьому місці стояла **часткова копія**, і вона протухла саме так, як протухає копія схеми: `CarbonMintEvent` перелічувався без `treeDidHash`/`kind`/`subjectDid`/`archiveRoot`, а `ProtocolFinancials` — двома лічильниками з семи, тобто без тих трьох, що несуть усю доказову поставу (`totalMintedGrowth`/`Insurance`/`Tax`). Копію знято 2026-08-28 [OPS.36]: перелік полів тут не стереже ніщо, а сама схема гейтована з двох боків — `spec/quality/subgraph_abi_parity_spec.rb` (події ⟷ `contracts/*.sol`) і `spec/quality/subgraph_entity_completeness_spec.rb` (кожне не-nullable поле присвоєне в мапінгу).

Що варто знати ЧИТАЧЕВІ ЦІЄЇ сторінки, не відкриваючи схему: індекс покриває **емісію і спалення** обох токенів плюс `ParameterUpdated` (арифметична передумова опублікованої податкової суми); межа предмета оголошена в шапці `subgraph/subgraph.yaml`. Для питання «скільки намінтовано за виміряний ріст» читають `ProtocolFinancials.totalMintedGrowth`, а не `totalMinted` — розкладка й підстава живуть у [`05_03 §Префікси ідентифікатора мінта`](05_03_Tokenomics_SCC_and_SFC).

---

### Рівень 3: Фінанси та Економіка (Primary Chain & Parallel Rails)

#### 5. Polygon (Primary EVM)

Головна артерія системи. Тут розгорнуті наші ключові смарт-контракти (`SilkenCarbonCoin.sol`, `SilkenForestCoin.sol`, `SilkenGovernor.sol`, `SilkenTimelock.sol`, `ProtocolParameters.sol`). Вибраний через низьку вартість транзакцій та сумісність з EVM.

| Параметр | Значення |
|----------|----------|
| **Сервіси** | `BlockchainMintingService`, `BlockchainBurningService`, `ChainAuditService`, `MintingRollbackService` |
| **Воркери** | `MintCarbonCoinWorker`, `BurnCarbonTokensWorker`, `BlockchainConfirmationWorker`, `TokenomicsEvaluatorWorker`, `Governance::ParameterSyncWorker` |
| **Черги** | `web3_critical` (мінтинг, підтвердження), `critical` (спалювання), `default` (токеноміка), `web3_low` (governance sync) |
| **ENV** | `ALCHEMY_POLYGON_RPC_URL`, `ORACLE_MINTER_PRIVATE_KEY`, `ORACLE_SLASHER_PRIVATE_KEY` (dedicated-only — legacy `ORACLE_PRIVATE_KEY` retired [INF.22]; [E.2] розділені ключі mint/slash, blast-radius), `CARBON_COIN_CONTRACT_ADDRESS`, `PROTOCOL_PARAMETERS_CONTRACT_ADDRESS` |
| **Спеки** | `spec/services/blockchain_minting_service_spec.rb`, `spec/services/blockchain_burning_service_spec.rb`, `spec/services/chain_audit_service_spec.rb`, `spec/services/minting_rollback_service_spec.rb`, `spec/workers/governance/parameter_sync_worker_spec.rb` |

**Governance DAO (✅ ARCH.4) — дім [`05_06`](05_06_Governance_and_DAO), тут лише факт розгортання.**

На Polygon поруч із токенами розгорнуті `SilkenGovernor`, `SilkenTimelock` (48 год) і `ProtocolParameters` (on-chain registry параметрів). ⛔ **Параметри голосування, quorum-база, перелік well-known keys і пʼять захистів від flash-loan тут НЕ дублюються — виміряно й відкинуто 2026-09-04 (DOC-T.98):** оголошений скоуп картки §1 (реєстр [`00_06 §2`](00_06_SSOT_Documentation_Standard)) є `роль · сервіс-клас · воркер · черга · retry · activation-стан`, і governance-параметрів у ньому немає; а сама пара `ProtocolParameters.sol` ⟷ `ParameterSyncWorker` стоїть під HARD-гейтом (`scripts/governance_key_sync.rb`), який цю копію не бачить.


**Guard Clauses (BlockchainMintingService):**
1. `verified_by_iotex? == true` — ZK-proof з IoTeX (**лише Path 1**, oracle-driven з `telemetry_log`)
2. `oracle_status_fulfilled?` (enum method, prefix) — Chainlink Oracle підтвердив (**лише Path 1**)
3. `wallet.kyc_approved_for_minting?` [KYC.1] — KYC бенефіціара адреси (власна → власний статус; custodial → успадковує org), **усі шляхи**; non-approved → per-tx SKIP
4. Oracle balance ≥ `0.05 MATIC` (default; `oracle_min_balance_matic` — governance-aware [INF.22]) — достатньо газу
5. Kredis distributed lock (**120s** expiration — покриває dry-run + binary-search worst-case ~130s, [S6.5]) — запобігає подвійному мінтингу
6. **[ARCH.62]** per-token circuit-break — `mint_circuit_broken?(token_type)` (Kredis `mint:circuit_broken:<token>`, ставить `Treasury::MonitorService` при volume-аномалії за `:mint_circuit_breaker_enabled`); tripped → HOLD того токена у `:pending` (re-runnable, **НЕ** escalate), fail-open на Redis-збої. Inert default → [`00_07` ARCH.62](00_07_Action_Plan_Tracker)

**HYBRID PROTOCOL GAIA:** 2% Dynamic Tax на carbon\_coin мінтинг, коли insurance pool потребує поповнення: бенефіціар отримує `amount − tax`, а податок їде ОДНИМ агрегованим `DAO_TREASURY`-записом на підбатч (`TAX_BATCH_*`), не по одному запису на транзакцію. ⚠️ Окремого отримувача-форестера в цьому тракті НЕМАЄ — `forester_share_amount` живе на `NaasContract` і диспенс-шляху не має ([`05_05 §3.1`](05_05_Slashing_and_Risk_Policy)).

#### 6. Polygon Hadron (Identity & Compliance)

Модуль Identity & Compliance. Перевіряє `hadron_kyc_status`. Інституційні інвестори можуть мінтити або купувати токени SCC тільки після проходження KYC (стандарт ERC-3643).

🔴 **Гейт живий, вимірювача немає — і наслідок операційний, не риторичний [ARCH.118].** Єдиний рантайм-писач `hadron_kyc_status = "approved"` — цей самий сервіс (решта входжень: сіди й load-test). Адресата в нього не існує, тож у production/`WEB3_STRICT_MODE` статус **не може вийти з `pending` жодного разу**, а `Wallet#kyc_approved_for_minting?` через це вічно `false` → `MintBatchCollectorWorker` кожні 5 хв **мовчки** скіпає per-tx кожного custodial-бенефіціара. ⚠️ І сітка відновлення `HadronKycReverifyWorker` [ARCH.65] стоїть на спростованій передумові: її шапка каже «коли Hadron **оживе**», тобто модель була **даунтайм**, а вимір дав **неіснування** — щогодини вона переозброювала ту саму мертву драбину (`BATCH_LIMIT` 500 на модель). ✅ **Цю половину закрито [ARCH.119, ⚖️ 2026-09-04]: ре-арм гейтований `verification_reachable?`** — без провайдера прохід не ставить жодної джоби. 🔴 **Але замір здоровʼя ЛИШИВСЯ безумовним, і це несуче:** `sample_pending_depth!` — єдиний писач gauge, а `sn-alert-hadron-kyc-backlog` має `noDataState: OK`, тож гейт на всьому проході замовкнув би саме тоді, коли беклог росте. Похідне не змінилось: gauge росте монотонно й **не є сигналом інциденту** — дно в нього структурне, доки провайдера не обрано. Присуд про самого провайдера (і перейменування `hadron_*`) лишається → [`00_07`](00_07_Action_Plan_Tracker) `BIZ.20`.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Polygon::HadronComplianceService` |
| **Воркер** | `HadronAssetRegistrationWorker` |
| **Черга** | `web3_low` (пріоритет 8) |
| **Retry** | 5 |
| **Credentials** | `hadron_api_key` — ⛔ **НЕ провіжнити** ([`06_04 §3`](06_04_Secrets_Checklist)); живий шлях ENV, не vault (§5) |
| **ENV** | `HADRON_API_URL` (default: `https://api.hadron.polygon.technology` — 🔴 **хост не існує**, `A`/`CNAME` відсутні на 2026-09-04; літерал лишається fail-closed заявкою, не робочим фолбеком) |
| **Спека** | `spec/services/polygon/hadron_compliance_service_spec.rb` |

**Два потоки:**
1. `verify_investor!(wallet)` — перевірка KYC через Hadron Identity Platform → `wallet.hadron_kyc_status`
2. `register_asset!(naas_contract)` — реєстрація лісової ділянки як Real World Asset (RWA) → `naas_contract.hadron_asset_id`

> **Режими роботи:** `WEB3_STRICT_MODE=true` → raises `ComplianceError` при відсутності credentials (Production). Без strict mode — simulation fallback для dev/test.

#### 7. Solana (Micro-Rewards)

Використовується для мікро-транзакцій. Забезпечує миттєві виплати USDC у якості винагород власникам дерев (або арбористам) за підтримання гомеостазу.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Solana::MintingService` |
| **Воркер** | `SolanaMicroRewardWorker` (per-event) · `SolanaBatchPayoutWorker` (batch payout [E.61]) |
| **Черга** | `web3` (пріоритет 7) |
| **Retry** | 3 |
| **ENV** | `SOLANA_RPC_URL` (⚠️ code-side fallback = **Devnet**, тобто ТРЕТЯ змінна цього класу поряд із Celo/Polygon — судиться не boot-guard'ом, а власним read-сайтом `Solana::MintingService#solana_rpc_urls`, і з [OPS.37] за віссю `WEB3_CHAIN_ENV`, не за `Rails.env`), `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_MINT_AUTHORITY_PUBKEY`, `SOLANA_USDC_MINT_ADDRESS`, `SOLANA_WALLET_KEYPAIR` |
| **Спека** | `spec/services/solana/minting_service_spec.rb` |

**Trustless Requirements (Guard Clauses):**
1. `verified_by_iotex? == true`
2. `oracle_status_fulfilled?` (enum method)
3. `verify_oracle_balance!` — баланс SOL ≥ 0.05 (50M lamports)

**Мікро-винагорода:** Base reward + bonus per growth\_point, конвертовано в lamports → USDC

> **⚠️ Scale (нот.4):** per-event Solana tx на КОЖЕН fulfilled telemetry на planetary-scale (мільйони verified-подій/добу) зрівнює fees з винагородою + RPC-навантаження. **Закрито batch payouts [E.61]:** при ненульовому порозі `solana_batch_threshold_usdc` (governance-aware `SystemParameter`, в USDC) `SolanaMicroRewardWorker` акумулює винагороду per-wallet у Kredis замість окремої tx; годинний `SolanaBatchPayoutWorker` (`Solana::BatchPayoutService`) виплачує накопичене одним `transferChecked` ATA→ATA, щойно сума перетне поріг. **[ARCH.45] idempotency:** durable intent-marker (signature обчислено до broadcast) + `reconcile_in_flight` (on-chain звірка `unsettled_within`) + **confirm-gated** Kredis-settle (decrement лише після on-chain confirm, за сумою самої tx → concurrent надбавки виживають) закривають double-pay crash-window — наступний годинний цикл звіряє on-chain замість сліпої повторної виплати. **Backward-compat:** поріг 0 → миттєва per-event виплата (поведінка за замовчуванням).

Solana `Solana::MintingService` використовує `sendTransaction` з Ed25519-підписом. ATA отримувача резолюється динамічно через `getTokenAccountsByOwner`.

#### 8. Celo (ReFi Community Rewards)

Мережа регенеративних фінансів. Інтеграція стейблкоїна cUSD для грантів та підтримки локальних громад, які доглядають за лісом.

| Параметр | Значення |
|----------|----------|
| **Сервіс** | `Celo::CommunityRewardService` |
| **Воркер** | `CeloRewardWorker` |
| **Черга** | `web3` (пріоритет 7) |
| **Retry** | 3 |
| **Тригер** | `ClusterHealthCheckWorker` (щоденно о 02:00 UTC) — для здорових кластерів |
| **ENV** | `CELO_RPC_URL` — **ОБОВʼЯЗКОВИЙ, фолбека немає** (⚖️ founder 2026-08-31). Доти порожня змінна сідала на `alfajores-forno.celo-testnet.org`, який віддає **NXDOMAIN**; ⚖️ розвʼязано ЗНЯТТЯМ, а не переціленням, і підстава портативна: **фолбек існує щоб пережити брак конфіга, а на грошовому шляху це і є небезпека, не зручність** — тож правило E.49, збудоване її поліціювати, стало непотрібним, а не переобґрунтованим. Тепер порожня змінна дає `KeyError` на КОЖНОМУ Celo-виклику (виплата · підтвердження · відкат мінту), а boot-гард E.49 вижив на третій підставі: він переносить цей `KeyError` із першої продової події на `kamal deploy`. ⛔ Не повертати дефолт у жодній формі — код-сайд-константа, що тихо підставляє інший чейн, обходить саме питання, задля якого існує вісь `WEB3_CHAIN_ENV`. ⚠️ Маркер-скан порожню змінну не бачить — це не змінилось. **[ARCH.50]** `ORACLE_CELO_PRIVATE_KEY` (dedicated Celo-підписант, no fallback — ізолює blast-radius від Polygon-флоту), `CELO_CUSD_CONTRACT_ADDRESS` |
| **Спека** | `spec/services/celo/community_reward_service_spec.rb` |

**Умови нарахування:**
- `stress_index ≤ 0.2` (кластер здоровий)
- `fraud_detected == false`
- Організація має зареєстровану crypto-адресу

**Сума:** 5 cUSD на здоровий кластер на день

**Особливості:** **[ARCH.50]** Money-path-hardened — durable `:pending` intent ПЕРЕД broadcast + dedup на ЛОГІЧНИЙ `reward_date` ВСЕРЕДИНІ chain-prefix Kredis-lock (`lock:web3:celo:oracle:`) + Celo-aware reconcile (`CeloConfirmationWorker`, бо `BlockchainConfirmationWorker` хардкоднутий на Polygon) + deterministic-vs-transient rescue split (dedicated `ORACLE_CELO_PRIVATE_KEY`). Закрив детермінований daily double-pay (логічний ключ ≠ `created_at`-партиція). **[ARCH.64]** Той reconcile покриває лише `:sent`; застрягле `:pending` без tx_hash (transient-timeout → dedup-skip, self-masking retry) підбирає `CeloRewardReconcileWorker` cron (:25/:55) → `:manual_review` (money-safe, не blind re-pay; раніше — тиха недоплата cUSD, дім [`06_08 §2.2`](06_08_Resilience_and_Failover_Policy)).

#### 9. KlimaDAO (ESG Carbon Retirement)

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

#### 10. Chainlink (DON) — ⚪ demoted до internal correlation-marker [ARCH.53]

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

#### 11. Ethereum L1 (State Root Anchoring)

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

## ⚙️ 2. Консенсус "Proof of Growth" — РОЛЬОВА карта мереж (кроки → [`05_02`](05_02_Proof_of_Growth_Pipeline))

> 🏠 **One-Home:** покроковий опис конвеєра (Фази 1–4, Кроки A–F), інвентар гардів обох шляхів мінту та їхні розходження живуть у [`05_02`](05_02_Proof_of_Growth_Pipeline) — це його оголошена Мета. Тут відповідь на інше питання, за яке цю сторінку й цитує [`00_00`](00_00_SSOT_Index): **яка з 11 мереж на якому кроці стоїть і в якій ролі.** Повні картки кожної — §1 вище.

| Крок конвеєра | Мережа / протокол | Роль тут | Дім кроку |
|---|---|---|---|
| Збір і обчислення на краю | — (LoRa · STM32 · mruby) | поза ланцюгами: сенсор, Lorenz, пакування | [`05_02`](05_02_Proof_of_Growth_Pipeline) Фази 1–3 |
| Паспорт вузла | **peaq** | машинна ідентичність дерева (DID) | [`05_02`](05_02_Proof_of_Growth_Pipeline) Крок A |
| Крипто-доказ | **IoTeX** W3bstream | ZK-верифікація телеметрії (activation-gated) | [`05_02`](05_02_Proof_of_Growth_Pipeline) Крок B |
| Oracle-маркування | **Chainlink** ⚪ demoted | latent-шлях; DON unwired [ARCH.53] | [`05_02`](05_02_Proof_of_Growth_Pipeline) Крок C |
| Аудит особи | Polygon **Hadron** ⚫ | KYC-гейт бенефіціара — ⛔ вендора не існує [ARCH.118], статус не виходить із `pending` (картка №6 §1) | [`05_02 §Крок E`](05_02_Proof_of_Growth_Pipeline) |
| Емісія | **Polygon** | mint SCC — два шляхи, гарди РІЗНІ | [`05_02 §DOC.7`](05_02_Proof_of_Growth_Pipeline) |
| Паралельні рейки (post-mint) | **Solana** · **Celo** · **The Graph** · **KlimaDAO** · **Filecoin** | мікро-винагорода · community-винагорода · індексація · ESG-ретайрмент · CID-архів | [`05_02`](05_02_Proof_of_Growth_Pipeline) Крок F |
| Фіналізація | **Ethereum L1** | щотижневий state-root якір | [`05_04`](05_04_Ethereum_L1_State_Anchor) |

⛔ **Не відтворювати тут покрокову механіку — виміряно й відкинуто 2026-09-04 (DOC-T.98).** Копія мала НУЛЬ вхідних рефів і розійшлася з домом на чотирьох осях одразу, з них дві грошові: вигаданий поріг «`TreeFamily` (напр. 20.0)», якого немає ані в моделі, ані в каноні · до-[E.63] модель «гомеостаз → нараховуються `growth_points`» (магнітуда GP є метаболічною `m(delta_t)`, [`03_04 §4.3`](03_04_mruby_Lorenz_Attractor)) · названий не той воркер у KYC-кроці · і сам KYC-гейт поданий прохідним, тоді як картка №6 за 190 рядків вище вже казала протилежне. **Кроки конвеєра нарощують у [`05_02`](05_02_Proof_of_Growth_Pipeline); ця таблиця нарощується лише коли зʼявляється НОВА МЕРЕЖА.**
---

## 📜 3. Смарт-Контракти на Polygon — де вони живуть (поверхня → [`05_03`](05_03_Tokenomics_SCC_and_SFC))

На Polygon розгорнуто **`SilkenCarbonCoin` (SCC)** — utility-токен емісії, і **`SilkenForestCoin` (SFC)** — governance-токен; поруч із ними `SilkenTimelock`, `SilkenGovernor`, `ProtocolParameters` (дім — [`05_06`](05_06_Governance_and_DAO)) і `StateRootAnchor` на Ethereum L1 (дім — [`05_04`](05_04_Ethereum_L1_State_Anchor)).

> 🏠 **One-Home: сигнатури функцій, події, ієрархія ролей і матриця дозволів — [`05_03`](05_03_Tokenomics_SCC_and_SFC), і тільки там.** Там вони стоять **під arity-гейтом** (`scripts/solidity_signature_arity_check.rb`, HARD у `docs.yml`), який червонить розходження з `contracts/*.sol`; будь-яка копія поза цим гейтом старіє мовчки — саме те, що тут і сталося.
>
> ⛔ **Не відтворювати тут перелік функцій — виміряно й відкинуто 2026-09-04 (DOC-T.98).** Копія мала НУЛЬ вхідних рефів і розійшлася на грошовій осі: вона подавала `slash(address, uint256)` **єдиним живим трактом спалення**, тоді як бекенд його не кличе взагалі — живий шлях є `slashUpTo(address, uint256 maxAmount, bytes32 contextHash)` (атомарний кламп до `balanceOf` замість приреченого реверту), а `slash()` лишається **виключно ручним DAO/Timelock-шляхом** ([`05_03`](05_03_Tokenomics_SCC_and_SFC) · [`05_05`](05_05_Slashing_and_Risk_Policy) SLASH.2). Заразом вона тримала `string memory` там, де контракт має `calldata`.

## ⚓ 4. Абсолютна Фіналізація (Ethereum State Root Anchoring)

| Параметр | Значення |
|----------|----------|
| **Воркер** | `EthereumAnchorWorker` (Sidekiq щопонеділка о 03:00 UTC) |
| **Сервіс** | `Ethereum::StateAnchorService` |
| **RPC** | `ALCHEMY_ETHEREUM_RPC_URL` |

```ruby
# Формула — дзеркало SSOT (owner [`05_04`](05_04_Ethereum_L1_State_Anchor)), правити ТАМ.
# Роздільник `|` (pipe), не `:`. [E.53/E.54] + total_sfc, active_tree_count; [ARCH.97] + total_scc_supply — разом ШІСТЬ полів (дім і гейт — [`05_04 §3`](05_04_Ethereum_L1_State_Anchor)).
state_root = Digest::SHA256.hexdigest("#{total_growth_points}|#{total_sfc}|#{active_tree_count}|#{chain_hash}|#{timestamp.iso8601}|#{total_scc_supply}")
```

Цей `bytes32` хеш записується в смарт-контракт на Ethereum Mainnet раз на тиждень. Рівень безпеки Ethereum (сотні мільярдів $) за мінімальну плату за газ.

---

## 🔌 5. Конфігурація Credentials та ENV

### Секрети сервісів — живий дім ENV, vault лише запасний

🔴 **Заголовок цієї таблиці казав «Rails Encrypted Credentials», і це СПРОСТОВАНО виміром** ([`06_04 §5`](06_04_Secrets_Checklist), SEC.22 Phase-2 ✅ 2026-09-02): образ не несе `credentials.yml.enc` (`.dockerignore`, інваріант C `deploy_secret_scan`), тож credentials-половина в контейнері була `nil` **із першого буту**, а `RAILS_MASTER_KEY` знято з усіх пʼяти deploy-поверхонь. Живий шлях КОЖНОГО рядка нижче — `ENV["X"].presence || credentials.x`; імена ENV — `.env.example` + [`06_04 §2.1`](06_04_Secrets_Checklist), гейт парності — `spec/deploy/credentials_env_fallback_spec.rb`. **Читати колонку як «де лежить секрет» означає шукати його там, де його не буває.** ⚠️ Одиниця тут не «сервіс»: `iotex` і `peaq` несуть по дві змінні, тож інжект іде за ПЕРЕЛІКОМ, не за числом ([`S1.1`](00_07_Action_Plan_Tracker)).

| Ключ (vault-імʼя) | Сервіс |
|------------|--------|
| `filecoin_api_key` | Filecoin/Pinata |
| `peaq_node_url`, `peaq_signing_key` | peaq |
| `iotex_w3bstream_url`, `iotex_api_key` | IoTeX |
| `the_graph_api_url` | The Graph |
| `hadron_api_key` | ⚫ **Polygon Hadron — адресата НЕ ІСНУЄ**, не провіжнити ([`06_04 §3`](06_04_Secrets_Checklist) · [`00_07`](00_07_Action_Plan_Tracker) `BIZ.20`) |

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

> **Boot guard:** `Security::Web3NetworkGuard` ([`04_02 §8`](04_02_Business_Logic_and_Services)) fail-closes at boot у production / `WEB3_STRICT_MODE`, якщо будь-який `*_RPC_URL` вище **суперечить ОГОЛОШЕНІЙ чейн-родині слоту** (`WEB3_CHAIN_ENV` ∈ `mainnet`/`testnet`, відсутнє → `mainnet`; на `mainnet` падає testnet-маркер Amoy/devnet/Sepolia…, на `testnet` — навпаки mainnet-ендпоінт: обидва значення є твердженнями, жодне не є послабленням — [OPS.37]) чи порожній `CELO_RPC_URL` при ОЗБРОЄНОМУ Celo-шляху (`armed_path_violations`; зашитих code-side фолбеків у дереві **нуль** з 2026-09-03 — Celo знято ⚖️ 08-31, Polygon `polygon-rpc.com` ⚖️ 09-03 як недосяжний за побудовою після presence-правила `[rpc]`; правило E.49 живе на новій підставі: переносить `KeyError` із першої продової події на деплой (§9)), `ORACLE_*` signer-ключ відсутній/malformed, або silent-address ENV (`DAO_TREASURY_ADDRESS`/SCC/SFC-адреси — use-сайти маскують config-баг під RPC-збій: tax тихо off, chain-audit хибне «clean», fallback-ціна) відсутній/malformed, або Solana signer-четвірка неповна (batch-payout без escalation-шляху) — розширює runtime E.47 Solana-guard (`SOLANA_RPC_URL` за замовчуванням = Devnet) на EVM + boot-time. Live `eth_chainId`-probe свідомо не робиться (нуль RPC-залежності на boot).

---

## 🏗️ 6. Shared Infrastructure Layer

> 🏠 **One-Home — [`04_02 §1`](04_02_Business_Logic_and_Services) «Web3 Utility Layer»; поіменного переліку тут НЕ вести.** ⛔ Виміряно й відкинуто 2026-09-04 (DOC-T.98): копія несла чотири утиліти, тоді як шар мав більше, і бракувало саме **щойно відвантаженої родини підписантів [SEC.17]** (`OracleSigner` · `KeySigner` · `KmsKey` · `LocalEnvSigner`) — тобто перелік старів **лише в бік неповноти** й мовчав саме про money-path-ланку. Перелік росте комітами, а копію пишуть один раз.
>
> Що з цього шару несуче ТУТ (мультичейн-специфіка, і живе воно в картках §1): **fallback-каскад RPC** Primary→Secondary→Public через `fallback_env_keys` і **circuit breaker** `Web3::ResilientClient`. ⚠️ Порогів двоє й вони РІЗНІ — воркерний ⊥ провайдерний; при цитуванні називай, про який ідеться, а дім обох — [`06_08 §2.1`](06_08_Resilience_and_Failover_Policy).

---

## 📊 7. Повна Матриця Сервісів та Черг

> 🏠 **One-Home:** `Черга` · `Retry` · `Cron` · `Активація` кожної ланки живуть у **її картці §1** (реєстр [`00_06 §2`](00_06_SSOT_Documentation_Standard)), а пріоритетна топологія черг — у [`04_02 §11`](04_02_Business_Logic_and_Services). Нижче — лише **індекс «мережа → воркери»**, щоб бачити всі одинадцять одразу.
>
> ⛔ **Колонки `Черга`/`Retry`/`Cron` тут НЕ відновлювати — виміряно й відкинуто 2026-09-04 (DOC-T.98).** Саме вони й протухли: `EthereumAnchorWorker` стояв із `Retry 3` при `retry: 5` у коді, а колонка `Cron` показувала «—» для **всіх** reconcile/backfill-воркерів, чиї крони живі в `config/sidekiq.yml` — тобто таблиця систематично не бачила цілого КЛАСУ ланок, а не помилялась у рядку.

| # | Мережа | Воркер(и) | Картка |
|---|--------|-----------|--------|
| 1 | Filecoin | `FilecoinArchiveWorker` + ре-арм `FilecoinReconcileWorker` | §1 Рівень 1 |
| 2 | peaq | `PeaqRegistrationWorker` + ре-арм `PeaqBackfillWorker` | §1 Рівень 2 |
| 3 | IoTeX | `IotexVerificationWorker` + ре-арм `IotexBackfillWorker` | §1 Рівень 2 |
| 4 | The Graph | — (синхронне читання з контролерів, воркера немає) | §1 Рівень 2 |
| 5 | Polygon | `MintCarbonCoinWorker` · `BurnCarbonTokensWorker` · `MintBatchCollectorWorker` | §1 Рівень 3 |
| 6 | Hadron ⚫ | `HadronKycVerificationWorker` (enqueue гейтований `verification_reachable?` [ARCH.119]) + ре-арм `HadronKycReverifyWorker` (ре-арм гейтований, замір глибини — НІ); `HadronAssetRegistrationWorker` — воркер-сирота (нуль enqueue, [BIZ.11]), тому свідомо НЕ гейтований: гейт на мертвому коді нічого не стереже | §1 Рівень 3 |
| 7 | Solana | `SolanaMicroRewardWorker` · `SolanaBatchPayoutWorker` [E.61] | §1 Рівень 3 |
| 8 | Celo | `CeloRewardWorker` + ре-арм `CeloRewardReconcileWorker` | §1 Рівень 3 |
| 9 | KlimaDAO | `KlimaRetirementWorker` (нуль enqueue — активація за подією) | §1 Рівень 3 |
| 10 | Chainlink ⚪ | `ChainlinkDispatchWorker` (demoted [ARCH.53]) | §1 Рівень 2 |
| 11 | Ethereum L1 | `EthereumAnchorWorker` + `EthereumAnchorConfirmationWorker` + `StuckSentAnchorSweeperWorker` | §1 Рівень 4 |
| — | Cross-chain | `TreasuryMonitorWorker` | [`04_02 §11`](04_02_Business_Logic_and_Services) |

> **Тести.** Spec-шлях кожного сервісу — у його картці §1 (One-Home: інвентар біля підсистеми). Конвенції написання / coverage-гейт / тріаж прогалин — [`04_06`](04_06_Testing_Guide_and_Coverage).
