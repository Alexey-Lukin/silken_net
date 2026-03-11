# 🔗 Блокчейн, Гаманці та Токени — Гід розробника (Gaia 2.0)

> Повний гід по налаштуванню мультичейн Web3-інфраструктури Silken Net: 12 мереж та протоколів — від Polygon до Ethereum L1.

---

## Зміст

1. [Архітектура](#архітектура)
2. [Змінні середовища](#змінні-середовища)
3. [Локальне налаштування](#локальне-налаштування)
4. [Тестове середовище](#тестове-середовище)
5. [Продакшин](#продакшин)
6. [Потік мінтингу (SCC/SFC)](#потік-мінтингу)
7. [Slashing Protocol](#slashing-protocol)
8. [Sidekiq черги та воркери](#sidekiq-черги-та-воркери)
9. [Смарт-контракти](#смарт-контракти)
10. [Мультичейн інтеграції (Gaia 2.0)](#мультичейн-інтеграції-gaia-20)
11. [Безпека та критичні механізми](#безпека-та-критичні-механізми)
12. [Troubleshooting](#troubleshooting)

---

## Архітектура

```
Sensor → TelemetryLog → growth_points → Wallet.balance
                                           ↓
           ┌───── Verification Pipeline ─────────────────────────┐
           │ peaq DID → IoTeX ZK-proof → Chainlink Oracle        │
           └─────────────────────────────────────────────────────┘
                                           ↓
                          TokenomicsEvaluatorWorker (щогодини)
                                           ↓
                          balance >= 10,000? → lock_and_mint!
                                           ↓
                          BlockchainMintingService → Polygon mint()
                          (guards: iotex + chainlink + hadron_kyc)
                                           ↓
                          BlockchainConfirmationWorker → confirm!()
                                           ↓
                 ┌─────────────────────────────────────────────┐
                 │  Parallel: Solana micro-rewards (USDC)      │
                 │  Parallel: Celo community rewards (cUSD)    │
                 │  Index: The Graph subgraph (GraphQL)        │
                 │  Archive: Filecoin/IPFS (CID)               │
                 │  Weekly: Ethereum L1 state root (bytes32)   │
                 └─────────────────────────────────────────────┘

         AiInsight (stress >= 0.8) → contract_breach?
                                           ↓
                          BurnCarbonTokensWorker → slash() on Polygon
                                           ↓
                          Optional: KlimaDAO retirement (ESG offset)
```

### Подвійна токен-система (Polygon)

| Токен | Тип | Контракт | Призначення |
|-------|-----|----------|-------------|
| **SCC** (Silken Carbon Coin) | ERC-20 + AccessControl + Pausable | `SilkenCarbonCoin.sol` | Утилітарний токен за секвестрацію вуглецю |
| **SFC** (Silken Forest Coin) | ERC-20 + Votes + Permit (EIP-712) | `SilkenForestCoin.sol` | Governance-токен для DAO |

---

## Змінні середовища

### Обов'язкові

```bash
# Polygon RPC (Alchemy)
ALCHEMY_POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY

# Oracle-гаманець (керує мінтингом/слешингом)
ORACLE_PRIVATE_KEY=0x...  # ⚠️ НІКОЛИ не комітити!

# Адреси смарт-контрактів (Polygon)
CARBON_COIN_CONTRACT_ADDRESS=0x...  # SCC
FOREST_COIN_CONTRACT_ADDRESS=0x...  # SFC
```

### Мультичейн (Gaia 2.0)

```bash
# Ethereum L1 (State Anchoring)
ETHEREUM_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

# IoTeX W3bstream (ZK Verification)
W3BSTREAM_API_URL=https://w3bstream-api.iotex.io
W3BSTREAM_PROJECT_ID=silken_net_dmrv

# Chainlink Functions (Oracle)
CHAINLINK_ROUTER_ADDRESS=0x...  # Polygon Chainlink Router
CHAINLINK_SUBSCRIPTION_ID=...

# peaq DID (Machine Identity)
PEAQ_NODE_URL=https://peaq-node.example.com

# Solana (Micro-Rewards)
SOLANA_RPC_URL=https://api.mainnet-beta.solana.com
SOLANA_WALLET_KEYPAIR=...  # Base58 keypair

# Celo (Community Rewards)
CELO_RPC_URL=https://forno.celo.org
CELO_CUSD_CONTRACT_ADDRESS=0x...

# KlimaDAO (Carbon Retirement)
KLIMA_RETIREMENT_CONTRACT_ADDRESS=0x...

# Polygon Hadron (RWA Compliance)
HADRON_API_URL=https://api.hadron.polygon.technology
HADRON_API_KEY=...

# Streamr (P2P Data)
STREAMR_API_URL=https://streamr.network/api/v2
STREAMR_STREAM_ID=silken_net/forest_telemetry

# Filecoin/IPFS (Archive)
PINATA_API_KEY=...
PINATA_SECRET_KEY=...

# The Graph (Indexing)
THE_GRAPH_SUBGRAPH_URL=https://api.thegraph.com/subgraphs/name/silken-net/carbon

# Akash Network (Deployment)
AKASH_WALLET_ADDRESS=...
```

### Опціональні

```bash
# PostgreSQL (для тестів)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=password
POSTGRES_HOST=localhost

# CoAP listener
COAP_PORT=5683
```

---

## Локальне налаштування

### 1. Створіть `.env` файл

```bash
cp .env.example .env   # або створіть вручну
```

Заповніть змінні. Для **локальної розробки** використовуйте Polygon Amoy Testnet:

```bash
ALCHEMY_POLYGON_RPC_URL=https://polygon-amoy.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
ORACLE_PRIVATE_KEY=0xYOUR_TESTNET_PRIVATE_KEY
CARBON_COIN_CONTRACT_ADDRESS=0xYOUR_DEPLOYED_SCC
FOREST_COIN_CONTRACT_ADDRESS=0xYOUR_DEPLOYED_SFC
```

### 2. Деплой контрактів на тестнет

```bash
# Встановіть Foundry (https://book.getfoundry.sh/)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Деплой SCC
cd contracts/
forge create SilkenCarbonCoin --rpc-url $ALCHEMY_POLYGON_RPC_URL --private-key $ORACLE_PRIVATE_KEY

# Деплой SFC
forge create SilkenForestCoin --rpc-url $ALCHEMY_POLYGON_RPC_URL --private-key $ORACLE_PRIVATE_KEY
```

Збережіть адреси контрактів у `.env`.

### 3. Поповніть Oracle-гаманець MATIC

Для Amoy Testnet: [faucet.polygon.technology](https://faucet.polygon.technology/)

Мінімальний баланс Oracle: **0.05 MATIC** (перевірка в `BlockchainMintingService`).

### 4. Запустіть інфраструктуру

```bash
bundle install
bin/rails db:create db:migrate

# Запуск всіх сервісів (Rails + Sidekiq + Tailwind)
bin/dev
```

### 5. Перевірте потік мінтингу вручну

```ruby
# rails console

# Створіть тестові дані
tree = Tree.first
wallet = tree.wallet || tree.create_wallet!(balance: 0, crypto_public_address: "0x1234567890abcdef1234567890abcdef12345678")

# Симулюйте накопичення балансу
wallet.credit!(15_000)

# Запустіть оцінку токеноміки вручну
TokenomicsEvaluatorWorker.new.perform

# Перевірте створену транзакцію
BlockchainTransaction.last
# => status: :pending, amount: 1.0, locked_points: 10000
```

---

## Тестове середовище

### Нюанси для RSpec

Тести **не потребують** реального RPC. Блокчейн-сервіси тестуються з моками:

```ruby
# spec/rails_helper.rb
ENV['RAILS_ENV'] ||= 'test'

# Фейкові адреси контрактів для тестів
ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x" + "0" * 40
ENV["FOREST_COIN_CONTRACT_ADDRESS"] ||= "0x" + "0" * 40
```

### Фабрики

```ruby
# spec/factories/wallets.rb
factory :wallet do
  tree
  balance { 0 }
  crypto_public_address { "0x1234567890abcdef1234567890abcdef12345678" }
end

# spec/factories/blockchain_transactions.rb
factory :blockchain_transaction do
  wallet
  amount { 10.0 }
  token_type { :carbon_coin }
  status { :confirmed }
  to_address { "0x1234567890abcdef1234567890abcdef12345678" }
  tx_hash { SecureRandom.hex(32) }
end
```

### Запуск тестів

```bash
# Всі тести
bundle exec rspec

# Тільки блокчейн/гаманці
bundle exec rspec spec/models/wallet_spec.rb
bundle exec rspec spec/models/blockchain_transaction_spec.rb

# Сервіси
bundle exec rspec spec/services/

# Воркери
bundle exec rspec spec/workers/
```

### Що мокати в інтеграційних тестах

Сервіси `BlockchainMintingService` та `BlockchainBurningService` використовують gem `eth` для взаємодії з Polygon RPC. У тестах замокайте:

```ruby
# Приклад мока для мінтингу
allow_any_instance_of(Eth::Client).to receive(:transact).and_return("0xfake_tx_hash")
allow_any_instance_of(Eth::Client).to receive(:eth_get_transaction_receipt).and_return({
  "result" => { "status" => "0x1", "blockNumber" => "0x100" }
})
```

---

## Продакшин

### 1. Змінні середовища

```bash
# Polygon Mainnet
ALCHEMY_POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/PRODUCTION_KEY
ORACLE_PRIVATE_KEY=<зберігається в Rails credentials або Vault>
CARBON_COIN_CONTRACT_ADDRESS=0x<mainnet_scc_address>
FOREST_COIN_CONTRACT_ADDRESS=0x<mainnet_sfc_address>
```

> ⚠️ **ORACLE_PRIVATE_KEY** — найкритичніший секрет. Зберігайте в `rails credentials:edit` або HashiCorp Vault. Ніколи не в `.env` на продакшині.

### 2. Деплой контрактів на Mainnet

```bash
# Переконайтесь, що контракти пройшли аудит
# Використовуйте multi-sig для ownership

forge create SilkenCarbonCoin \
  --rpc-url $ALCHEMY_POLYGON_RPC_URL \
  --private-key $ORACLE_PRIVATE_KEY \
  --verify --etherscan-api-key $POLYGONSCAN_API_KEY
```

### 3. Sidekiq конфігурація

```yaml
# config/sidekiq.yml
concurrency: 15

queues:
  - [uplink, 5]    # Телеметрія (КРИТИЧНО)
  - [alerts, 4]    # Сповіщення
  - [critical, 4]  # Slashing (КРИТИЧНО)
  - [downlink, 3]  # Команди актуаторів
  - [default, 2]   # Стандартні задачі
  - [web3, 1]      # Блокчейн (НИЗЬКИЙ — повільний RPC)
  - [low, 1]       # Аналітика
```

### 4. Моніторинг

| Метрика | Критичний рівень | Дія |
|---------|-----------------|-----|
| Oracle MATIC баланс | < 0.05 MATIC | Поповнити гаманець |
| `BlockchainTransaction.status_failed` | > 0 за годину | Перевірити RPC/gas |
| Sidekiq `web3` черга | > 100 jobs | Перевірити Alchemy rate limits |
| `AiInsight.fraudulent` | > 0 | Перевірити телеметрію вузлів |

---

## Потік мінтингу

```
TokenomicsEvaluatorWorker (щогодини, cron: "0 * * * *")
│
├── Знаходить Wallet.where("balance >= ?", 10_000)
├── Для кожного:
│   ├── Pessimistic lock (SELECT ... FOR UPDATE)
│   ├── tokens = balance / EMISSION_THRESHOLD (10,000)
│   ├── Зменшує wallet.balance
│   └── Створює BlockchainTransaction(status: :pending)
│
└── Збирає всі pending tx_ids → MintCarbonCoinWorker
    │
    └── BlockchainMintingService.call_batch(tx_ids)
        ├── З'єднання з Alchemy RPC
        ├── Перевірка Oracle balance >= 0.05 MATIC
        ├── Групування по token_type (SCC/SFC)
        ├── 1 tx → mint() | Багато → batchMint() [≤200]
        ├── Fire-and-Forget: client.transact()
        ├── Оновлення status → :sent, збереження tx_hash
        └── Schedule BlockchainConfirmationWorker (30s delay)
            │
            └── Поллінг eth_get_transaction_receipt
                ├── status 0x1 → confirm!()
                ├── status 0x0 → fail!() (EVM revert)
                └── Немає рецепту → retry (10 спроб)
```

---

## Slashing Protocol

```
DailyAggregationWorker (01:00 UTC)
│ └── InsightGeneratorService → AiInsight per tree
│
ClusterHealthCheckWorker (02:00 UTC)
│ ├── Для кожного NaasContract:
│ │   ├── Рахує дерева з stress_index >= 1.0
│ │   └── Якщо > 20% аномальних → activate_slashing_protocol!
│ │
│ └── BurnCarbonTokensWorker (queue: critical)
│     └── BlockchainBurningService.call()
│         ├── total_minted = confirmed SCC по кластеру
│         ├── damage_ratio = critical_trees / total_trees
│         ├── burn_amount = total_minted × damage_ratio
│         ├── slash() на CARBON_COIN_CONTRACT_ADDRESS
│         ├── NaasContract.status → :breached
│         ├── BlockchainTransaction аудит-запис
│         └── EwsAlert + MaintenanceRecord
```

> ⚠️ Slashing є **необоротним** на блокчейні. `NaasContract` помічається як `:breached` одразу в БД, навіть якщо RPC тимчасово недоступний.

---

## Sidekiq черги та воркери

### Розклад (sidekiq-scheduler)

| Воркер | Розклад | Черга | Призначення |
|--------|---------|-------|-------------|
| `TokenomicsEvaluatorWorker` | `0 * * * *` | default | Мінтинг pending SCC |
| `DailyAggregationWorker` | `0 1 * * *` | low | Телеметрія → AiInsight |
| `ClusterHealthCheckWorker` | `0 2 * * *` | default | Аудит здоров'я, slashing |

### Блокчейн воркери

| Воркер | Черга | Retry | Призначення |
|--------|-------|-------|-------------|
| `MintCarbonCoinWorker` | web3 | 5 | Батч-мінтинг (до 200 tx) |
| `BlockchainConfirmationWorker` | web3 | 10 | Поллінг receipt, confirm/fail |
| `BurnCarbonTokensWorker` | critical | 5 | Виконання slash() |

---

## Смарт-контракти

Знаходяться в `contracts/`:

### SilkenCarbonCoin.sol

```
ERC-20 + AccessControl + Pausable

Функції:
  mint(to, amount, treeDid)         — Тільки MINTER_ROLE (Oracle)
  batchMint(to[], amounts[], dids[]) — Атомарний батч
  slash(investor, amount)           — Тільки SLASHER_ROLE, спалює токени
  pause() / unpause()               — ADMIN_ROLE
```

### SilkenForestCoin.sol

```
ERC-20 + Votes + Permit (EIP-712) + AccessControl + Pausable

Функції:
  mint(to, amount, clusterId)
  batchMint(to[], amounts[], clusterIds[])
  permit()                          — Gasless approvals (EIP-712)
  delegate()                        — DAO голосування
```

---

## Мультичейн інтеграції (Gaia 2.0)

### Verification Pipeline (Trust Layer)

```
TelemetryLog (uplink)
    ↓
IotexVerificationWorker → Iotex::W3bstreamVerificationService
    ↓ (verified_by_iotex = true, zk_proof_ref saved)
ChainlinkDispatchWorker → Chainlink::OracleDispatchService
    ↓ (oracle_status = "fulfilled")
MintCarbonCoinWorker → BlockchainMintingService
    ↓ (guard: verified_by_iotex? + oracle_status + hadron_kyc_status)
Polygon: mint(investor, amount, tree_did)
```

### peaq DID (Machine Passport)

```ruby
# Peaq::DidRegistryService
did = "did:peaq:0x#{Digest::SHA256.hexdigest(seed)[0, 40]}"
# Реєструється при provisioning дерева через PeaqRegistrationWorker
```

### Solana Micro-Rewards

```ruby
# Solana::MintingService
# Parallel to Polygon — instant USDC micro-payments
SolanaMicroRewardWorker.perform_async(telemetry_log_id, created_at_iso)
```

### Celo Community ReFi

```ruby
# Celo::CommunityRewardService
# Triggered by ClusterHealthCheckWorker when cluster is healthy
CeloRewardWorker.perform_async(cluster_id, date_str)
```

### KlimaDAO ESG Retirement

```ruby
# KlimaDao::RetirementService
# Initiated by organization for ESG carbon offset
KlimaRetirementWorker.perform_async(wallet_id, amount)
```

### Polygon Hadron (RWA Compliance)

```ruby
# Polygon::HadronComplianceService
# Two flows: verify_investor! (KYC) and register_asset! (RWA)
HadronAssetRegistrationWorker.perform_async(cluster_id)
```

### Ethereum L1 State Anchoring

```ruby
# Ethereum::StateAnchorService
# Weekly: SHA-256(total_scc + chain_hash + timestamp) → Ethereum Mainnet
# Scheduled: Monday 03:00 UTC via sidekiq-scheduler
```

### The Graph (Subgraph)

```
subgraph/
├── schema.graphql      # CarbonMintEvent entity
├── subgraph.yaml       # Network: polygon-amoy (TODO: mainnet)
└── src/mapping.ts      # handleCarbonMinted event handler
```

Queried via `TheGraph::QueryService.total_carbon_minted`.

### Streamr (Real-Time P2P)

```ruby
# Streamr::BroadcasterService
# Non-blocking broadcast to Streamr P2P network
StreamrBroadcastWorker.perform_async(telemetry_log_id)
```

### Filecoin/IPFS (Eternal Memory)

```ruby
# Filecoin::ArchiveService — archive AuditLog to IPFS (Pinata API)
# Filecoin::VerificationService — verify CID integrity
FilecoinArchiveWorker.perform_async(audit_log_id)
```

---

## Безпека та критичні механізми

| Механізм | Де використовується | Навіщо |
|----------|---------------------|--------|
| **Pessimistic Lock** | `Wallet#lock_and_mint!` | Захист від race condition при мінтингу |
| **Kredis Lock** (60s) | Blockchain services | Oracle single-use гарантія |
| **Atomic DB Transactions** | Всі сервіси | Консистентність balance/status |
| **Fire-and-Forget** | `BlockchainMintingService` | Неблокуючі RPC виклики |
| **Rollback on Exhaustion** | `MintCarbonCoinWorker` | Повернення points якщо RPC failed 5x |
| **Oracle Balance Check** | `BlockchainMintingService` | Fail якщо < 0.05 MATIC |
| **Batch Size Limit** | `MintCarbonCoinWorker` | ≤200 tx (gas limits) |
| **BigDecimal precision** | `AiInsight#contract_breach?` | Без похибки float для фінансових рішень |

---

## Troubleshooting

### "Oracle balance too low"

```bash
# Перевірте баланс Oracle
rails runner "puts BlockchainMintingService.new.send(:check_oracle_balance)"
```

Поповніть гаманець MATIC на Polygonscan.

### Транзакції застрягли в `pending`

```ruby
# Знайдіть застряглі
BlockchainTransaction.where(status: :pending).where("created_at < ?", 1.hour.ago)

# Перезапустіть мінтинг
MintCarbonCoinWorker.perform_async
```

### "uninitialized constant Eth::Client"

```bash
bundle install  # gem 'eth' може бути не встановлений
```

### Тести падають з Connection refused

```bash
# PostgreSQL не запущено
sudo pg_ctlcluster 16 main start

# Або Redis для Sidekiq
redis-server &
```

### Slashing виконано, але контракт не breached в БД

Перевірте логи `BurnCarbonTokensWorker` в Sidekiq dashboard. NaasContract маркується `:breached` перед RPC-викликом, тому це не повинно статися.
