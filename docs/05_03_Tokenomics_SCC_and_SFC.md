# 05_03: Токеноміка — SCC & SFC (Смарт-контракти на Polygon)

## 🎯 Мета

Зафіксувати реальний стан («як є») смарт-контрактів токеноміки Gaia 2.0 — `SilkenCarbonCoin` (SCC) та `SilkenForestCoin` (SFC). Документ описує стандарти токенів, ієрархію ролей, ключові функції, механізм Dynamic Tax, зв'язок з бекендом та повний перелік знайдених блокерів.

---

## ✅ Статус

- **SCC контракт:** ✅ Production-ready (MAX_SUPPLY=1B, MINTER/SLASHER split, ReentrancyGuard, NatSpec, PremiumPaid event)
- **SFC контракт:** ✅ Production-ready (MAX_SUPPLY=100M, SLASHER_ROLE + slash(), ReentrancyGuard, NatSpec, unified pause)
- **Backend інтеграція:** ✅ `BlockchainMintingService` + `BlockchainBurningService`
- **The Graph subgraph:** ✅ `TokenSlashed` event name виправлено, `treeDidHash` додано
- **Синхронізація:** 2026-04-15
- **Mainnet deployment:** ✅ Всі B-01..B-15 блокери закриті в PR #254
- **Пов'язані модулі:**
  - Мультичейн → [`05_01_Multichain_Architecture`](05_01_Multichain_Architecture)
  - Proof of Growth → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)

---

## 🏗️ Dual Token System (Архітектура)

| Параметр | SCC — Silken Carbon Coin | SFC — Silken Forest Coin |
|---|---|---|
| **Тип** | Utility Token | Governance Token |
| **Ticker** | SCC | SFC |
| **Стандарти** | ERC-20 + AccessControl + Pausable + ERC20Permit | ERC-20 + AccessControl + Pausable + ERC20Permit + ERC20Votes |
| **Мережа** | Polygon (Amoy testnet → Mainnet) | Polygon (Amoy testnet → Mainnet) |
| **Файл** | `contracts/SilkenCarbonCoin.sol` | `contracts/SilkenForestCoin.sol` |
| **ENV адреса** | `CARBON_COIN_CONTRACT_ADDRESS` | `FOREST_COIN_CONTRACT_ADDRESS` |
| **Pragma** | `^0.8.20` | `^0.8.20` |
| **Максимальна емісія** | ✅ `MAX_SUPPLY = 1_000_000_000 SCC` | ✅ `MAX_SUPPLY = 100_000_000 SFC` |
| **Slash / Burn** | ✅ `slash()` через `SLASHER_ROLE` | ✅ `slash()` через `SLASHER_ROLE` (B-06 виправлено) |
| **Gasless approvals** | ✅ EIP-2612 / EIP-712 (PR #253) | ✅ EIP-2612 / EIP-712 |
| **DAO голосування** | ❌ | ✅ `ERC20Votes` |
| **Subgraph індексація** | ✅ `CarbonMinted`, ✅ `TokenSlashed` | ❌ Немає |

---

## 📦 OpenZeppelin — Успадковані Стандарти

### SilkenCarbonCoin (SCC)

```solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SilkenCarbonCoin is ERC20, AccessControl, Pausable, ReentrancyGuard, ERC20Permit { ... }
```

| Базовий контракт | Призначення |
|---|---|
| `ERC20` | Стандартний fungible token: `transfer`, `approve`, `transferFrom`, `balanceOf`, `totalSupply` |
| `AccessControl` | Ієрархія ролей через `bytes32` hash — `grantRole`, `revokeRole`, `hasRole` |
| `Pausable` | Екстрене заморожування всіх трансферів (override `_update`) |
| `ERC20Permit` | **[PR #253]** Gasless approvals через EIP-2612 / EIP-712 підписи (`permit()`). Дозволяє DEX/P2P marketplace інтеграцію без газу для власників SCC. `nonces(address)` override для MRO сумісності з Nonces. |
| `Pausable` | Аварійна зупинка всіх переміщень токенів через `pause()` / `unpause()` |

### SilkenForestCoin (SFC)

```solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract SilkenForestCoin is ERC20, AccessControl, Pausable, ERC20Permit, ERC20Votes { ... }
```

| Базовий контракт | Призначення |
|---|---|
| `ERC20` | Стандартний fungible token |
| `AccessControl` | Ієрархія ролей |
| `Pausable` | Аварійна зупинка |
| `ERC20Permit` | Gasless approvals через EIP-2612 / EIP-712 підписи (`permit()`) |
| `ERC20Votes` | Governance voting power для DAO (checkpoint-based, `delegate()`, snapshot) |

---

## 🔑 Ієрархія Ролей (AccessControl)

### SCC — Ролі

| Роль | Константа | Призначається в конструкторі | Можливості |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | `0x00` (OpenZeppelin default) | `admin` (параметр конструктора) | Видача / відкликання будь-яких ролей; `pause()`, `unpause()` |
| `MINTER_ROLE` | `keccak256("MINTER_ROLE")` | `oracle` (параметр конструктора) | `mint()`, `batchMint()` |
| `SLASHER_ROLE` | `keccak256("SLASHER_ROLE")` | `oracle` (параметр конструктора) | `slash()` |

```solidity
constructor(address admin, address oracle) ERC20("Silken Carbon Coin", "SCC") {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(MINTER_ROLE, oracle);
    _grantRole(SLASHER_ROLE, oracle);   // ⚠️ Та сама адреса — BLOCKER B-02
}
```

> ⚠️ **Архітектурна проблема:** Один `oracle` акаунт отримує і `MINTER_ROLE`, і `SLASHER_ROLE`. Компрометація одного ключа `ORACLE_PRIVATE_KEY` дозволяє одночасно карбувати та спалювати токени — повний контроль над економікою.

### SFC — Ролі

| Роль | Константа | Призначається в конструкторі | Можливості |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | `0x00` | `admin` | Видача / відкликання ролей; `pause()`, `unpause()` |
| `MINTER_ROLE` | `keccak256("MINTER_ROLE")` | `oracle` | `mint()`, `batchMint()` |

```solidity
constructor(address admin, address oracle)
    ERC20("Silken Forest Coin", "SFC")
    ERC20Permit("Silken Forest Coin")
{
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(MINTER_ROLE, oracle);
}
```

> **Архітектурне рішення:** SFC свідомо не має `SLASHER_ROLE` — governance токени не спалюються при порушенні NaaS контракту. Потенційний наслідок: "нечесні" учасники зберігають DAO voting power після slashing. Потрібне явне архітектурне рішення — BLOCKER B-06.

### Матриця Дозволів

| Дія | SCC MINTER | SCC SLASHER | SCC ADMIN | SFC MINTER | SFC ADMIN |
|---|---|---|---|---|---|
| `mint()` SCC | ✅ | ❌ | ❌ | — | — |
| `batchMint()` SCC | ✅ | ❌ | ❌ | — | — |
| `slash()` SCC | ❌ | ✅ | ❌ | — | — |
| `pause()` SCC | ❌ | ❌ | ✅ | — | — |
| `unpause()` SCC | ❌ | ❌ | ✅ | — | — |
| Видача ролей SCC | ❌ | ❌ | ✅ | — | — |
| `mint()` SFC | — | — | — | ✅ | ❌ |
| `batchMint()` SFC | — | — | — | ✅ | ❌ |
| `pause()` SFC | — | — | — | ❌ | ✅ |
| Видача ролей SFC | — | — | — | ❌ | ✅ |

---

## ⚙️ Функції Контрактів

### SCC — SilkenCarbonCoin

#### `mint(address to, uint256 amount, string calldata treeDid)`

```solidity
function mint(address to, uint256 amount, string calldata treeDid)
    external
    onlyRole(MINTER_ROLE)
{
    _mint(to, amount);
    emit CarbonMinted(to, amount, treeDid);
}
```

| Параметр | Тип | Опис |
|---|---|---|
| `to` | `address` | Адреса інвестора / власника дерева |
| `amount` | `uint256` | Кількість у wei (1 SCC = 10^18 wei) |
| `treeDid` | `string` | DID дерева (напр. `SNET-00A1B2C3`) |

- **Модифікатор:** `onlyRole(MINTER_ROLE)`
- **Guard on pause:** Опосередковано через `_update → whenNotPaused`
- **Виклик з бекенду:** `BlockchainMintingService` → `client.transact(contract, "mint", to, amount, identifier)`
- **Подія:** `CarbonMinted(address indexed investor, uint256 amount, string indexed treeDid)`

> ⚠️ **Розбіжність з Wiki:** Wiki (05_01, 05_02) посилається на функцію `mintForTree`, але в реальному контракті функція називається `mint`. Назва в ABI `BlockchainMintingService` також `"mint"` — відповідає контракту.

#### `batchMint(address[] calldata recipients, uint256[] calldata amounts, string[] calldata treeDids)`

```solidity
function batchMint(
    address[] calldata recipients,
    uint256[] calldata amounts,
    string[] calldata treeDids
) external onlyRole(MINTER_ROLE) {
    uint256 length = recipients.length;
    require(length == amounts.length && length == treeDids.length, "SCC: Array lengths mismatch");
    for (uint256 i = 0; i < length; i++) {
        _mint(recipients[i], amounts[i]);
        emit CarbonMinted(recipients[i], amounts[i], treeDids[i]);
    }
}
```

- **Призначення:** Газово-ефективна масова емісія для цілих секторів/кластерів
- **Валідація:** Перевірка рівності довжин масивів; **ліміт розміру відсутній** — BLOCKER B-04
- **Dynamic Tax:** При виклику `batchMint` з бекенду, `BlockchainMintingService` вставляє додаткових отримувачів (`DAO_TREASURY_ADDRESS`) коли баланс Treasury < 100,000 SCC
- **Gas Optimization [PR #253]:** `Treasury::MintBatchCollectorService` (cron кожні 5 хв) агрегує pending TX та відправляє пакетами по 100 через `BlockchainMintingService.call_batch`. `batchMint(100) ≈ 30-40%` дешевше ніж `100 × mint()`. Urgent TX (>30 хв) відправляються негайно.

#### `slash(address investor, uint256 amount)`

```solidity
function slash(address investor, uint256 amount)
    external
    onlyRole(SLASHER_ROLE)
{
    _burn(investor, amount);
    emit TokenSlashed(investor, amount);
}
```

- **Модифікатор:** `onlyRole(SLASHER_ROLE)`
- **Тригер:** `BurnCarbonTokensWorker → BlockchainBurningService → slash(investor, amount)` при >20% аномальних дерев у кластері
- **Guard on pause:** `_burn → _update → whenNotPaused` — слешинг заблокований під час паузи
- **Подія:** `TokenSlashed(address indexed investor, uint256 amount)`

> 🚨 **Критичний баг subgraph:** `subgraph/subgraph.yaml` підписаний на `Slashed(...)`, тоді як контракт емітує `TokenSlashed(...)`. Slashing-події **не індексуються** The Graph — `ProtocolFinancials.totalBurned` завжди `0`. ([05_01 BLOCKER-2])

#### `pause()` / `unpause()`

```solidity
function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
```

#### `_update(address from, address to, uint256 value)` — internal hook

```solidity
function _update(address from, address to, uint256 value)
    internal
    override
    whenNotPaused
{
    super._update(from, to, value);
}
```

- Блокує всі операції (mint, transfer, burn/slash) при активній паузі через модифікатор `whenNotPaused`

---

### SFC — SilkenForestCoin

#### `mint(address to, uint256 amount, string calldata clusterId)`

```solidity
function mint(address to, uint256 amount, string calldata clusterId)
    external
    onlyRole(MINTER_ROLE)
    whenNotPaused
{
    _mint(to, amount);
    emit ForestMinted(to, amount, clusterId);
}
```

| Параметр | Тип | Опис |
|---|---|---|
| `to` | `address` | Адреса отримувача (організація / DAO учасник) |
| `amount` | `uint256` | Кількість SFC у wei |
| `clusterId` | `string` | Ідентифікатор кластера. Бекенд формує: `"CLUSTER_#{tree.cluster_id}"` або `"CLUSTER_GLOBAL"` |

- **Відмінність від SCC:** `whenNotPaused` на рівні функції (не лише через `_update`)
- **Виклик з бекенду:** `BlockchainMintingService` — однакова логіка з SCC, але `token_type == "forest_coin"` → `FOREST_COIN_CONTRACT_ADDRESS`

#### `batchMint(address[] calldata recipients, uint256[] calldata amounts, string[] calldata clusterIds)`

- Аналогічний SCC `batchMint`, але прив'язаний до `clusterId` замість `treeDid`
- Має `whenNotPaused` безпосередньо на функції

#### `_update(address from, address to, uint256 value)` — internal override

```solidity
function _update(address from, address to, uint256 value)
    internal
    override(ERC20, ERC20Votes)
{
    if (paused()) {
        revert EnforcedPause();
    }
    super._update(from, to, value);
}
```

- Override необхідний через конфлікт між `ERC20` та `ERC20Votes`
- Перевірка паузи вручну (`if (paused()) revert EnforcedPause()`) замість модифікатора `whenNotPaused` — відмінність від SCC патерну (BLOCKER B-07)

#### `nonces(address owner)` — override для EIP-2612

```solidity
function nonces(address owner)
    public view override(ERC20Permit, Nonces) returns (uint256)
{
    return super.nonces(owner);
}
```

- Вирішення конфлікту MRO між `ERC20Permit` та `Nonces`

---

## 📡 Події (Events)

### SCC

| Подія | Сигнатура | Indexed поля | Subgraph |
|---|---|---|---|
| `CarbonMinted` | `CarbonMinted(address indexed investor, uint256 amount, string indexed treeDid)` | `investor`, `treeDid` (→ keccak256) | ✅ `handleCarbonMinted` |
| `TokenSlashed` | `TokenSlashed(address indexed investor, uint256 amount)` | `investor` | 🚨 Subgraph слухає `Slashed` — MISMATCH |

### SFC

| Подія | Сигнатура | Indexed поля | Subgraph |
|---|---|---|---|
| `ForestMinted` | `ForestMinted(address indexed investor, uint256 amount, string indexed clusterId)` | `investor`, `clusterId` (→ keccak256) | ❌ Не індексується |

### Subgraph vs Контракт — Повна Матриця

| Event у subgraph.yaml | Подія у контракті | Статус |
|---|---|---|
| `CarbonMinted(indexed address,uint256,indexed string)` | `CarbonMinted` | ✅ Збігається |
| `TokenSlashed(indexed address,uint256)` | `TokenSlashed` | ✅ Виправлено |
| `PremiumPaid(indexed address,uint256)` | ❌ **Відсутня в контракті** | 🚨 Подія не існує — BLOCKER B-08 |

> ⚠️ **Indexed string у Events:** `string indexed treeDid` та `string indexed clusterId` зберігаються як `keccak256` хеш — не як рядок. Off-chain підписники не можуть прочитати значення без окремого lookup. (BLOCKER B-10)

---

## 💸 Dynamic Tax — HYBRID PROTOCOL GAIA

`BlockchainMintingService` реалізує механізм автоматичного 2% відрахування від кожного SCC мінтингу до `DAO_TREASURY_ADDRESS`:

```ruby
DYNAMIC_TAX_RATE = BigDecimal("0.02")  # 2%

# При batchMint для carbon_coin:
if token_type == "carbon_coin" && insurance_pool_requires_funding?
  tax_amount = (tx.amount * DYNAMIC_TAX_RATE).round(4)
  forester_amount = tx.amount - tax_amount

  recipients.push(tx.to_address, ENV.fetch("DAO_TREASURY_ADDRESS"))
  amounts.push(to_wei(forester_amount), to_wei(tax_amount))
  identifiers.push(identifier_for(tx), "TAX_#{identifier_for(tx)}")
end
```

```ruby
def insurance_pool_requires_funding?
  # On-chain query: балансOf DAO Treasury < INSURANCE_POOL_THRESHOLD (100_000 SCC)
  # Кешується 15 хв. Failsafe: true при збої RPC.
  Rails.cache.fetch(TREASURY_CACHE_KEY, expires_in: TREASURY_CACHE_TTL) do
    fetch_treasury_balance_wei < INSURANCE_POOL_THRESHOLD_WEI
  end
end
```

**Наслідок:** Dynamic Tax (2%) застосовується коли баланс DAO Treasury < 100,000 SCC. Одиночний `mint()` (не `batchMint`) Dynamic Tax **не застосовує**.

---

## 🔄 Потік Мінтингу (Поточний Стан)

```
Telemetry → Lorenz Z-value → growth_points++
                                    ↓
                    TokenomicsEvaluatorWorker (щогодини, cron: 0 * * * *)
                                    ↓
                    Wallet.balance >= 10,000? → lock_and_mint!
                                    ↓
                    MintCarbonCoinWorker [queue: web3_critical]
                                    ↓
                    Guards (лише якщо telemetry_log переданий, oracle-driven flow):
                    ├── verified_by_iotex? == true
                    ├── oracle_status_fulfilled? (enum method)
                    └── hadron_kyc_status == "approved"
                    (TokenomicsEvaluatorWorker без log → growth_points вже верифіковані pipeline'ом)
                                    ↓
                    BlockchainMintingService#perform
                    ├── Oracle balance ≥ 0.05 MATIC
                    ├── Kredis lock (30s) — запобігає подвійному мінтингу
                    └── Dynamic Tax: 2% до DAO_TREASURY (якщо batchMint + insurance_pool_requires_funding?)
                                    ↓
                    SCC: mint(to, amount, treeDid)          ← MINTER_ROLE
                    SFC: mint(to, amount, "CLUSTER_{id}")   ← MINTER_ROLE
                                    ↓
                    BlockchainConfirmationWorker (+30s) → confirm!(tx_hash)
                                    ↓
                    The Graph: CarbonMintEvent indexed (SCC тільки)
```

**Конверсія:** 10,000 growth_points = 1 SCC (= 1 × 10^18 wei)

---

## 🔥 Потік Slashing (Поточний Стан)

```
ClusterHealthCheckWorker (02:00 UTC) [queue: default]
        ↓
NaasContract#check_cluster_health!
        ↓
> 20% дерев з stress_index >= 1.0?
        ↓
activate_slashing_protocol! → status = :breached
        ↓
BurnCarbonTokensWorker [queue: critical]
        ↓
BlockchainBurningService#call
        ↓
SCC: slash(investor, amount)   ← SLASHER_ROLE (= той самий ORACLE_PRIVATE_KEY)
        ↓
emit TokenSlashed(...)
        ↓
The Graph індексує `TokenSlashed` → `ProtocolFinancials.totalBurned` оновлюється
        ↓
EwsAlert + MaintenanceRecord + AuditLog
        ↓
FilecoinArchiveWorker → IPFS/Filecoin permanent record
```

---

## 🔌 Зв'язок з Rails Backend

| Контракт дія | Сервіс | Воркер | Черга | Retry |
|---|---|---|---|---|
| `SCC.mint()` | `BlockchainMintingService` | `MintCarbonCoinWorker` | `web3_critical` | 5 |
| `SCC.batchMint()` | `BlockchainMintingService` | `MintCarbonCoinWorker` | `web3_critical` | 5 |
| `SFC.mint()` | `BlockchainMintingService` | `MintCarbonCoinWorker` | `web3_critical` | 5 |
| `SFC.batchMint()` | `BlockchainMintingService` | `MintCarbonCoinWorker` | `web3_critical` | 5 |
| `SCC.slash()` | `BlockchainBurningService` | `BurnCarbonTokensWorker` | `critical` | 5 |
| TX підтвердження | — | `BlockchainConfirmationWorker` | `web3_critical` | 5 |
| Tokenomics eval | — | `TokenomicsEvaluatorWorker` | `default` | — |
| Events indexing | `TheGraph::QueryService` | — | — | — |
| KlimaDAO retire | `KlimaDao::RetirementService` | `KlimaRetirementWorker` | `web3_low` | 3 |
| Rollback | `MintingRollbackService` | — | — | — |

**Rollback:** `MintingRollbackService.call(...)` при вичерпанні 5 retry через `sidekiq_retries_exhausted`.

---

## 🌐 Subgraph (The Graph)

**Файли:** `subgraph/schema.graphql`, `subgraph/subgraph.yaml`, `subgraph/src/mapping.ts`
**Мережа:** `polygon-amoy`
**Адреса контракту:** `0x0000000000000000000000000000000000000000` (TODO: замінити після деплою)

```yaml
# subgraph/subgraph.yaml — поточний стан eventHandlers:
- event: CarbonMinted(indexed address,uint256,indexed string)
  handler: handleCarbonMinted           # ✅ OK

- event: Slashed(indexed address,uint256,indexed string)
  handler: handleSlashed                # 🚨 MISMATCH: контракт emits "TokenSlashed"

- event: PremiumPaid(indexed address,uint256)
  handler: handlePremiumPaid            # 🚨 Подія відсутня в контракті
```

**GraphQL Entities:**

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
  totalBurned: BigInt!    # ⚠️ Завжди 0 через MISMATCH
  totalPremiums: BigInt!  # ⚠️ Завжди 0 — PremiumPaid відсутня в контракті
}
```

---

## 🌍 Зовнішні Залежності

| Параметр | Значення |
|---|---|
| **Мережа** | Polygon PoS (Amoy testnet → Mainnet) |
| **Toolchain** | Foundry (forge, cast, anvil) |
| **OpenZeppelin** | 5.x (`pragma ^0.8.20`) |
| **RPC** | `ALCHEMY_POLYGON_RPC_URL` (через `Web3::RpcConnectionPool`) |
| **Oracle wallet** | `ORACLE_PRIVATE_KEY` — єдиний ключ для MINTER + SLASHER |
| **The Graph** | `subgraph/` — індексує лише SCC події (SFC — ні) |
| **Chainlink** | Oracle dispatch для Proof of Growth pipeline (⚠️ Hybrid mode) |
| **peaq DID** | Верифікація `did:peaq:0x...` перед мінтингом |
| **IoTeX W3bstream** | ZK-доказ апаратного походження телеметрії |
| **Polygon Hadron** | KYC/KYB (ERC-3643) — `hadron_kyc_status == "approved"` |
| **KlimaDAO** | ESG carbon retirement (approve + retire) |
| **Ethereum L1** | Weekly state root anchoring (SHA-256) |

---

## ✅ Закриті Блокери (PR #254)

Всі блокери, виявлені під час аудиту, закриті в PR #254 (commit 6f4e7ee). Контракти готові до зовнішнього аудиту (CertiK/Hacken) та Mainnet deployment.

| # | Блокер | Область | Статус |
|---|---|---|---|
| B-01 | Відсутність max supply | Security | ✅ `MAX_SUPPLY = 1_000_000_000 SCC` / `100_000_000 SFC` з `require` |
| B-02 | Єдиний oracle = minter + slasher | Security | ✅ Конструктор: `minterOracle` + `slasherOracle` — окремі ролі |
| B-03 | Zero address check відсутній | Security | ✅ `require(admin != address(0))` у конструкторах SCC та SFC |
| B-04 | Відсутній ліміт batchMint | Functional | ✅ `MAX_BATCH_SIZE = 200` + pre-calculated total (gas optimization) |
| B-06 | SFC без slash механізму | Governance | ✅ `SLASHER_ROLE` + `slash()` + `GovernanceSlashed` event додано до SFC |
| B-07 | Непослідовна реалізація паузи | Maintainability | ✅ Уніфіковано: `whenNotPaused` в `_update` для SCC та SFC |
| B-08 | `PremiumPaid` відсутня в контракті | Subgraph | ✅ `PremiumPaid` event + `recordPremiumPaid()` додано до SCC |
| B-10 | Indexed `string` у Events | Observability | ✅ `treeDidHash = keccak256(treeDid)` як окреме `bytes32 indexed` поле |
| B-12 | `mintForTree` vs `mint` назва | Documentation | ✅ `mintForTree()` + backward-compatible `mint()` alias в SCC |
| B-13 | Відсутній ReentrancyGuard | Security | ✅ `ReentrancyGuard` успадковано в SCC та SFC |
| B-14 | Неповний NatSpec у SFC | Documentation | ✅ Повний NatSpec для всіх функцій SCC та SFC |
| B-15 | `startBlock: 0` у subgraph | Performance | ✅ TODO-коментар уточнено; реальний startBlock встановлюється при деплої |

## 📂 Структура Файлів (File Map)

```
contracts/
├── SilkenCarbonCoin.sol              # SCC: ERC-20 + AccessControl + Pausable + ReentrancyGuard + Permit
├── SilkenForestCoin.sol              # SFC: ERC-20 + AccessControl + Pausable + ReentrancyGuard + Permit + Votes
└── StateRootAnchor.sol               # Ethereum L1 state root anchoring (weekly finality)

app/services/
├── blockchain_minting_service.rb     # SCC + SFC mint / batchMint + Dynamic Tax
└── blockchain_burning_service.rb     # SCC slash + SFC slash

app/workers/
├── mint_carbon_coin_worker.rb        # queue: web3_critical, retry: 5
├── burn_carbon_tokens_worker.rb      # queue: critical, retry: 5
├── blockchain_confirmation_worker.rb # queue: web3_critical, retry: 5
└── tokenomics_evaluator_worker.rb    # cron: 0 * * * *, queue: default

subgraph/
├── schema.graphql                    # CarbonMintEvent (treeDidHash), SlashingEvent, ProtocolFinancials
├── subgraph.yaml                     # ✅ PremiumPaid handler (event додано до контракту)
└── src/mapping.ts                    # handleCarbonMinted, handleTokenSlashed, handlePremiumPaid

spec/services/
├── blockchain_minting_service_spec.rb
└── blockchain_burning_service_spec.rb
```

---

## 🗳️ Planned: Governance DAO (Законодавча Гілка Влади)

> **Нотатка N13 інтегрована (Сесія 3).** Поточний стан: константи протоколу жорстко зашиті в коді. Запланована архітектурна зміна для post-TRL 6.

### Проблема (Абсолютна Монархія)

Поточні константи Gaia 2.0 зашиті в Rails-сервісних класах та firmware:

| Константа | Де зашита | Значення |
|-----------|---------|---------|
| `SIGMA = 10.0`, `RHO = 28.0`, `BETA = 8.0/3.0` | `SilkenNet::Attractor` | Параметри атрактора Лоренца |
| `SLASH_THRESHOLD = 0.20` | `ContractHealthCheckService` | 20% аномальних дерев → Slashing |
| `POINTS_PER_SCC = 10_000` | `TokenomicsEvaluatorWorker` | Конверсія growth points → SCC |
| `STRESS_THRESHOLD = 0.83` | `ContractHealthCheckService` | Поріг стресу дерева |

**Проблема при планетарному масштабуванні:** Тропічні ліси, тайга та мангрові зарості мають принципово різні метаболічні базлайни. Одні й ті самі константи σ=10, ρ=28 призведуть до масових хибних Slashings у тропіках та пропуску реальних аномалій у тайзі.

Зміна будь-якої константи = повний деплой Rails + перепрошивка всіх STM32-вузлів. При мільярдах дерев — практично нездійсненне.

### Рішення — Governance DAO

SFC-токен вже має `ERC20Votes` та `ERC20Permit` — ідеальна база для DAO голосувань.

**Архітектура:**

```
SFC holders / Multisig Forester Council
        │ vote()
        ▼
GovernorContract.sol (OpenZeppelin Governor + TimelockController)
        │ after 48h timelock
        ▼
ProtocolParameters.sol (on-chain registry)
        │ read via TheGraph
        ▼
Governance::ParameterSyncWorker (Sidekiq, queue: web3_low)
        │ scheduled 1x/day
        ▼
SilkenNet::Attractor (dynamic params instead of constants)
ContractHealthCheckService (dynamic slash threshold)
TokenomicsEvaluatorWorker (dynamic conversion rate)
```

**Нові смарт-контракти:**
1. `GovernorContract.sol` — OpenZeppelin Governor з TimelockController (48h)
2. `ProtocolParameters.sol` — on-chain registry: `setSigma(uint)`, `setRho(uint)`, `setSlashThreshold(uint)`, `setPointsPerScc(uint)`

**Новий Rails воркер:**
- `Governance::ParameterSyncWorker` (queue: `web3_low`, cron: 1×/день)
- Зчитує поточні параметри з `ProtocolParameters.sol` через `TheGraph::QueryService`
- Зберігає у `SystemParameter` (нова модель) або Rails credentials з auto-rotation

### Пріоритет та Залежності

| Аспект | Деталі |
|--------|--------|
| **Пріоритет** | Post-TRL 6. Не блокує прототип або seed-раунд |
| **Залежить від** | `SilkenForestCoin.sol` (SFC) задеплоєний → ✅ є |
| **Блокує** | Планетарне масштабування з різними кліматичними зонами |
| **Ризики DAO** | Voter apathy, governance attacks (купівля SFC для зміни параметрів) → потрібен quorum + timelock |

### Governance-Aware Backend (Future State)

```ruby
# Замість: SIGMA = 10.0
# Буде:
sigma = SystemParameter.current(:lorenz_sigma, default: 10.0)

# Замість: SLASH_THRESHOLD = 0.20
# Буде:
threshold = SystemParameter.current(:slash_threshold, default: 0.20)
```

**`SystemParameter` model:** кеш поточних on-chain значень з TTL 24h. При недоступності The Graph — fallback на default constants.

*Документ згенеровано: Reverse Shaping Cycle 1 Small Batch (Issue #172) · Стан "як є" на 2026-03-23*
*Джерела: `contracts/SilkenCarbonCoin.sol`, `contracts/SilkenForestCoin.sol`,*
*`app/services/blockchain_minting_service.rb`, `app/services/blockchain_burning_service.rb`,*
*`subgraph/subgraph.yaml`,*
*Wiki: [05_01 Multichain Architecture](https://github.com/Alexey-Lukin/silken_net/wiki/05_01_Multichain_Architecture), [05_02 Proof of Growth Pipeline](https://github.com/Alexey-Lukin/silken_net/wiki/05_02_Proof_of_Growth_Pipeline)*
