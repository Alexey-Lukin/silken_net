# 05_04: Ethereum L1 State Anchor (Щотижнева фіналізація)

## 🎯 Мета

Зафіксувати механізм щотижневої фіналізації стану SilkenNet в Ethereum Mainnet. Один раз на тиждень `EthereumAnchorWorker` обчислює 32-байтний SHA-256 `state_root` із глобального стану PostgreSQL та записує його в смарт-контракт `StateRootAnchor`. Після запису стан вважається криптографічно незмінним.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Механізм якорування повністю імплементовано (broadcast + confirmation-lifecycle → `:confirmed`/`:failed`/`:manual_review` + stuck-reconcile, [ARCH.66] §5.1).
- **Цільовий TRL:** TRL 9 — ⚠️ **НЕ «deploy»**: mainnet-присутність із лімітом емісії та multi-sig настає вже на TRL 7-8; TRL 9 = доведена стабільна робота + зняття лімітів/DAO (⛔ не переписуй це на «TRL 9 = mainnet deploy»: та редакція суперечила корекції [`00_03 §4`](00_03_TRL_Matrix_HIL_and_Beyond), узгоджено 2026-08-22). Технічний маркер модуля лишається той самий: контракт на Ethereum Mainnet + перший щотижневий anchor підтверджено, per [`00_03`](00_03_TRL_Matrix_HIL_and_Beyond). Поточні gas-management + аудит-трейл у БД вже на рівні TRL 8.
- **Відкрите:** Production gas-management tuning + Mainnet contract deploy → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) | Мультичейн (L1 у стеку фіналізації) |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Pipeline (джерело state даних) |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | Токеноміка (`total_scc_supply`/`total_sfc` у root) |
| [`05_05` — Slashing and Risk Policy](05_05_Slashing_and_Risk_Policy) | Slashing/burn змінює total_supply між anchor-вікнами |
| [`05_06` — Governance and DAO](05_06_Governance_and_DAO) | Timelock керує `ANCHOR_ROLE`-ротацією (admin=Timelock) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (Mainnet deploy, gas) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Огляд](#-огляд)
- [Статус Імплементації](#-статус-імплементації)
- [1. Cron-Розклад (The Ethereum Seal)](#1-cron-розклад-the-ethereum-seal)
- [2. Sidekiq Worker](#2-sidekiq-worker)
- [3. Алгоритм Формування state_root](#3-алгоритм-формування-state_root)
- [4. Відправка L1 Транзакції](#4-відправка-l1-транзакції)
- [5. Обробка Помилок](#5-обробка-помилок)
- [5.1 Підтвердження та Reconcile](#51-підтвердження-та-reconcile-arch66)
- [6. Web3::RpcConnectionPool](#6-web3rpcconnectionpool)
- [7. RSpec Покриття](#7-rspec-покриття)
- [8. Місце в SilkenNet Pipeline](#8-місце-в-silkennet-pipeline)
- [9. Залежності](#9-залежності)
- [10. Конфігурація Production](#10-конфігурація-production)
- [Перспективи Розвитку L1 Якоріння](#-перспективи-розвитку-l1-якоріння)
<!-- TOC:AUTO:END -->

---

## 💡 Огляд

Ethereum L1 State Anchor — це **фінальна печатка** всього стану системи SilkenNet. Один раз на тиждень (щопонеділка о 03:00 UTC) `EthereumAnchorWorker` запускає `Ethereum::StateAnchorService`, який:

1. Збирає глобальний стан системи з PostgreSQL (бали росту всіх гаманців + чинний SCC-supply + кумулятивні SFC-мінтинги + кількість активних дерев + останній chain_hash AuditLog + timestamp)
2. Стискає його в 32-байтний SHA-256 хеш (`state_root`)
3. Записує `bytes32` хеш у смарт-контракт `StateRootAnchor` на **Ethereum Mainnet** через Alchemy RPC

> **Архітектурний принцип:** Після запису в L1 стан SilkenNet вважається незмінним — будь-який аудитор може перевірити відповідність локальної бази даних зафіксованому хешу. Це перетворює SilkenNet із Web2-сервісу на криптографічно верифіковану систему.

---

## 📋 Статус Імплементації

| Компонент | Файл | Статус |
|-----------|------|--------|
| `EthereumAnchorWorker` | `app/workers/ethereum_anchor_worker.rb` | ✅ Real |
| `EthereumAnchorConfirmationWorker` [ARCH.66] | `app/workers/ethereum_anchor_confirmation_worker.rb` | ✅ Real |
| `StuckSentAnchorSweeperWorker` [ARCH.66] | `app/workers/stuck_sent_anchor_sweeper_worker.rb` | ✅ Real |
| `Ethereum::StateAnchorService` | `app/services/ethereum/state_anchor_service.rb` | ✅ Real |
| `EthereumAnchor` | `app/models/ethereum_anchor.rb` | ✅ Real |
| Міграція (base) | `db/migrate/20260415140000_create_ethereum_anchors.rb` | ✅ Applied |
| Міграція (E.53/E.54) | `db/migrate/20260424165615_add_sfc_and_tree_count_to_ethereum_anchors.rb` | ✅ Applied |
| `Web3::RpcConnectionPool` | `app/services/web3/rpc_connection_pool.rb` | ✅ Real |
| `ApplicationWeb3Worker` | `app/workers/application_web3_worker.rb` | ✅ Real |
| Cron-розклад | `config/sidekiq.yml` | ✅ Сконфігуровано |
| RSpec (worker) | `spec/workers/ethereum_anchor_worker_spec.rb` | ✅ Покрито |
| RSpec (confirmation) [ARCH.66] | `spec/workers/ethereum_anchor_confirmation_worker_spec.rb` | ✅ Покрито |
| RSpec (sweeper) [ARCH.66] | `spec/workers/stuck_sent_anchor_sweeper_worker_spec.rb` | ✅ Покрито |
| RSpec (service) | `spec/services/ethereum/state_anchor_service_spec.rb` | ✅ Покрито |
| RSpec (model) | `spec/models/ethereum_anchor_spec.rb` | ✅ Покрито |
| `StateRootAnchor.sol` | `contracts/StateRootAnchor.sol` | ✅ Real |

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

  sidekiq_options queue: "web3_low", retry: 5, unique_for: 7.days

  # [S6.6] Maximum gap between anchors before alerting (8 days = 1 week + 1 day buffer).
  MISSED_ANCHOR_THRESHOLD = 8.days

  def perform
    detect_missed_anchor_weeks!

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
| **unique_for** | 7.days | Запобігає перетину тижневих anchoring циклів (idempotency guard) |
| **Mixin** | `ApplicationWeb3Worker` | RPC Rate Limiter (50 req/s), уніфіковане error handling, Prometheus метрики |

**Захист від пропущених тижнів (S6.6):** `detect_missed_anchor_weeks!` перед кожним anchoring перевіряє gap з останнім успішним anchor. Якщо > 8 днів → warning + Prometheus `silkennet_anchor_missed_weeks_total`. Retroactive backfill неможливий (DB state вже змінився), тому поточний state root записується як catch-up.

**Захист від подвійного якорення (S6.7):** При timeout або IOError anchor залишається `pending` (не `failed`), щоб retry через `in_flight` guard знайшов існуючий anchor і відновив його замість створення нового state_root.

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
state_root = SHA256("#{total_growth_points}|#{total_sfc}|#{active_tree_count}|#{chain_hash}|#{anchored_at.iso8601}|#{total_scc_supply}")
```

> 🔴 **[ARCH.97] Дві грошові величини — РІЗНІ, і плутати їх не можна.** Доти тут стояло одне поле `total_scc` = `Wallet.sum(:scc_balance)`, тобто **бали росту** під іменем монети (`scc_balance` — це `alias_attribute` на колонку `balance`; дім величини — [`04_01 §6`](04_01_Data_Models_and_Entities)), тоді як сусідній `total_sfc` того самого дайджесту ніс справжні confirmed-мінти. Одна криптографічна обіцянка змішувала дві одиниці, а верифікація цього не бачила **за побудовою**: `aggregate_payload` — свідомий One-Home для generate І verify, тож обидві сторони рахували однаково й ідеально збігались. Нове поле стоїть **у хвості** payload'а, бо порядок тут = порядок історії розширень (E.53/E.54 теж додавали в хвіст).

де:

| Поле | Джерело | Тип | Приклад |
|------|---------|-----|---------|
| `total_growth_points` | `Wallet.sum(:balance)` | Decimal — **офчейн-леджер балів росту**, НЕ монети. Єдине його криптографічне засвідчення: `Wallet` не має `Auditable`, а `credit!` — голий `increment!` без сліду, тож саме тут воно й потрібне | `"1250000.5"` |
| `total_scc_supply` | `BlockchainTransaction.net_minted_supply(:carbon_coin)` | Decimal — **чинний** monetary supply (Σmints − Σburns), дзеркало on-chain `totalSupply()`. Ім'я каже «supply», а не «minted»: величина не кумулятивна, slash її зменшує | `"48.0"` |
| `total_sfc` | `BlockchainTransaction.where(token_type: :forest_coin, status: :confirmed).sum(:amount)` | Decimal (сума підтверджених SFC мінтингів) — **сира кумулятивна Σ**, свідомо не `net_minted_supply`: бекенд SFC не палить. ⚠️ Але `SilkenForestCoin.sol` має `slash()`/`slashUpTo()`, тож перший DAO-слеш розведе це поле з on-chain `totalSupply()` | `"500.0"` |
| `active_tree_count` | `Tree.active.count` | Integer (кількість активних дерев у екосистемі) | `"4250"` |
| `chain_hash` | `AuditLog.order(created_at: :desc, id: :desc).pick(:chain_hash)` | String або `"GENESIS"` якщо AuditLog порожній | `"a3f8c2..."` |
| `anchored_at` | `Time.current.utc` | UTC DateTime (зберігається в `EthereumAnchor.anchored_at`) | `2026-03-23T03:00:01Z` |

> 🔴 **[ARCH.97] Інваріант ШКАЛИ: кожна decimal-колонка якоря = `numeric(30,6)`, бо шкала її ДЖЕРЕЛА = 6.** `wallets.balance` і `blockchain_transactions.amount` — обидва `numeric(24,6)`. `generate_state_root` хешує **необроблене** значення в `leaf0`, а `verify_state_root` перераховує payload зі **збереженої** колонки — тож колонка, вужча за джерело, робить чесний якір таким, що не сходиться САМ ІЗ СОБОЮ, і «зовнішній аудитор відтворить хеш» стає хибним арифметично, а не концептуально. Виміряно SQL: `SELECT 3.000003::numeric(30,4)` → `3.0000`. ⚠️ **І знай, як цей дефект вижив пів дня ПІСЛЯ власного фіксу:** шкалу звели на двох полях із трьох, а `total_sfc` лишився `(30,4)` — захищений не інваріантом, а **збігом** (mint пише ціле `tokens_to_mint`). Збіг не тримає: SFC приходить у транзакції ще й страховим трактом (`InsurancePayoutWorker` → `payout_amount`, голий `numeric`, рахується як `damage_ratio × insured_value`). Регресійний носій — `spec/models/ethereum_anchor_spec.rb`, і він мусить подавати КОЖНОМУ decimal-полю власне 6-значне значення: на нулі розходження шкал не виразиме за побудовою.

### Покроковий алгоритм (Ruby)

```ruby
def generate_state_root
  # [SNAPSHOT ISOLATION]: REPEATABLE READ гарантує consistent snapshot
  # між паралельними MintCarbonCoinWorker / AuditLogWorker записами
  ActiveRecord::Base.transaction(isolation: :repeatable_read) do
    # 1. [ARCH.97] Офчейн-леджер БАЛІВ росту (НЕ монети). Читається `balance` НАПРЯМУ,
    #    не через alias `scc_balance`: доказовий шлях не має залежати від імені, що
    #    обіцяє монети. `.to_d` нормалізує до BigDecimal (sum() віддає Integer 0 на
    #    порожній множині) — Float дав би e-нотацію в хешованому рядку.
    total_growth_points = Wallet.sum(:balance).to_d

    # 1b. [ARCH.97] ЧИННИЙ monetary supply — One-Home `net_minted_supply`
    #     (Σmints − Σburns, дискримінатор `sourceable_type`), спільний із ChainAudit.
    total_scc_supply = BlockchainTransaction.net_minted_supply(:carbon_coin).to_d

    # 2. [E.53] Сума підтверджених SFC мінтингів (governance token supply)
    #    ⚠️ СВІДОМО сира Σ, тобто КУМУЛЯТИВНА, а не supply: бекенд SFC не палить.
    #    Але `SilkenForestCoin.sol` має `slash()`/`slashUpTo()` — перший DAO-слеш
    #    зробить її розбіжною з `totalSupply()`, і тоді вона мусить перейти на
    #    `net_minted_supply(:forest_coin)`. Семантики двох сусідніх полів РІЗНІ навмисно.
    total_sfc = BlockchainTransaction.where(token_type: :forest_coin, status: :confirmed).sum(:amount).to_d

    # 3. [E.54] Кількість активних дерев (ecosystem coverage metric)
    active_tree_count = Tree.active.count

    # 4. chain_hash останнього AuditLog (криптографічна ланцюгова прив'язка)
    #    order: created_at DESC, id DESC — гарантує детерміновану сортировку при рівному часі
    latest_chain_hash = AuditLog.order(created_at: :desc, id: :desc).pick(:chain_hash) || "GENESIS"

    # 5. Timestamp моменту формування хешу (зберігається в EthereumAnchor.anchored_at)
    timestamp = Time.current.utc

    # 6. Конкатенація через | роздільник (One-Home рядка = EthereumAnchor.aggregate_payload)
    payload = "#{total_growth_points}|#{total_sfc}|#{active_tree_count}|" \
              "#{latest_chain_hash}|#{timestamp.iso8601}|#{total_scc_supply}"

    # 7. SHA-256 хешування → 64-символьний hex рядок (256 bits / 32 bytes)
    state_root = Digest::SHA256.hexdigest(payload)

    # 8. Повернути всі компоненти для збереження в EthereumAnchor (BLOCKER-6)
    { state_root: state_root, total_growth_points: total_growth_points,
      total_scc_supply: total_scc_supply, total_sfc: total_sfc,
      active_tree_count: active_tree_count, chain_hash: latest_chain_hash, anchored_at: timestamp }
  end
end
```

### Приклад payload та результату

```
Payload:  "1250000.5|500.0|4250|a3f8c2d1e4b7f9a0c2e5d8b1f4a7e0d3c6b9e2a5f8c1d4e7b0a3f6c9d2e5|2026-03-23T03:00:01Z"
Result:   "7f4a9b2c1e8d3f6a0b5c8e2d7a4f1b9e3c6d0a7f4b1e8d5c2a9f6b3e0d7a4c1"  (64 hex chars = 32 bytes)
```

### Що включено / що відсутнє

| Включено ✅ | Відсутнє ⚠️ |
|------------|------------|
| **Бали росту всіх гаманців** (офчейн-леджер, НЕ монети) [ARCH.97] — leaf0 | Lorenz Z-value статистика (агрегатна) |
| **Чинний SCC supply** (Σmints − Σburns, дзеркало `totalSupply()`) [ARCH.97] — leaf0 | |
| Кумулятивні SFC-мінтинги [E.53] — leaf0 (⚠️ не supply: burn'и не віднімаються) | |
| Кількість активних дерев [E.54] — leaf0 | |
| Останній AuditLog chain_hash — leaf0 | |
| Timestamp виконання (збережений в БД) — leaf0 | |
| **Per-record телеметрія-листя вікна** (cluster-субкорені; leaf = `Mrv::TelemetryLeaf`) [ARCH.12 Фаза 1а] | |
| `REPEATABLE READ` snapshot isolation | |

> **Примітка [ARCH.12 Фаза 1а, 2026-07-19]:** Агрегат-формула вище тепер = **`leaf0`** Merkle-дерева, а `state_root = MerkleTree.root([leaf0] + cluster-субкорені)` (`root_version: 1`; One-Home рядка-формули = `EthereumAnchor.aggregate_payload` — юзають і generate, і verify). Legacy-якорі (`root_version: 0`) — flat commitment. Незалежна верифікація: `EthereumAnchor#verify_state_root` version-route — v0 відтворює хеш зі збережених колонок; v1 звіряє leaf0 з тих самих колонок І перераховує корінь зі збережених `subtree_roots` (самодостатньо O(#кластерів), переживає ретеншн). Механіка вікна/листя — §Merkle нижче.
>
> 🔴 **ПОПРАВКА [ARCH.97]: тут стояло «верифікуються старою формулою НАЗАВЖДИ», і це звужено.** `root_version` версіонує **структуру** commitment'а (flat ⊥ Merkle), а не заморожує СКЛАД полів: обидві гілки читають один `aggregate_payload`, тож зміна складу міняє обидві. Формулу вже розширювали на місці — E.53/E.54 (3→5 полів) і [ARCH.97] (5→6), — і це легально рівно **до першого підтвердженого якоря**: продовий письменник один і завжди ставить `root_version: 1`, рядків у БД нуль, контракт не задеплоєно ([`SEC.1`](00_07_Action_Plan_Tracker)), тож обіцянка «назавжди» квантифікувалась по ПОРОЖНІЙ множині. **Після першого confirmed-якоря склад полів заморожується, і будь-яке розширення вимагає нової версії кореня** — разом із двома хардкодженими фільтрами `root_version: 1` (window-chaining в `StateAnchorService`, `covering_anchors` у `Mrv::LineageReportService`), які інакше зроблять v2-якорі невидимими для lineage-бандлів.

---

## 4. Відправка L1 Транзакції

**Файл:** `app/services/ethereum/state_anchor_service.rb`  
**Метод:** `Ethereum::StateAnchorService#anchor_to_l1!`

### Повний флоу

```
generate_state_root()
       │
       ▼
generate_state_root()  →  { state_root, total_growth_points, total_scc_supply, total_sfc, active_tree_count, chain_hash, anchored_at }
       │
       ▼
EthereumAnchor.create!(state_root:, total_growth_points:, total_scc_supply:, total_sfc:, active_tree_count:, chain_hash:, anchored_at:, status: :pending)
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
EthereumAnchorConfirmationWorker.perform_in(30.seconds, anchor.id)   # [ARCH.66] довершити lifecycle
       │
       ▼
Rails.logger.info "⚓ [Ethereum L1] State Root anchored: #{state_root} → TX: #{tx_hash}"
       │
       ▼
return anchor   # EthereumAnchor (:sent → поллер доведе до :confirmed/:failed/:manual_review)
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
  },
  {
    "inputs": [
      { "internalType": "uint256", "name": "index", "type": "uint256" }
    ],
    "name": "getRootAtIndex",
    "outputs": [
      { "internalType": "bytes32", "name": "root", "type": "bytes32" },
      { "internalType": "uint256", "name": "timestamp", "type": "uint256" }
    ],
    "stateMutability": "view",
    "type": "function"
  }
]
```

**Тип транзакції:** EIP-1559 (`legacy: false`)  
**Метод контракту:** `storeStateRoot(bytes32 root)` — nonpayable  
**View метод:** `getRootAtIndex(uint256 index)` — повертає (root, timestamp) для ISO 14064 / Verra VCS compliance  
**Gas:** `DEFAULT_GAS_LIMIT = 100_000` (safety cap), `storeStateRoot` потребує ~50,000 gas (2 SSTORE + event)
**Мінімальний інтервал:** `MIN_ANCHOR_INTERVAL = 6 days` — захист від спаму при компрометованому oracle
**block.timestamp:** Може відрізнятись від реального часу до ~12 секунд (Ethereum PoS). Для compliance-звітності використовуйте `EthereumAnchor.anchored_at`.

---

## 5. Обробка Помилок

```ruby
rescue Net::OpenTimeout, Net::ReadTimeout => e
  # [S6.7] НЕ маркуємо :failed — TX може бути в мемпулі; лишаємо :pending, щоб in_flight
  # guard відновив цей anchor на retry (а не згенерував новий state_root = double-anchor).
  anchor&.update!(error_message: "Timeout (TX may be in-flight): #{e.message.truncate(450)}") if anchor&.persisted?
  raise "Ethereum L1 Timeout: #{e.message}"

rescue IOError => e
  anchor&.update!(error_message: "Connection error (TX may be in-flight): #{e.message.truncate(450)}") if anchor&.persisted?
  raise "Ethereum L1 Connection Error: #{e.message}"
```

| Помилка | Джерело | Дія |
|---------|---------|-----|
| Insufficient balance | `balance < MIN_ANCHOR_BALANCE_WEI` | `anchor.update!(status: :failed)` + raise → retry |
| `Net::OpenTimeout` | RPC endpoint недоступний | **keep `:pending`** (S6.7 — TX може бути в мемпулі) + raise → retry відновить |
| `Net::ReadTimeout` | Відповідь від Alchemy перевищила таймаут | **keep `:pending`** (S6.7) + raise → retry відновить |
| `IOError` | TCP з'єднання розірвано | **keep `:pending`** (S6.7) + raise → retry відновить |
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

## 5.1 Підтвердження та Reconcile [ARCH.66]

**Проблема (до ARCH.66):** `anchor_to_l1!` ставив `:sent` і зупинявся — жоден воркер не опитував receipt, тож anchor **ніколи не досягав `:confirmed`**. Scopes `successful`/`latest_confirmed` вічно порожні; `block_number`/`gas_used` не заповнювались; double-anchor guard (`in_flight` = pending/sent AND `created_at > 1.week.ago`) деградував до 1-тижневого таймера — завислий `:sent` після 7 днів випадав із guard, і якщо старий tx колись приземлявся → ризик подвійного state_root.

**Рішення** — поллер + backstop-cron (дзеркало `CeloConfirmationWorker`/ARCH.55, з L1-специфікою):

### `EthereumAnchorConfirmationWorker(anchor_id)`

Enqueue'иться `perform_in(30.seconds, anchor.id)` одразу після `update!(status: :sent)`. Опитує `eth_get_transaction_receipt` → `Web3::EvmReceiptClassifier`:

| Класифікація | Дія |
|--------------|-----|
| `:confirmed` | **reorg-depth gate** (нижче) → `anchor.confirm!(block_number, gas_used)` |
| `:reverted` | `anchor.mark_failed!` + `silkennet_ethereum_anchor_reverted_total` |
| `:pending` | `raise` → Sidekiq retry (ще в мемпулі) |

- **Черга/retry:** `web3_low`, фіксований `sidekiq_retry_in { 180 }` × `retry: 60` ≈ 3-год горизонт (НЕ exponential — 100-Gwei cap може стопорити включення на години; money-path 15-20хв дав би хибну ескалацію).
- **Reorg-depth gate:** «фінальна печатка» не confirm'иться на першому receipt (на відміну від money-path). Чекає `latest_block − receipt.blockNumber >= ETHEREUM_ANCHOR_MIN_CONFIRMATIONS` (default **64** ≈ 2 епохи post-Merge finality; ENV-tunable, `0`=off для dev/testnet). Недостатньо глибоко → на нормальному поллі `raise` (чекати), на фінальному re-check → `escalate` (retries вичерпано, людська звірка) — **gate діє І на final**, «печатка» не осідає на sub-finality блоці (slow-inclusion міг замайнити tx в останні хвилини на глибині < 64).
- **Exhausted** (~3год поллінгу вичерпано) → **фінальний receipt re-check** (дзеркало `MintingRollbackService`: tx міг замайнитись в останній ретрай — сліпий escalate записав би підтверджений-on-chain anchor у `:manual_review` назавжди): `:confirmed`+finalized→`confirm!`, `:reverted`→`mark_failed!`, а `:pending`/shallow/anomalous-no-block→`escalate_to_review!` (`:manual_review`, людська звірка на etherscan). RPC-глюк під час re-check → `rescue`→escalate (не `:sent`-limbo). **НІКОЛИ blind re-broadcast** (поллер лише читає receipt; розштовхування застряглого = операторський same-nonce gas-bump — nonce персиститься перед broadcast, ↓ §nonce-persist). `:manual_review` виходить з `in_flight` → наступний тижневий seal не блокується.

### `StuckSentAnchorSweeperWorker` (cron `:40`, hourly)

Backstop, коли САМ поллер загинув до вичерпання ретраїв (container OOM під час поллінгу): anchor лишається `:sent`, retries не вичерпані → жоден escalate не спрацює. Cron re-arm'ить `EthereumAnchorConfirmationWorker` для будь-якого anchor у scope `EthereumAnchor.stuck_sent` (`:sent` AND `updated_at < STUCK_SENT_THRESHOLD` = 6год; ключ `updated_at`, бо `sent_at`-колонки немає, а `pending→sent` бампає `updated_at`). **Read-only re-poll, ніколи re-send.** reload-guard перед re-arm (живий поллер міг довершити).

### Модель — plain enum, гардовані переходи

`EthereumAnchor` = Rails `enum` (не AASM), тож idempotency тримає `with_lock` + status-гард — перехід рівно-раз проти конкурентного reconcile-re-arm / weekly-resume. `confirm!`/`mark_failed!` переходять з `:sent` **або** `:manual_review` (останнє = гардований операторський вихід із manual_review після etherscan-звірки — оператор робить `confirm!`/`mark_failed!` без raw `update_column` повз валідації/аудит); `escalate!` лише з `:sent` (не ре-ескалює вже-ескальоване). Термінальні `:confirmed`/`:failed` не відкочуються (глибокий reorg вже-`:confirmed` = P0-подія для людини). Новий статус `manual_review` (value 4).

### `detect_missed_anchor_weeks!` звужено на `[:confirmed]`

З реальним поллером `:sent` transient (розв'язується за години), тож `detect_missed` рахує успіхом лише `:confirmed` — інакше завислий `:sent` після наступного тижневого broadcast маскував би реально-непідтверджений gap назавжди.

### nonce-persist проти F2a double-send [companion]

`anchor_to_l1!` персистить `nonce` broadcast'у в колонку `ethereum_anchors.nonce` **ПЕРЕД** `client.transact` (новий anchor → `client.get_nonce` pending-tag + persist; resume `:pending` → колонка вже заповнена, `get_nonce` НЕ кличеться) і передає його явним `nonce:` у `transact`. **F2a, яку закриває:** crash між broadcast і `update!(status: :sent)` лишає anchor `:pending` без `tx_hash`, а завислий tx — у мемпулі під тим nonce. Без персисту resume-гілка (double-anchor guard, `existing_anchor&.status_pending?`) кликала б авто-nonce: `eth_get_transaction_count(pending)` уже врахував би завислий tx → `nonce+1` → **другий незалежний on-chain запис** (обидва майнились би; контракт revert'нув би дубль через `rootTimestamps[root]==0` + 6-day `MIN_ANCHOR_INTERVAL`, але спалений gas + брехливий `:failed`). Persisted nonce → resume ре-броадкастить на ТОМУ Ж слоті → node відповідає `replace` / `already known` / `nonce too low` = **щонайбільше один on-chain tx на anchor**, не N+1. **Classify-and-escalate half** (без неї persist = напівфікс): ці node-rejection'и приходять як `Eth::Client::RpcError` (< `IOError`), тож service ловить їх у `rescue Eth::Client::RpcError` **ПЕРЕД** generic `rescue IOError`; на resume (`:pending` + персистований nonce) → `EthereumAnchor#escalate_pending_ambiguous!` → `:manual_review` (перший broadcast досяг мережі, `tx_hash` втрачено у crash-вікні → людська звірка за `address`+`nonce` на etherscan), а НЕ blind-retry чи `:pending`-orphan (поллер enqueue'иться лише після `:sent` → `tx_hash` ніколи не писався б, `detect_missed` рахував би тиждень як gap). Не-ambiguous `RpcError` (insufficient-funds/revert на fresh send) → `raise`. Дзеркало money-path (`transact_error_pre_broadcast?` / celo `AMBIGUOUS_PATTERNS`); `:manual_review` без `tx_hash` легітимний (presence-валідація лише для sent/confirmed). Поллер (↑) уже конвертував limbo у benign transient — nonce-persist прибирає й спалений-gas-хвіст. **Ніколи авто-gas-bump на resume**: «розстопорення» застряглого tx = операторський ручний same-nonce gas-bump (console). Дзеркало money-path, де intent-marker несе ту саму роль.

### Observability

- `silkennet_ethereum_anchor_stuck_sent_depth` (gauge) — рахує scope `stuck_sent` (НЕ весь `:sent` — здоровий anchor у вікні підтвердження давав би хибний щотижневий page). Семплить `Treasury::MonitorService` (15-хв, freshness проти restart-обнулення in-process gauge). Alert `sn-alert-ethereum-anchor-stuck-sent` (P1, `min_over_time[2h] > 0`).
- `silkennet_ethereum_anchor_manual_review_depth` (gauge) — anchor, ескальований у `:manual_review` (термінальний, поза sweeper/detect_missed → без gauge невидимий — лише 8-денний missed-weeks-лаг ловив би). Семплить `Treasury::MonitorService`. Alert `sn-alert-ethereum-anchor-manual-review` (P1).
- `silkennet_ethereum_anchor_reverted_total` (counter) — детермінований contract-revert = аномалія. Alert `sn-alert-ethereum-anchor-reverted` (P2-info).

> **Активація gated на деплой контракту** (SEC.1): `ETHEREUM_ANCHOR_CONTRACT`/`_PRIVATE_KEY` не задані → anchor-path структурно неактивний, тож `:sent` не досягається і обидва воркери natural-inert. Код pre-deploy готовий. F2a double-send закрито nonce-persist (↑ окремий під-розділ).

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

> Конвенції написання / coverage-гейт / тріаж прогалин — [`04_06`](04_06_Testing_Guide_and_Coverage) (Testing Guide). Нижче — per-subsystem інвентар тестів L1-якоря (One-Home: інвентар біля підсистеми).

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
| describe `root_version: 1 (Merkle) [ARCH.12]` | tier2-побудова (leaf0-агрегат + cluster-субкорені), ланцюжіння вікон (`window_from` = попередній confirmed v1), GRACE-межа, персист `subtree_roots`/`leaf_count` |

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
| validations (presence, uniqueness, format) | state_root, tx_hash, total_growth_points, total_scc_supply, chain_hash |
| `verify_state_root` | Відтворення хешу з компонентів (незалежна верифікація) |
| `etherscan_url` | URL генерація для confirmed TX |
| scopes: `recent`, `successful`, `latest_confirmed`, `stuck_sent` [ARCH.66] | AR scopes |
| enum status | pending/sent/confirmed/failed/**manual_review** [ARCH.66] |
| `confirm!` / `mark_failed!` / `escalate_to_review!` [ARCH.66] | guarded lifecycle transitions (`with_lock`, idempotent from `:sent`) |
| describe `verify_state_root` version-route [ARCH.12] | v0 = flat-формула назавжди; v1 = leaf0-звірка + корінь зі збережених `subtree_roots` (самодостатньо, tamper → false) |

> [ARCH.12] Merkle-примітив має власний дім-спек `spec/lib/merkle_tree_spec.rb` (golden-vectors + mutation-verified, pure — без Rails); mrv-споживачі (`spec/services/mrv/*`) — інвентар біля своєї підсистеми ([`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline) + карти [`04_02`](04_02_Business_Logic_and_Services)).

---

## 8. Місце в SilkenNet Pipeline

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
║    SCC-supply може змінитись (slash палить on-chain)                ║
║                                                                      ║
║  Понеділок 03:00 UTC ← ТОЧКА ФІНАЛІЗАЦІЇ                            ║
║    EthereumAnchorWorker (web3_low, cron: '0 3 * * 1', retry: 5)     ║
║       │                                                              ║
║       ▼                                                              ║
║    generate_state_root():                                            ║
║      [REPEATABLE READ transaction]                                   ║
║      total_growth_points = Wallet.sum(:balance)      [PostgreSQL]   ║
║      total_scc_supply    = net_minted_supply(:scc)   [PostgreSQL]   ║
║      total_sfc           = BlockchainTx(SFC).sum     [PostgreSQL]   ║
║      active_tree_count   = Tree.where(...).count     [PostgreSQL]   ║
║      chain_hash          = AuditLog.last.chain_hash  [PostgreSQL]   ║
║      anchored_at         = Time.current.utc          [Runtime]      ║
║      state_root          = SHA256(scc|sfc|trees|hash|ts) [CPU]      ║
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
| 05_03 Tokenomics | `ClusterHealthCheckWorker` + `BurnCarbonTokensWorker` | 02:00 UTC | Фінальний **SCC-supply** після slashing (burn зменшує `net_minted_supply`) |

> 🔴 **ПОПРАВКА [ARCH.97]: тут стояв «фінальний `Wallet.scc_balance` після slashing», і залежність була ВИГАДАНА.** Slashing колонки `wallets.balance` не торкається взагалі — виміряно: письменників у дереві рівно два (`credit!` → `increment!` і ESG-`decrement!`, останній без живого викликача, [`ARCH.95`](00_07_Action_Plan_Tracker)), тож балова величина монотонно росте й від 02:00-воркерів не залежить. Залежність стала СПРАВЖНЬОЮ лише тепер, коли якір несе `total_scc_supply`: burn зменшує саме його. **Урок ширший за рядок: увесь цей документ міркував про якорену величину як про монетний supply — і в такому прочитанні був НЕСУПЕРЕЧЛИВИЙ, тож перечитування дрейфу не ловило, бо шукало конфлікт між реченнями, а конфлікт був між узгодженим документом і реальністю.**

### Низхідні (Blocks)

| Що блокує | Причина |
|-----------|---------|
| Довіра інституційних інвесторів | Без L1 anchor система = Web2 БД без криптографічних гарантій |
| Регуляторний D-MRV compliance | ISO 14064 / Verra VCS вимагають незмінного audit trail |
| Публічна верифікація SCC-атестацій | SCC токени без L1 finality не мають незалежної верифікації |

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
bin/rails runner "ENV.fetch('ALCHEMY_ETHEREUM_RPC_URL'); ENV.fetch('ETHEREUM_ANCHOR_PRIVATE_KEY'); ENV.fetch('ETHEREUM_ANCHOR_CONTRACT'); puts 'OK'"

# 2. Перевірити баланс oracle-гаманця (> 0.01 ETH):
# Через Alchemy Dashboard або etherscan.io

# 3. Запустити тести:
bin/rspec spec/services/ethereum/ spec/workers/ethereum_anchor_worker_spec.rb spec/models/ethereum_anchor_spec.rb
```

### Operational Security

- **Admin = Timelock [SEC.1]:** Для production `DEFAULT_ADMIN_ROLE` призначається `SilkenTimelock` (48h), а не Gnosis Safe / EOA — `StateRootAnchor` не має `pause()`, тож видача `ANCHOR_ROLE` (oracle-rotation) = management-влада → governance-gated (правило «admin=Timelock, окрім pause»; деталі — [`05_03`](05_03_Tokenomics_SCC_and_SFC)). Recovery: Safe = PROPOSER Timelock'а (планова rotation за 48h); 6-денний `MIN_ANCHOR_INTERVAL` + off-chain root-верифікація роблять повільніше відкликання некритичним
- **Admin Protection:** Контракт блокує видалення останнього `DEFAULT_ADMIN_ROLE` через `_adminCount` лічильник — `renounceRole()` та `revokeRole()` ревертять якщо залишився один адмін
- **Anti-Spam:** `MIN_ANCHOR_INTERVAL = 6 days` запобігає спаму фейковими state roots компрометованим oracle
- **Roles & Events:** запис авторизується роллю `ANCHOR_ROLE` (oracle-гаманець); кожен запис емітує `StateRootStored(bytes32 indexed root, uint256 timestamp, uint256 anchorIndex)` — джерело для subgraph-індексації
- **Timestamp:** `block.timestamp` може відрізнятись від реального часу до ~12 секунд (Ethereum PoS). Для compliance-звітності крос-референс з `EthereumAnchor.anchored_at` в PostgreSQL

---

## 🔬 Перспективи Розвитку L1 Якоріння

> ⛔ **ТВЕРДА МЕЖА СКЛАДУ ЯКОРЯ — сюди не кладуть похідних від популярності, смаку чи будь-якого голосування людей** (⚖️ founder, 2026-08-15). Пропозиція, що це закриває: класти в тижневий якір топ-N найцитованіших вузлів наративного шару, тобто **вихід конкурсу популярності**. L1-якір є найдорожчим артефактом чесності платформи: він криптографічно стверджує, що дерева свідчили саме так. Домішавши до нього число, чиє «звідки» — клікова перевага, ти робиш ОДИН підпис над двома твердженнями різної природи, і зовнішній аудитор більше не може розрізнити, яке з них перевіряє. Межа тримається **за будь-якого розміру натовпу** й не залежить від того, чи існує шар, що таку метрику виробляв. Критерій допуску поля: величина мусить бути ВИМІРЯНА пристроєм або дедукована з виміряного ([`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap) — «правдиво · невідбирано · відтворювано»).


### Merkle state_root [ARCH.12 — Фаза 1а SHIPPED 2026-07-19]

Перший inclusion-proof-споживач визначено founder-присудом 2026-07-19 (**ISO-звіт/MRV.1** — офлайн-verifiable lineage-bundle) → Фаза 1а реалізована. `state_root` = Merkle-корінь (`root_version: 1`): `tier2 = [leaf0-агрегат] + cluster-субкорені`, де `leaf0` = SHA-256 старої агрегат-формули (§3 — supply-finality збережена), а листя = per-record телеметрія (leaf-формула One-Home [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline), код-дім `Mrv::TelemetryLeaf`; **НЕ** `TelemetryLog.chain_hash` — такої колонки немає, агрегатний AuditLog `chain_hash` лишається всередині leaf0).

```
                state_root = MerkleTree.root(tier2)
               /                |                    \
        leaf0 = aggregate   subroot(cluster 7)   subroot(NULL-sentinel)
        (SHA256 §3-формули)  /            \             |
                       leaf(logA)    leaf(logB)     leaf(logC)
```

**Механіка вікна (персистована, GRACE-захищена):**
- Вікно листя = `(window_from .. window_to]`; `window_from` = `window_to` попереднього confirmed v1-якоря (ланцюжиться без дір і перекриттів; перший v1-якір → from-genesis), `window_to` = `anchored_at − WINDOW_GRACE` (5 хв). **GRACE закриває клас «рядок загублено назавжди»**: телеметрія, що комітиться під час repeatable_read-снапшота, має `created_at` нижче за верхню межу — без лагу вона випала б і з цього вікна, і з усіх наступних. Обидві межі **персистуються** (`window_from`/`window_to`) — історичні вікна не залежать від значення константи.
- Порядок детермінований: кластери за `cluster_id` asc (NULL-cluster = sentinel-група останньою), листя всередині кластера — `(created_at, id)` asc.
- **Overlap-правило:** `manual_review`-якір, підтверджений оператором пізніше, дає легальні перекриті вікна з наступним тижневим — bundle обирає «найранішій confirmed-якір, що покриває лист».
- `[transitional]` стеля: один процес сканує все тижневе вікно в одному снапшоті (~10⁶ листя межа; довга repeatable_read-транзакція ще й тримає vacuum-горизонт БД на час скану) — ієрархія тут дає форму, масштаб ще ні; upgrade-path = per-cluster субкорінь-воркери поверх збережених `subtree_roots` + винесення телеметрія-скану за межі RR-транзакції (листя обмежені персистованими межами, агрегат-снапшоту не потребують) → [`00_07`](00_07_Action_Plan_Tracker) ARCH.52. Тижневий скан фільтрує вікно голою `created_at`-межею (свідома асиметрія з tuple-`(created_at, id)` у `Mrv::LineageWindow` — глобальне вікно без per-owner курсора tie-break не потребує, а гола межа зберігає partition-pruning).
- **Ops-застереження ре-кластеризації:** переїзд дерева між кластерами робить tier1-пруфи всього старого кластера `unprovable_regrouped` для ВСІХ минулих якорів (збережений субкорінь без leaf-list) — **генеруй/архівуй lineage-bundle ПЕРЕД ре-кластеризацією**.

**Верифікація (два рівні, `verify_state_root` version-route):** (1) **агрегат-фінальність** — самодостатня назавжди: leaf0 з 5 збережених колонок + корінь зі збереженого `subtree_roots` (O(#кластерів), переживає ретеншн; `subtree_roots` також фіксує групування-як-було — `cluster_id` мутабельний); (2) **per-leaf inclusion-proof** — поки живуть телеметрія-партиції, з БД; довгостроково — через самодостатній lineage-bundle (несе листя+пруфи). Ретеншн-дроп партицій сьогодні НЕ реалізований (`PartitionMaintenanceWorker` лише створює) — політика майбутня, bundle = довгостроковий носій верифіковності.

**Контракт НЕ змінився:** `storeStateRoot(bytes32)` приймає Merkle-корінь так само, як flat-хеш; legacy-якорі (`root_version: 0`) верифікуються старою формулою назавжди.

**Паралель E.60, не вкладеність:** цей Eth-L1 weekly state-root і Polygon per-batch `archive_root` ([`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline)) — два незалежні якорі, що ділять ОДИН `MerkleTree` primitive (`lib/merkle_tree.rb`: sha256, RFC-6962 domain-sep 0x00/0x01, promotion непарного вузла — НЕ дублювання, анти-CVE-2012-2459; hash-of-hex; двоярусність = композиція verify×2 у споживачах); Polygon-нога = **✅ Фаза 1б SHIPPED 2026-07-19** (mint-anchored батч → `mint(bytes32)`; механіка — [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline), стан — [`00_07`](00_07_Action_Plan_Tracker) E.60). keccak / OZ-`MerkleProof` — upgrade-path лише за on-chain-verify споживача (YAGNI).

**L2 device-voice (чесна межа):** кластерний ярус НЕ дає per-tree піддерева (листя дерев перемішані всередині кластера) — майбутній L2-рунг ([`05_05 §3.3`](05_05_Slashing_and_Risk_Policy)) підписуватиме **власний per-tree корінь** (mint-window-подібний, MRV.1), не кластерний субкорінь.

**Стан/фазування:** [`00_07`](00_07_Action_Plan_Tracker) ARCH.12 (обидві фази SHIPPED 2026-07-19; residuals-⚖️ — дім E.60).

### Anchor-транспорт: baseline direct-L1; AVS відхилено; довготривала тривкість (far-horizon)

**Baseline (чинний, лишається).** State root пишеться напряму в Ethereum L1 — найвища децентралізація/immutability + золотий стандарт для аудиторів. Вартість у 2026 неістотна: `storeStateRoot` ~50k gas при gas ~0.05–0.5 gwei → **порядок кількох доларів на рік** (52 tx), а не «$5–15/tx» старої оцінки (та стояла на 40–100 gwei — режимі, якого більше немає). 100-Gwei cap = worst-case стеля від рідкого спайку (він лише відкладе включення — weekly+retry це терпить), не робоча ціна.

**EigenLayer AVS — відхилено (won't-do, 2026-07-19).** Розглядався як дешевша L1-альтернатива для weekly-запису; присуд — не робити, за трьома незалежними осями:
- **Economics зникла.** Стара теза «дешевший AVS» стояла на 40–100 gwei; у 2026 direct-L1 = копійки/рік → оптимізувати нічого.
- **Attestation theater над self-asserted хешем.** `state_root` = SHA-256 приватної Postgres-БД. AVS-оператори даних **не бачать** → їхній слешинг засвідчує «ми запостили байти», а не «байти = правда про ліс». AVS додав би лише *бренд* «secured by restaked ETH» поверх недоведеного твердження — робить платформу такою, що *виглядає* надійнішою, ніж є (пряма суперечність з чесністю про залізо). Готового anchoring-AVS до споживання немає; будувати власний = operator-set + slashing-контракти + аудит + вічний ops-податок.
- **Аудитори/реєстри AVS не визнають.** Verra / Gold Standard / ISO 14064 не мандатують ланцюг узагалі; Ethereum L1 = найзрозуміліший наратив, AVS = екзотична довірча модель, яку довелося б пояснювати.

**Ортогональна вісь структура/транспорт.** ARCH.12 = *структура* кореня (flat→Merkle) ✅ done; *транспорт* (куди писати) — baseline direct-L1, AVS-гілка закрита. Дві незалежні осі.

**Far-horizon тривкість (окремі треки, активація pre-mainnet / до 20-річних гарантій перед аудитором).** Дві РІЗНІ загрози потребують різних інструментів — жоден не будується передчасно (TRL-3, контракт не задеплоєно, нуль live-коштів):
- **Незалежний-домен другий якір (→ [`00_07`](00_07_Action_Plan_Tracker) ARCH.72):** захист від смерті ОДНОГО ланцюга на 20-річному горизонті. Якщо ціль — реальна chain-risk диверсифікація, правильний другий транспорт = **OpenTimestamps → Bitcoin** (безкоштовна calendar-агрегація хеша в незалежний PoW-домен; той самий Merkle-примітив), а **не** Polygon-дубль: Polygon checkpoint-иться в Ethereum → shared security (нуль диверсифікації) + вічний 2-й confirmation-lifecycle з іншою finality. «Два корені» несуть, лише коли другий світ незалежний.
- **Renewal по осі часу (→ [`00_07`](00_07_Action_Plan_Tracker) ARCH.73):** захист від СТАРІННЯ хеш-алгоритму — те, чого другий ланцюг НЕ дає (обидва на SHA-256). RFC 4998 ERS: пере-timestamp старого доказу під сильнішим хешем **перш ніж** SHA-256 ослабне (hash-agility; горизонт NIST PQC-переходу). + qualified RFC-3161 timestamp (eIDAS QTSP) = юридична презумпція в суді ЄС, якої blockchain не несе. Це напрям, що реально закриває 20-річну прогалину, а не дублює транспорт.
