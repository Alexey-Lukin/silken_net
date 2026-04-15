# 05_04: Ethereum L1 State Anchor (Щотижнева фіналізація)

## 🎯 Мета

Зафіксувати механізм щотижневої фіналізації стану Gaia 2.0 в Ethereum Mainnet. Один раз на тиждень `EthereumAnchorWorker` обчислює 32-байтний SHA-256 `state_root` із глобального стану PostgreSQL та записує його в смарт-контракт `StateRootAnchor`. Після запису стан вважається криптографічно незмінним.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Механізм якорування повністю імплементовано.
- **Цільовий TRL:** TRL 9 — Production-ready з повним gas management та аудит-трейлом у БД.
- **Синхронізація:** 2026-04-15
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
| `Web3::RpcConnectionPool` | `app/services/web3/rpc_connection_pool.rb` | ✅ Real |
| `ApplicationWeb3Worker` | `app/workers/application_web3_worker.rb` | ✅ Real |
| Cron-розклад | `config/sidekiq.yml` | ✅ Сконфігуровано |
| RSpec (worker) | `spec/workers/ethereum_anchor_worker_spec.rb` | ✅ Покрито |
| RSpec (service) | `spec/services/ethereum/state_anchor_service_spec.rb` | ✅ Покрито |
| `StateRootAnchor.sol` | `contracts/` | 🔴 Відсутній (ABI захардкоджено в сервісі) |

---

## 🛑 Відкриті Блокери

### 🔴 BLOCKER-1: Smart Contract відсутній у репозиторії

**Статус:** Критичний архітектурний пробіл.

Директорія `contracts/` містить тільки `SilkenCarbonCoin.sol` та `SilkenForestCoin.sol`. Смарт-контракт `StateRootAnchor`, у який щотижня записується `state_root`, **відсутній у кодбейсі**.

- **Де в коді:** `Ethereum::StateAnchorService` — ABI для `storeStateRoot(bytes32)` захардкоджено inline як Ruby Hash-масив у константі `ANCHOR_ABI`.
- **Вплив:** Неможливо провести аудит контракту, верифікувати його адресу, або задеплоїти повторно через Foundry toolchain.
- **Потрібно:** Створити `contracts/StateRootAnchor.sol`, задеплоїти через Foundry, зберегти адресу в `ENV["ETHEREUM_ANCHOR_CONTRACT"]`.

### 🔴 BLOCKER-2: Відсутність персистентності state_root та tx_hash у БД

**Статус:** Критичний. Відсутній аудит-трейл на рівні бази даних.

`Ethereum::StateAnchorService#anchor_to_l1!` виконує L1-транзакцію та логує `tx_hash` тільки в `Rails.logger`. Якщо процес падає після успішного відправлення транзакції, але до збереження результату, **відновити що саме було заанкоровано — неможливо**.

- **Де в коді:** `Ethereum::StateAnchorService#anchor_to_l1!` — немає жодного `ActiveRecord` збереження.
- **Вплив:** Відсутність аудит-трейлу є проблемою для інституційних інвесторів та регуляторного compliance.
- **Потрібно:** Модель `EthereumAnchor` або поле в `AuditLog` для збереження `{ state_root, tx_hash, anchored_at, block_number }`.

### 🔴 BLOCKER-3: Відсутність gas management (лімітів та fee caps)

**Статус:** Критичний фінансовий ризик.

Виклик `client.transact(contract, "storeStateRoot", root_bytes, sender_key: anchor_key, legacy: false)` не передає явних параметрів газу:

- **Немає `gas_limit`** — `ruby-eth` самостійно оцінює через `eth_estimateGas`. При пере-завантаженні мережі оцінка може бути хибною.
- **Немає `max_fee_per_gas` / `max_priority_fee_per_gas`** — незважаючи на EIP-1559 (`legacy: false`), верхній ліміт вартості транзакції не встановлено. Під час gas spike (як у грудні 2021: >500 Gwei) транзакція може коштувати $100–$500.
- **Де в коді:** `Ethereum::StateAnchorService#anchor_to_l1!` — рядок `client.transact(...)`.
- **Потрібно:** Додати `max_fee_per_gas`, `max_priority_fee_per_gas` через ENV або Chainlink Gas Oracle. Встановити safety cap.

### 🟡 BLOCKER-4: Відсутність перевірки балансу oracle-гаманця (частково вирішено)

**Статус:** Частково вирішено через Treasury monitoring (PR #253).

`BlockchainMintingService` (Polygon) має явний guard clause: `raise if balance < 0.05 MATIC`. `Ethereum::StateAnchorService` **не перевіряє баланс ETH** на гаманці `ETHEREUM_ANCHOR_PRIVATE_KEY` перед відправленням L1-транзакції.

**Покращення [PR #253]:** `Treasury::MonitorService` (cron кожні 15 хв) тепер моніторить баланс ETH на `ETHEREUM_ANCHOR_PRIVATE_KEY` гаманці з порогом `0.01 ETH`. При balance < threshold:
- Prometheus gauge `ORACLE_BALANCE{network="ethereum"}` < threshold
- `ORACLE_BALANCE_RATIO{network="ethereum"}` < 1.0
- `EwsAlert.create(alert_type: :system_fault, severity: :critical)` — оперативне сповіщення

**Залишається:** Inline guard clause в `StateAnchorService#anchor_to_l1!` (raise перед transact) ще не додано — покладаємося на proactive моніторинг.

### 🟡 BLOCKER-5: ENV-змінна `ALCHEMY_ETHEREUM_RPC_URL` не задокументована в `.env.example`

**Статус:** Середній. Невідповідність між кодом і документацією.

В `docs/BLOCKCHAIN_DEVELOPMENT.md` та `config/` Ethereum RPC задокументовано як `ETHEREUM_RPC_URL`, але в `Ethereum::StateAnchorService` та `Web3::RpcConnectionPool` використовується `ALCHEMY_ETHEREUM_RPC_URL`. Файл `.env.example` відсутній у репозиторії.

- **Де в коді:** `app/services/ethereum/state_anchor_service.rb` рядок `Web3::RpcConnectionPool.client_for("ALCHEMY_ETHEREUM_RPC_URL")`.
- **Вплив:** Новий розробник або CI/CD-пайплайн може не встановити правильну ENV-змінну і отримати `KeyError: key not found: "ALCHEMY_ETHEREUM_RPC_URL"` під час деплою.
- **Потрібно:** Синхронізувати документацію та додати `.env.example`.

### 🟡 BLOCKER-6: Non-reproducible state_root через timestamp

**Статус:** Середній. Архітектурне обмеження верифікації.

`generate_state_root` включає `Time.current.utc.iso8601` у хеш-payload. Це означає:

- **Неможливо незалежно відтворити** той самий `state_root` без знання точного timestamp виконання.
- Зовнішній аудитор, знаючи `total_scc` та `chain_hash`, **не може верифікувати** хеш без додаткових метаданих.
- **Де в коді:** `Ethereum::StateAnchorService#generate_state_root` — `timestamp = Time.current.utc.iso8601`.
- **Потрібно (для TRL 9):** Зберігати `{ total_scc, chain_hash, anchored_at }` разом з `tx_hash` (пов'язано з BLOCKER-2), щоб аудитор міг самостійно відтворити хеш.

### 🟢 INFO: state_root є SHA-256 flat hash, а не Merkle Root

**Статус:** Інформаційний. Архітектурне рішення (прийнятне для TRL 8).

Попри назву "State Root" (яка імплікує Merkle Tree), поточна реалізація використовує плаский SHA-256 хеш трьох полів:
```
SHA256("#{total_scc}|#{chain_hash}|#{timestamp}")
```
Це технічно є коректним commitment-схемою, але не є справжнім Merkle Root над усіма деревами/транзакціями. Для TRL 9 можна розглянути справжній Merkle Tree над `TelemetryLog.chain_hash` значеннями за тиждень.

### 🟢 INFO: retry: 3 може бути недостатнім для L1

**Статус:** Інформаційний.

`EthereumAnchorWorker` налаштований на `retry: 3`. Ethereum Mainnet може бути перевантажений годинами (наприклад, під час NFT drops або DeFi ліквідацій). Інші Web3 воркери мають `retry: 5` (IoTeX, peaq, Filecoin). Три спроби з Sidekiq exponential backoff (~45 хвилин загалом) може бути недостатньо для відновлення після мережевого congestion.

---

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

  sidekiq_options queue: "web3_low", retry: 3, unique_for: 1.hour

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
| **Retry** | 3 | Exponential backoff; ⚠️ може бути недостатньо (BLOCKER INFO) |
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
state_root = SHA256("#{total_scc}|#{latest_chain_hash}|#{timestamp}")
```

де:

| Поле | Джерело | Тип | Приклад |
|------|---------|-----|---------|
| `total_scc` | `Wallet.sum(:scc_balance)` | Float (сума всіх SCC-балансів у системі) | `"1250000.5"` |
| `latest_chain_hash` | `AuditLog.order(created_at: :desc, id: :desc).pick(:chain_hash)` | String або `"GENESIS"` якщо AuditLog порожній | `"a3f8c2..."` |
| `timestamp` | `Time.current.utc.iso8601` | ISO 8601 UTC рядок | `"2026-03-23T03:00:01Z"` |

### Покроковий алгоритм (Ruby)

```ruby
def generate_state_root
  # 1. Сума всіх SCC-балансів у системі (cross-chain total supply snapshot)
  total_scc = Wallet.sum(:scc_balance)

  # 2. chain_hash останнього AuditLog (криптографічна ланцюгова прив'язка)
  #    order: created_at DESC, id DESC — гарантує детерміновану сортировку при рівному часі
  latest_chain_hash = AuditLog.order(created_at: :desc, id: :desc).pick(:chain_hash) || "GENESIS"

  # 3. Timestamp моменту формування хешу (⚠️ BLOCKER-6: non-reproducible)
  timestamp = Time.current.utc.iso8601

  # 4. Конкатенація через | роздільник
  payload = "#{total_scc}|#{latest_chain_hash}|#{timestamp}"

  # 5. SHA-256 хешування → 64-символьний hex рядок (256 bits / 32 bytes)
  Digest::SHA256.hexdigest(payload)
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
| Timestamp виконання | Lorenz Z-value статистика |
| | SFC supply |
| | Merkle root над індивідуальними tree hashes |

> **Примітка:** Це SHA-256 flat commitment, а не повноцінний Merkle Root (детальніше — BLOCKER INFO).

---

## 4. Відправка L1 Транзакції

**Файл:** `app/services/ethereum/state_anchor_service.rb`  
**Метод:** `Ethereum::StateAnchorService#anchor_to_l1!`

### Повний флоу

```
generate_state_root()
       │
       ▼
Web3::RpcConnectionPool.client_for("ALCHEMY_ETHEREUM_RPC_URL")
       │ Thread-cached Eth::Client → Alchemy Ethereum Mainnet HTTPS endpoint
       │
       ▼
Eth::Key.new(priv: ENV.fetch("ETHEREUM_ANCHOR_PRIVATE_KEY"))
       │ Secp256k1 приватний ключ → Ethereum адреса oracle-гаманця
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
                sender_key: anchor_key, legacy: false)
       │ legacy: false → EIP-1559 транзакція (Type 2)
       │ ⚠️ BLOCKER-3: max_fee_per_gas / gas_limit НЕ встановлено
       │
       ▼
TX Hash → Rails.logger.info "⚓ [Ethereum L1] State Root anchored: #{state_root} → TX: #{tx_hash}"
       │ ⚠️ BLOCKER-2: tx_hash НЕ зберігається в БД
       │
       ▼
return tx_hash
```

### ENV-змінні (обов'язкові)

| Змінна | Призначення | Де використовується |
|--------|-------------|---------------------|
| `ALCHEMY_ETHEREUM_RPC_URL` | Alchemy Ethereum Mainnet HTTPS endpoint | `Web3::RpcConnectionPool.client_for(...)` |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | Secp256k1 приватний ключ oracle-гаманця | `Eth::Key.new(priv: ...)` |
| `ETHEREUM_ANCHOR_CONTRACT` | Адреса `StateRootAnchor` контракту на Mainnet | `Eth::Contract.from_abi(address: ...)` |

> ⚠️ **Безпека:** `ETHEREUM_ANCHOR_PRIVATE_KEY` ніколи не повинен потрапляти в Git. Зберігається в Rails encrypted credentials або secrets manager (AWS Secrets Manager / GCP Secret Manager при деплої через Kamal).

### Smart Contract ABI (захардкоджено в сервісі)

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
**Метод контракту:** `storeStateRoot(bytes32 root)` — nonpayable (не приймає ETH, тільки gas)  
**Gas:** Оцінюється автоматично `ruby-eth` через `eth_estimateGas` ⚠️ (BLOCKER-3)

---

## 5. Обробка Помилок

```ruby
rescue Net::OpenTimeout, Net::ReadTimeout => e
  Rails.logger.error "🛑 [Ethereum L1] Timeout: #{e.message}"
  raise "Ethereum L1 Timeout: #{e.message}"

rescue IOError => e
  Rails.logger.error "🛑 [Ethereum L1] Connection error: #{e.message}"
  raise "Ethereum L1 Connection Error: #{e.message}"
```

| Помилка | Джерело | Дія |
|---------|---------|-----|
| `Net::OpenTimeout` | RPC endpoint недоступний | Log + raise → Sidekiq retry (до 3 разів) |
| `Net::ReadTimeout` | Відповідь від Alchemy перевищила таймаут | Log + raise → Sidekiq retry |
| `IOError` | TCP з'єднання розірвано | Log + raise → Sidekiq retry |
| `HTTPX::TimeoutError` | (від `ApplicationWeb3Worker`) | Prometheus counter + raise |
| `HTTPX::ConnectionError` | (від `ApplicationWeb3Worker`) | Prometheus counter + raise |
| `KeyError` | `ENV.fetch("ALCHEMY_ETHEREUM_RPC_URL")` якщо не встановлено | Crash без retry ⚠️ |

> **Важливо:** Після вичерпання 3 retry-спроб Sidekiq переміщує задачу в Dead Queue. Чергове спрацювання cron (наступний понеділок) відправить новий `state_root` — **пропущений тиждень не буде перезаписано**.

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
| `incorporates timestamp so results differ over time` | Timestamp впливає на результат |
| `returns L1 transaction hash on success` | `anchor_to_l1!` повертає tx_hash |
| `connects to Alchemy Ethereum RPC` | Правильний RPC endpoint |
| `calls storeStateRoot with a 0x-prefixed bytes32 root` | Формат bytes32 аргументу |
| `rescues Net::OpenTimeout` | Timeout → RuntimeError з описом |
| `rescues Net::ReadTimeout` | Timeout → RuntimeError з описом |
| `rescues IOError` | Connection error → RuntimeError з описом |
| `logs successful anchoring` | Rails.logger.info при успіху |

### `spec/workers/ethereum_anchor_worker_spec.rb`

| Тест | Що перевіряє |
|------|-------------|
| `calls Ethereum::StateAnchorService#anchor_to_l1!` | Делегація до сервісу |
| `uses the web3_low queue` | Правильна черга |
| `has retry set to 3` | Кількість retry |
| `re-raises errors after logging` | Error propagation для Sidekiq retry |

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
║    EthereumAnchorWorker (web3_low, cron: '0 3 * * 1')               ║
║       │                                                              ║
║       ▼                                                              ║
║    generate_state_root():                                            ║
║      total_scc    = Wallet.sum(:scc_balance)         [PostgreSQL]   ║
║      chain_hash   = AuditLog.last.chain_hash         [PostgreSQL]   ║
║      timestamp    = Time.current.utc.iso8601         [Runtime]      ║
║      state_root   = SHA256(scc|hash|ts)              [CPU]          ║
║       │                                                              ║
║       ▼                                                              ║
║    anchor_to_l1!(state_root):                                        ║
║      Alchemy RPC → Ethereum Mainnet                                  ║
║      storeStateRoot(bytes32) → TX Hash                              ║
║      Rails.logger.info "⚓ State Root anchored"                      ║
║      ⚠️ БД НЕ оновлюється (BLOCKER-2)                               ║
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

# Адреса StateRootAnchor контракту на Mainnet
ETHEREUM_ANCHOR_CONTRACT=0x...      # ⚠️ Контракт відсутній у contracts/ (BLOCKER-1)
```

### Рекомендовані перевірки перед деплоєм

```bash
# 1. Переконатись, що всі ENV встановлені:
bundle exec rails runner "ENV.fetch('ALCHEMY_ETHEREUM_RPC_URL'); ENV.fetch('ETHEREUM_ANCHOR_PRIVATE_KEY'); ENV.fetch('ETHEREUM_ANCHOR_CONTRACT'); puts 'OK'"

# 2. Перевірити баланс oracle-гаманця (> 0.01 ETH):
# Через Alchemy Dashboard або etherscan.io

# 3. Запустити тести:
bundle exec rspec spec/services/ethereum/ spec/workers/ethereum_anchor_worker_spec.rb
```

---

## Зміни від Попередньої Версії SSOT

> Цей документ є **першою версією** синхронізованого SSOT для модуля 05_04.  
> Попередня документація: відсутня (TRL 7 — механізм існував, але не був задокументований).

| Аспект | До (TRL 7) | Після (TRL 8) |
|--------|-----------|--------------|
| Документація | Відсутня | Повна (цей документ) |
| Cron-розклад | В коді, не задокументований | `'0 3 * * 1'` — задокументовано |
| Алгоритм state_root | Неочевидний з коду | Точна формула SHA256(scc\|hash\|ts) |
| Блокери | Не виявлені | 4 критичних + 2 середніх + 2 інфо |
| RSpec покриття | Існувало | Задокументовано (12 тестів сервісу, 4 тести воркера) |

---

*Документ синхронізовано з кодбейсом `Alexey-Lukin/silken_net` станом на **2026-03-23**.  
Наступна синхронізація — після вирішення BLOCKER-1 (StateRootAnchor.sol) та BLOCKER-2 (DB persistence).*
