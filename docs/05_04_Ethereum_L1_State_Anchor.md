# 05_04: Ethereum L1 State Anchor (Щотижнева фіналізація)

## 🎯 Мета

Зафіксувати механізм щотижневої фіналізації стану Gaia 2.0 в Ethereum Mainnet. Один раз на тиждень `EthereumAnchorWorker` обчислює 32-байтний SHA-256 `state_root` із глобального стану PostgreSQL та записує його в смарт-контракт `StateRootAnchor`. Після запису стан вважається криптографічно незмінним.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Механізм якорування повністю імплементовано.
- **Цільовий TRL:** TRL 9 — Production-ready з повним gas management та аудит-трейлом у БД.
- **Синхронізація:** 2026-04-16
- **Пов'язані модулі:**
  - Мультичейн → [`05_01_Multichain_Architecture`](05_01_Multichain_Architecture)
  - Proof of Growth → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)
  - Токеноміка → [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC)

---

## 💡 Огляд

Ethereum L1 State Anchor — це **фінальна печатка** всього стану системи Gaia 2.0. Один раз на тиждень (щопонеділка о 03:00 UTC) `EthereumAnchorWorker` запускає `Ethereum::StateAnchorService`, який:

1. Збирає глобальний стан системи з PostgreSQL (загальний SCC-баланс + останній chain_hash AuditLog + timestamp)
2. Стискає його в 32-байтний SHA-256 хеш (`state_root`)
3. Записує `bytes32` хеш у смарт-контракт `StateRootAnchor` на **Ethereum Mainnet** через Alchemy RPC

> **Архітектурний принцип:** Після запису в L1 стан Gaia 2.0 вважається незмінним — будь-який аудитор може перевірити відповідність локальної бази даних зафіксованому хешу. Це перетворює SilkenNet із Web2-сервісу на криптографічно верифіковану систему.

---

## 📋 Статус Імплементації

| Компонент | Файл | Статус |
|-----------|------|--------|
| `EthereumAnchorWorker` | `app/workers/ethereum_anchor_worker.rb` | ✅ Real |
| `Ethereum::StateAnchorService` | `app/services/ethereum/state_anchor_service.rb` | ✅ Real |
| `EthereumAnchor` | `app/models/ethereum_anchor.rb` | ✅ Real |
| Міграція | `db/migrate/20260415140000_create_ethereum_anchors.rb` | ✅ Applied |
| `Web3::RpcConnectionPool` | `app/services/web3/rpc_connection_pool.rb` | ✅ Real |
| `ApplicationWeb3Worker` | `app/workers/application_web3_worker.rb` | ✅ Real |
| Cron-розклад | `config/sidekiq.yml` | ✅ Сконфігуровано |
| RSpec (worker) | `spec/workers/ethereum_anchor_worker_spec.rb` | ✅ Покрито |
| RSpec (service) | `spec/services/ethereum/state_anchor_service_spec.rb` | ✅ Покрито |
| RSpec (model) | `spec/models/ethereum_anchor_spec.rb` | ✅ Покрито |
| `StateRootAnchor.sol` | `contracts/StateRootAnchor.sol` | ✅ Real |

---

## ✅ Закриті Блокери (PR #254)

### ✅ BLOCKER-1: `StateRootAnchor.sol` створено

`contracts/StateRootAnchor.sol` додано до репозиторію. Контракт успадковує `AccessControl` (OpenZeppelin), визначає роль `ANCHOR_ROLE`, зберігає `latestRoot`, `anchorCount`, маппінг `rootTimestamps` та емітує `StateRootStored(bytes32 indexed root, uint256 timestamp, uint256 anchorIndex)`. Дедуплікація: `require(rootTimestamps[root] == 0, "root already anchored")` — кожен state root можна записати тільки один раз. Деплой через Foundry; адреса зберігається в `ENV["ETHEREUM_ANCHOR_CONTRACT"]`.

### ✅ BLOCKER-2: Персистентність state_root у БД — `EthereumAnchor` модель

Модель `EthereumAnchor` (таблиця `ethereum_anchors`) зберігає повний аудит-трейл кожної L1 операції. `anchor_to_l1!` тепер **до TX** створює запис `status: :pending` (crash recovery), після TX — `update!(status: :sent, tx_hash:)`. Race condition safety: Sidekiq `unique_for: 7.days` + DB unique index на `state_root`.

### ✅ BLOCKER-3: Gas management з safety caps

Явні константи: `DEFAULT_GAS_LIMIT = 100_000`, `DEFAULT_MAX_FEE_GWEI = 100`, `DEFAULT_PRIORITY_FEE_GWEI = 2`. Всі перекриваються ENV: `ETHEREUM_MAX_FEE_GWEI`, `ETHEREUM_PRIORITY_FEE_GWEI`, `ETHEREUM_GAS_LIMIT`. Захист від gas spikes.

### ✅ BLOCKER-4: Inline ETH balance guard

`MIN_ANCHOR_BALANCE_WEI = 0.01 ETH`. Перед `client.transact(...)` перевіряється баланс: `balance = client.get_balance(anchor_key.address)`. При `balance < MIN_ANCHOR_BALANCE_WEI` — `anchor.update!(status: :failed, error_message: ...)` + raise. `EwsAlert` через `TreasuryMonitorWorker` (cron кожні 15 хв) є додатковим проактивним шаром.

### ✅ BLOCKER-5: `.env.example` з усіма ENV-змінними

`.env.example` додано до репозиторію з документацією всіх ENV-змінних включаючи `ALCHEMY_ETHEREUM_RPC_URL`, `ETHEREUM_ANCHOR_PRIVATE_KEY`, `ETHEREUM_ANCHOR_CONTRACT` та gas management змінні.

### ✅ BLOCKER-6: Reproducible state_root — збережені компоненти

`generate_state_root` повертає `Hash { state_root, total_scc, chain_hash, anchored_at }`. Всі компоненти зберігаються в `EthereumAnchor`. `EthereumAnchor#verify_state_root` дозволяє зовнішньому аудитору незалежно відтворити хеш: `SHA256("#{total_scc}|#{chain_hash}|#{anchored_at.utc.iso8601}")`.

---

> **Усі блокери нижче вирішені в PR #254.** Секція збережена для історичної довідки.

### ✅ ~~BLOCKER-1~~: `StateRootAnchor.sol` — вирішено

~~Директорія `contracts/` містить тільки `SilkenCarbonCoin.sol` та `SilkenForestCoin.sol`. Смарт-контракт `StateRootAnchor`, у який щотижня записується `state_root`, **відсутній у кодбейсі**.~~

- **Статус:** ✅ Вирішено. `contracts/StateRootAnchor.sol` створено з `AccessControl`, `ANCHOR_ROLE`, deduplicate guard.

### ✅ ~~BLOCKER-2~~: Персистентність state_root — вирішено

~~`Ethereum::StateAnchorService#anchor_to_l1!` виконує L1-транзакцію та логує `tx_hash` тільки в `Rails.logger`.~~

- **Статус:** ✅ Вирішено. Модель `EthereumAnchor` зберігає повний аудит-трейл. Crash recovery через `status: :pending` до TX.

## 1. Cron-Розклад (The Ethereum Seal)

**Файл:** `config/sidekiq.yml`

```yaml
:scheduler:
  :schedule:
    ethereum_state_anchor:
      cron: '0 3 * * 1'   # Щопонеділка о 03:00 UTC
      class: EthereumAnchorWorker
```

| Параметр | Значення | Обґрунтування |
|----------|----------|---------------|
| **Частота** | 1 раз на тиждень | Gas-ефективність: тільки 1 L1-транзакція на тиждень |
| **День** | Понеділок | Після завершення всіх нічних воркерів (DailyAggregation о 01:00, ClusterHealth о 02:00) |
| **Час** | 03:00 UTC | Гарантовано після `DailyAggregationWorker` (01:00) та `ClusterHealthCheckWorker` (02:00) |
| **Часовий пояс** | UTC | Всі Sidekiq cron задачі — UTC |

**Вікно виконання:** Між 03:00 і 04:00 UTC щопонеділка (з урахуванням Sidekiq backoff при помилках).

---

## 2. Sidekiq Worker

**Файл:** `app/workers/ethereum_anchor_worker.rb`

```ruby
class EthereumAnchorWorker
  include ApplicationWeb3Worker

  sidekiq_options queue: "web3_low", retry: 5, unique_for: 1.hour

  def perform
    with_web3_error_handling("Ethereum", "L1 State Anchor") do
      Ethereum::StateAnchorService.new.anchor_to_l1!
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [EthereumAnchor] L1 anchoring failed: #{e.message}"
    raise
  end
end
```

| Параметр | Значення | Пояснення |
|----------|----------|-----------|
| **Queue** | `web3_low` | Найнижчий Web3-пріоритет — некритичні, але важливі L1 операції |
| **Priority** | 2 з 9 | Обробляється після всіх критичних Web3-задач |
| **Retry** | 5 | Exponential backoff (~2+ годин); достатньо для L1 congestion recovery |
| **unique_for** | 1.hour | Запобігає паралельному запуску тижневих циклів (idempotency guard) |
| **Mixin** | `ApplicationWeb3Worker` | RPC Rate Limiter (50 req/s), уніфіковане error handling, Prometheus метрики |

**`ApplicationWeb3Worker` надає:**
- `with_web3_error_handling(chain, resource)` — обгортка з Prometheus лічильниками (`RPC_ERRORS_TOTAL`)
- `WEB3_RPC_LIMITER` — Sidekiq Enterprise rate limiter (50 req/s на всі Web3 воркери)
- Перехоплення: `HTTPX::TimeoutError`, `HTTPX::ConnectionError`, `Net::OpenTimeout`, `Net::ReadTimeout`, `Errno::ECONNREFUSED`, `Errno::ECONNRESET`, `IOError`

---

## 3. Алгоритм Формування state_root

**Файл:** `app/services/ethereum/state_anchor_service.rb`  
**Метод:** `Ethereum::StateAnchorService#generate_state_root`

### Формула

```
state_root = SHA256("#{total_scc}|#{chain_hash}|#{anchored_at.iso8601}")
```

де:

| Поле | Джерело | Тип | Приклад |
|------|---------|-----|---------|
| `total_scc` | `Wallet.sum(:scc_balance)` | Decimal (сума всіх SCC-балансів у системі) | `"1250000.5"` |
| `chain_hash` | `AuditLog.order(created_at: :desc, id: :desc).pick(:chain_hash)` | String або `"GENESIS"` якщо AuditLog порожній | `"a3f8c2..."` |
| `anchored_at` | `Time.current.utc` | UTC DateTime (зберігається в `EthereumAnchor.anchored_at`) | `2026-03-23T03:00:01Z` |

### Покроковий алгоритм (Ruby)

```ruby
def generate_state_root
  # [SNAPSHOT ISOLATION]: REPEATABLE READ гарантує consistent snapshot
  # між паралельними MintCarbonCoinWorker / AuditLogWorker записами
  ActiveRecord::Base.transaction(isolation: :repeatable_read) do
    # 1. Сума всіх SCC-балансів у системі (cross-chain total supply snapshot)
    total_scc = Wallet.sum(:scc_balance)

    # 2. chain_hash останнього AuditLog (криптографічна ланцюгова прив'язка)
    #    order: created_at DESC, id DESC — гарантує детерміновану сортировку при рівному часі
    latest_chain_hash = AuditLog.order(created_at: :desc, id: :desc).pick(:chain_hash) || "GENESIS"

    # 3. Timestamp моменту формування хешу (зберігається в EthereumAnchor.anchored_at)
    timestamp = Time.current.utc

    # 4. Конкатенація через | роздільник
    payload = "#{total_scc}|#{latest_chain_hash}|#{timestamp.iso8601}"

    # 5. SHA-256 хешування → 64-символьний hex рядок (256 bits / 32 bytes)
    state_root = Digest::SHA256.hexdigest(payload)

    # 6. Повернути всі компоненти для збереження в EthereumAnchor (BLOCKER-6)
    { state_root: state_root, total_scc: total_scc, chain_hash: latest_chain_hash, anchored_at: timestamp }
  end
end
```

### Приклад payload та результату

```
Payload:  "1250000.5|a3f8c2d1e4b7f9a0c2e5d8b1f4a7e0d3c6b9e2a5f8c1d4e7b0a3f6c9d2e5|2026-03-23T03:00:01Z"
Result:   "7f4a9b2c1e8d3f6a0b5c8e2d7a4f1b9e3c6d0a7f4b1e8d5c2a9f6b3e0d7a4c1"  (64 hex chars = 32 bytes)
```

### Що включено / що відсутнє

| Включено ✅ | Відсутнє ⚠️ |
|------------|------------|
| Загальний SCC supply (всі гаманці) | Кількість активних дерев |
| Останній AuditLog chain_hash | TelemetryLog count за тиждень |
| Timestamp виконання (збережений в БД) | Lorenz Z-value статистика |
| `REPEATABLE READ` snapshot isolation | SFC supply |
| | Merkle root над індивідуальними tree hashes |

> **Примітка:** Це SHA-256 flat commitment, а не повноцінний Merkle Root. Для TRL 9 можна розглянути справжній Merkle Tree над `TelemetryLog.chain_hash` значеннями за тиждень. Незалежна верифікація: `EthereumAnchor#verify_state_root` відтворює хеш з збережених компонентів.

---

## 4. Відправка L1 Транзакції

**Файл:** `app/services/ethereum/state_anchor_service.rb`  
**Метод:** `Ethereum::StateAnchorService#anchor_to_l1!`

### Повний флоу

```
generate_state_root()
       │
       ▼
generate_state_root()  →  { state_root, total_scc, chain_hash, anchored_at }
       │
       ▼
EthereumAnchor.create!(state_root:, total_scc:, chain_hash:, anchored_at:, status: :pending)
       │ Crash recovery: запис існує до TX (якщо процес впаде — запис залишиться в :pending)
       │
       ▼
Web3::RpcConnectionPool.client_for("ALCHEMY_ETHEREUM_RPC_URL")
       │ Thread-cached Eth::Client → Alchemy Ethereum Mainnet HTTPS endpoint
       │
       ▼
Eth::Key.new(priv: ENV.fetch("ETHEREUM_ANCHOR_PRIVATE_KEY"))
       │
       ▼
balance = client.get_balance(anchor_key.address)
       │ balance < MIN_ANCHOR_BALANCE_WEI (0.01 ETH)?
       │   → anchor.update!(status: :failed) + raise
       │
       ▼
Eth::Contract.from_abi(name: "StateRootAnchor", address: ETHEREUM_ANCHOR_CONTRACT, abi: ANCHOR_ABI)
       │ ABI: storeStateRoot(bytes32 root) nonpayable
       │
       ▼
root_bytes = "0x#{state_root}"   # 64-char hex → 0x-prefixed bytes32
       │
       ▼
client.transact(contract, "storeStateRoot", root_bytes,
                sender_key: anchor_key, legacy: false,
                gas_limit: DEFAULT_GAS_LIMIT,          # 100_000 (ENV-overridable)
                max_fee_per_gas: DEFAULT_MAX_FEE_GWEI,  # 100 Gwei cap
                max_priority_fee_per_gas: DEFAULT_PRIORITY_FEE_GWEI)  # 2 Gwei tip
       │
       ▼
anchor.update!(status: :sent, tx_hash:)
       │
       ▼
Rails.logger.info "⚓ [Ethereum L1] State Root anchored: #{state_root} → TX: #{tx_hash}"
       │
       ▼
return anchor   # EthereumAnchor instance
```

### ENV-змінні

| Змінна | Призначення | Default |
|--------|-------------|---------|
| `ALCHEMY_ETHEREUM_RPC_URL` | Alchemy Ethereum Mainnet HTTPS endpoint | — (required) |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | Secp256k1 приватний ключ oracle-гаманця | — (required) |
| `ETHEREUM_ANCHOR_CONTRACT` | Адреса `StateRootAnchor` контракту на Mainnet | — (required) |
| `ETHEREUM_MAX_FEE_GWEI` | Gas fee cap (Gwei) | `100` |
| `ETHEREUM_PRIORITY_FEE_GWEI` | Validator tip (Gwei) | `2` |
| `ETHEREUM_GAS_LIMIT` | Gas limit для `storeStateRoot` | `100_000` |

> ⚠️ **Безпека:** `ETHEREUM_ANCHOR_PRIVATE_KEY` ніколи не повинен потрапляти в Git. Зберігається в Rails encrypted credentials або secrets manager.

### Smart Contract ABI (в константі `ANCHOR_ABI`)

```json
[
  {
    "inputs": [
      { "internalType": "bytes32", "name": "root", "type": "bytes32" }
    ],
    "name": "storeStateRoot",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
]
```

**Тип транзакції:** EIP-1559 (`legacy: false`)  
**Метод контракту:** `storeStateRoot(bytes32 root)` — nonpayable  
**Gas:** `DEFAULT_GAS_LIMIT = 100_000` (safety cap), `storeStateRoot` потребує ~45,000 gas (1 SSTORE + event)

---

## 5. Обробка Помилок

```ruby
rescue Net::OpenTimeout, Net::ReadTimeout => e
  anchor&.update!(status: :failed, error_message: e.message.truncate(500)) if anchor&.persisted?
  Rails.logger.error "🛑 [Ethereum L1] Timeout: #{e.message}"
  raise "Ethereum L1 Timeout: #{e.message}"

rescue IOError => e
  anchor&.update!(status: :failed, error_message: e.message.truncate(500)) if anchor&.persisted?
  Rails.logger.error "🛑 [Ethereum L1] Connection error: #{e.message}"
  raise "Ethereum L1 Connection Error: #{e.message}"
```

| Помилка | Джерело | Дія |
|---------|---------|-----|
| Insufficient balance | `balance < MIN_ANCHOR_BALANCE_WEI` | `anchor.update!(status: :failed)` + raise → retry |
| `Net::OpenTimeout` | RPC endpoint недоступний | `anchor.update!(status: :failed)` + raise → retry |
| `Net::ReadTimeout` | Відповідь від Alchemy перевищила таймаут | `anchor.update!(status: :failed)` + raise → retry |
| `IOError` | TCP з'єднання розірвано | `anchor.update!(status: :failed)` + raise → retry |
| `HTTPX::TimeoutError` | (від `ApplicationWeb3Worker`) | Prometheus counter + raise |
| `HTTPX::ConnectionError` | (від `ApplicationWeb3Worker`) | Prometheus counter + raise |
| `KeyError` | `ENV.fetch(...)` якщо не встановлено | Crash без retry |

> **Важливо:** Після вичерпання 5 retry-спроб Sidekiq переміщує задачу в Dead Queue. Чергове спрацювання cron (наступний понеділок) відправить новий `state_root` з іншим `anchored_at` — **пропущений тиждень не буде перезаписано**.

### Double-Anchoring Guard

**Проблема:** Якщо `client.transact()` відправив TX в мемпул Ethereum, але відповідь не дійшла (timeout), код маркує anchor як `:failed` і Sidekiq робить retry. На retry генерується новий `state_root` і відправляється нова TX. Обидві TX (з різними `state_root`) можуть підтвердитись на L1 (nonce, nonce+1), що призведе до двох state roots за один тиждень.

**Рішення:** `anchor_to_l1!` перед генерацією нового `state_root` перевіряє `EthereumAnchor.in_flight` (статус `:pending` або `:sent`, `created_at > 1.week.ago`):

| In-flight статус | Поведінка |
|-----------------|-----------|
| `:sent` | TX може бути в мемпулі — **повертає існуючий anchor без нової TX** |
| `:pending` | Anchor створено, але TX не відправлена (crash recovery) — **перевикористовує існуючий anchor** і відправляє TX з його `state_root` |
| Немає in-flight | Стандартний флоу: `generate_state_root()` → `EthereumAnchor.create!` → `client.transact()` |

---

## 6. Web3::RpcConnectionPool

**Файл:** `app/services/web3/rpc_connection_pool.rb`

```ruby
Web3::RpcConnectionPool.client_for("ALCHEMY_ETHEREUM_RPC_URL")
```

- **Thread-safe:** кожен Sidekiq-потік отримує власний `Eth::Client` через `Thread.current`
- **Кешування:** клієнт створюється один раз per-thread, перевикористовується для наступних викликів
- **Fallback:** якщо `fallback:` не переданий (як у `StateAnchorService`) — `ENV.fetch` кидає `KeyError` при відсутній змінній (fail-fast поведінка)
- **Reset:** `Web3::RpcConnectionPool.reset!` скидає всі кеші (використовується в тестах)

---

## 7. RSpec Покриття

### `spec/services/ethereum/state_anchor_service_spec.rb`

| Тест | Що перевіряє |
|------|-------------|
| `returns a 64-character SHA256 hex string` | Формат `state_root` |
| `incorporates total scc_balance from all wallets` | `Wallet.sum(:scc_balance)` впливає на результат |
| `incorporates chain_hash from latest AuditLog` | AuditLog chain_hash впливає на результат |
| `uses GENESIS fallback when no AuditLog exists` | Порожній AuditLog → `"GENESIS"` fallback |
| `creates EthereumAnchor with status: pending before TX` | Crash recovery: запис до TX |
| `updates EthereumAnchor to sent with tx_hash on success` | Persistence BLOCKER-2 |
| `raises and sets status: failed if ETH balance too low` | Balance guard BLOCKER-4 |
| `uses gas_limit, max_fee_per_gas, priority_fee from ENV` | Gas management BLOCKER-3 |
| `stores all state_root components for independent verification` | BLOCKER-6 |
| `connects to Alchemy Ethereum RPC` | Правильний RPC endpoint |
| `calls storeStateRoot with a 0x-prefixed bytes32 root` | Формат bytes32 аргументу |
| `rescues Net::OpenTimeout and updates anchor to failed` | Timeout + EthereumAnchor persistence |
| `rescues Net::ReadTimeout and updates anchor to failed` | Timeout + EthereumAnchor persistence |
| `rescues IOError and updates anchor to failed` | Connection error + EthereumAnchor persistence |
| `logs successful anchoring` | Rails.logger.info при успіху |

### `spec/workers/ethereum_anchor_worker_spec.rb`

| Тест | Що перевіряє |
|------|-------------|
| `calls Ethereum::StateAnchorService#anchor_to_l1!` | Делегація до сервісу |
| `uses the web3_low queue` | Правильна черга |
| `has retry set to 5` | Кількість retry |
| `re-raises errors after logging` | Error propagation для Sidekiq retry |

### `spec/models/ethereum_anchor_spec.rb`

| Тест | Що перевіряє |
|------|-------------|
| validations (presence, uniqueness, format) | state_root, tx_hash, total_scc, chain_hash |
| `verify_state_root` | Відтворення хешу з компонентів (незалежна верифікація) |
| `etherscan_url` | URL генерація для confirmed TX |
| scopes: `recent`, `successful`, `latest_confirmed` | AR scopes |
| enum status transitions | pending/sent/confirmed/failed |

---

## 8. Місце в Gaia 2.0 Pipeline

```
╔══════════════════════════════════════════════════════════════════════╗
║  ЩОТИЖНЕВИЙ ЦИКЛ L1 ЯКОРЯ (The Ethereum Seal)                       ║
║                                                                      ║
║  Понеділок 01:00 UTC                                                 ║
║    DailyAggregationWorker → InsightGeneratorService                 ║
║    AuditLog.chain_hash оновлено                                      ║
║                                                                      ║
║  Понеділок 02:00 UTC                                                 ║
║    ClusterHealthCheckWorker → Slashing Protocol (якщо потрібно)     ║
║    Wallet.scc_balance може змінитись (BurnCarbonTokensWorker)       ║
║                                                                      ║
║  Понеділок 03:00 UTC ← ТОЧКА ФІНАЛІЗАЦІЇ                            ║
║    EthereumAnchorWorker (web3_low, cron: '0 3 * * 1', retry: 5)     ║
║       │                                                              ║
║       ▼                                                              ║
║    generate_state_root():                                            ║
║      [REPEATABLE READ transaction]                                   ║
║      total_scc    = Wallet.sum(:scc_balance)         [PostgreSQL]   ║
║      chain_hash   = AuditLog.last.chain_hash         [PostgreSQL]   ║
║      anchored_at  = Time.current.utc                 [Runtime]      ║
║      state_root   = SHA256(scc|hash|ts)              [CPU]          ║
║       │                                                              ║
║       ▼                                                              ║
║    EthereumAnchor.create!(status: :pending)          [PostgreSQL]   ║
║       │                                                              ║
║       ▼                                                              ║
║    anchor_to_l1!:                                                    ║
║      ETH balance guard (>= 0.01 ETH)                                ║
║      Alchemy RPC → Ethereum Mainnet                                  ║
║      storeStateRoot(bytes32, gas_limit:, max_fee:)                  ║
║      EthereumAnchor.update!(status: :sent, tx_hash:)  [PostgreSQL] ║
║      Rails.logger.info "⚓ State Root anchored"                      ║
╚══════════════════════════════════════════════════════════════════════╝
          │
          ▼
    Ethereum Mainnet (L8)
    StateRootAnchor Contract
    bytes32 state_root → незмінний запис на L1
    
    "Те, що сталося в SilkenNet до цього моменту, є істиною,
     і її більше ніколи не можна змінити."
```

### Позиція в 8-шаровій архітектурі

```
L8  Ethereum L1    ← ТИЖНЕВА ФІНАЛІЗАЦІЯ (цей модуль)
L7  Polygon + DeFi ← SCC/SFC minting (05_03)
L6  Verification   ← peaq, IoTeX, Streamr, Filecoin (05_02)
L5  Rails Backend  ← Telemetry, Services, Workers (04_xx)
```

---

## 9. Залежності

### Висхідні (Requires — повинні завершитись до 03:00 UTC)

| Модуль | Воркер | Час | Що надає |
|--------|--------|-----|---------|
| 05_02 Proof of Growth | `DailyAggregationWorker` | 01:00 UTC | Оновлені `AuditLog.chain_hash` за добу |
| 05_03 Tokenomics | `ClusterHealthCheckWorker` + `BurnCarbonTokensWorker` | 02:00 UTC | Фінальний `Wallet.scc_balance` після slashing |

### Низхідні (Blocks)

| Що блокує | Причина |
|-----------|---------|
| Довіра інституційних інвесторів | Без L1 anchor система = Web2 БД без криптографічних гарантій |
| Регуляторний D-MRV compliance | ISO 14064 / Verra VCS вимагають незмінного audit trail |
| Публічна верифікація carbon credits | SCC токени без L1 finality не мають незалежної верифікації |

---

## 10. Конфігурація Production

### Обов'язкові ENV (для деплою через Kamal)

```bash
# Alchemy Ethereum Mainnet RPC
ALCHEMY_ETHEREUM_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

# Oracle-гаманець для підпису L1 транзакцій
ETHEREUM_ANCHOR_PRIVATE_KEY=0x...   # ⚠️ НІКОЛИ не комітити!

# Адреса StateRootAnchor контракту на Mainnet (contracts/StateRootAnchor.sol)
ETHEREUM_ANCHOR_CONTRACT=0x...

# Gas management (опціональні; значення за замовчуванням — безпечні для більшості умов)
ETHEREUM_MAX_FEE_GWEI=100        # Default: 100 Gwei cap
ETHEREUM_PRIORITY_FEE_GWEI=2     # Default: 2 Gwei (validator tip)
ETHEREUM_GAS_LIMIT=100000        # Default: 100_000 (storeStateRoot ~45k gas)
```

### Рекомендовані перевірки перед деплоєм

```bash
# 1. Переконатись, що всі ENV встановлені:
bundle exec rails runner "ENV.fetch('ALCHEMY_ETHEREUM_RPC_URL'); ENV.fetch('ETHEREUM_ANCHOR_PRIVATE_KEY'); ENV.fetch('ETHEREUM_ANCHOR_CONTRACT'); puts 'OK'"

# 2. Перевірити баланс oracle-гаманця (> 0.01 ETH):
# Через Alchemy Dashboard або etherscan.io

# 3. Запустити тести:
bundle exec rspec spec/services/ethereum/ spec/workers/ethereum_anchor_worker_spec.rb spec/models/ethereum_anchor_spec.rb
```

---

## Зміни від Попередньої Версії SSOT

| Аспект | TRL 8 (до PR #254) | TRL 9 (після PR #254) |
|--------|-----------|--------------|
| `StateRootAnchor.sol` | 🔴 Відсутній | ✅ `contracts/StateRootAnchor.sol` |
| `EthereumAnchor` модель | 🔴 Відсутня | ✅ `app/models/ethereum_anchor.rb` |
| Персистентність state_root | 🔴 Тільки logger | ✅ PostgreSQL аудит-трейл |
| Gas management | 🔴 Відсутній | ✅ Явні caps + ENV overrides |
| ETH balance guard | 🟡 Тільки Treasury monitor | ✅ Inline guard перед TX |
| `.env.example` | 🔴 Відсутній | ✅ Додано до репозиторію |
| Reproducible state_root | 🔴 Non-reproducible | ✅ Компоненти збережені в EthereumAnchor |
| Worker retry | 3 | 5 |

---

## 🔒 Security Audit — StateRootAnchor

> **Синхронізація:** 2026-04-16. Проведено внутрішній аналіз потенційних вразливостей контракту StateRootAnchor.

### Проаналізовані Проблеми

| # | Проблема | Вердикт | Обґрунтування |
|---|----------|---------|---------------|
| 6 | Immutability — неможливість корекції state root | ❌ Невалідна | Іммутабельність — основний архітектурний принцип L8. Корекція підриває trust model |
| 9 | Відсутня валідація формату root | ❌ Невалідна | `bytes32(0)` вже перевіряється. SHA-256 формат неможливо валідувати on-chain |
| 10 | Відсутній upgrade mechanism | ❌ Невалідна | Intentional design. Governance DAO заплановано post-TRL 6 |

### Деталі

**Іммутабельність state root (#6):** Запропоноване рішення (`correctStateRoot()`) фундаментально підриває trust model L1 anchoring. Якщо admin може "виправляти" state roots, система перестає бути криптографічно верифікованою — це еквівалентно мутабельній БД. Кожен тиждень генерує новий `state_root` з унікальним `anchored_at` timestamp — пропущений або помилковий тиждень не впливає на наступні якорення. Дедуплікація (`rootTimestamps[root] == 0`) запобігає повторному запису.

**Валідація формату root (#9):** Перевірка `root != bytes32(0)` вже реалізована. Валідувати, що `bytes32` є "валідним SHA-256 хешем", **неможливо** — SHA-256 може видати будь-яке 256-бітне значення. Запропонована перевірка `root != latestRoot` є **шкідливою**: при нульовій активності протоколу між тижнями (малоймовірно, але можливо в pre-launch) легітимний однаковий root буде відхилений.

**Операційна рекомендація:** Використовувати Gnosis Safe multisig для `ANCHOR_ROLE` admin (DEFAULT_ADMIN_ROLE) — стандартна operational security practice для production deployment.

Повний аналіз безпеки всіх контрактів: див. [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC.md) → секція "Аудит Безпеки Смарт-Контрактів".

---

*Документ синхронізовано з кодбейсом `Alexey-Lukin/silken_net` станом на **2026-04-16**.*
