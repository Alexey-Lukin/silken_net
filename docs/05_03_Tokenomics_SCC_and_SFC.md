# 05_03: Токеноміка — SCC & SFC (Смарт-контракти на Polygon)

## 🎯 Мета

Зафіксувати реальний стан («як є») смарт-контрактів токеноміки Gaia 2.0 — `SilkenCarbonCoin` (SCC) та `SilkenForestCoin` (SFC). Документ описує стандарти токенів, ієрархію ролей, ключові функції, механізм Dynamic Tax, зв'язок з бекендом та повний перелік знайдених блокерів.

---

## ✅ Статус

- **Поточний TRL:** TRL 9 — Всі контракти production-ready, блокери закриті (PR #254), готові до Mainnet deployment та зовнішнього аудиту.
- **SCC контракт:** ✅ Production-ready (MAX_SUPPLY=1B, MINTER/SLASHER split, ReentrancyGuard, NatSpec, PremiumPaid event, mintForTree alias, audit hardening)
- **SFC контракт:** ✅ Production-ready (MAX_SUPPLY=100M, SLASHER_ROLE + slash(), ReentrancyGuard, NatSpec, unified `whenNotPaused`, audit hardening)
- **Аудит-зміцнення (PR #255):** ✅ Додано явну перевірку балансу в `slash()`, валідацію нульових значень у `mint()`/`slash()`, перевірку порожнього батчу у `batchMint()`, NatSpec для MAX_SUPPLY, документацію emit-коментарів у конструкторах, NatSpec щодо EIP-712 chain safety. [B-15] Додано `treeDid`/`clusterId` length limit (≤256 bytes) у `mint()`/`mintForTree()`/`batchMint()` — захист від The Graph DoS; валідацію `recordPremiumPaid()` (`payer != address(0)`, `amount > 0`) — запобігання event spoofing; per-element string validation у `batchMint()` для обох контрактів
- **Backend інтеграція:** ✅ `BlockchainMintingService` + `BlockchainBurningService`
- **The Graph subgraph:** ✅ `TokenSlashed` виправлено, `PremiumPaid` додано, `treeDidHash` (bytes32) додано
- **Синхронізація:** 2026-04-16
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
| `MINTER_ROLE` | `keccak256("MINTER_ROLE")` | `minterOracle` (окремий параметр) | `mintForTree()`, `mint()`, `batchMint()` |
| `SLASHER_ROLE` | `keccak256("SLASHER_ROLE")` | `slasherOracle` (окремий параметр) | `slash()` |

```solidity
constructor(address admin, address minterOracle, address slasherOracle)
    ERC20("Silken Carbon Coin", "SCC")
    ERC20Permit("Silken Carbon Coin")
{
    require(admin != address(0), "SCC: zero admin");
    require(minterOracle != address(0), "SCC: zero minter oracle");
    require(slasherOracle != address(0), "SCC: zero slasher oracle");
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    // Emits: RoleGranted(DEFAULT_ADMIN_ROLE, admin, msg.sender)
    _grantRole(MINTER_ROLE, minterOracle);
    // Emits: RoleGranted(MINTER_ROLE, minterOracle, msg.sender)
    _grantRole(SLASHER_ROLE, slasherOracle);
    // Emits: RoleGranted(SLASHER_ROLE, slasherOracle, msg.sender)
}
```

### SFC — Ролі

| Роль | Константа | Призначається в конструкторі | Можливості |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | `0x00` | `admin` | Видача / відкликання ролей; `pause()`, `unpause()` |
| `MINTER_ROLE` | `keccak256("MINTER_ROLE")` | `oracle` (параметр конструктора) | `mint()`, `batchMint()` |
| `SLASHER_ROLE` | `keccak256("SLASHER_ROLE")` | `slasherOracle` | `slash()` — спалення governance-токенів при breach |

```solidity
constructor(address admin, address oracle, address slasherOracle)
    ERC20("Silken Forest Coin", "SFC")
    ERC20Permit("Silken Forest Coin")
{
    require(admin != address(0), "SFC: zero admin");
    require(oracle != address(0), "SFC: zero oracle");
    require(slasherOracle != address(0), "SFC: zero slasher oracle");
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    // Emits: RoleGranted(DEFAULT_ADMIN_ROLE, admin, msg.sender)
    _grantRole(MINTER_ROLE, oracle);
    // Emits: RoleGranted(MINTER_ROLE, oracle, msg.sender)
    _grantRole(SLASHER_ROLE, slasherOracle);
    // Emits: RoleGranted(SLASHER_ROLE, slasherOracle, msg.sender)
}
```

### Матриця Дозволів

| Дія | SCC MINTER | SCC SLASHER | SCC ADMIN | SFC MINTER | SFC SLASHER | SFC ADMIN |
|---|---|---|---|---|---|---|
| `mintForTree()` / `mint()` SCC | ✅ | ❌ | ❌ | — | — | — |
| `batchMint()` SCC | ✅ | ❌ | ❌ | — | — | — |
| `slash()` SCC | ❌ | ✅ | ❌ | — | — | — |
| `pause()` SCC | ❌ | ❌ | ✅ | — | — | — |
| `unpause()` SCC | ❌ | ❌ | ✅ | — | — | — |
| Видача ролей SCC | ❌ | ❌ | ✅ | — | — | — |
| `mint()` SFC | — | — | — | ✅ | ❌ | ❌ |
| `batchMint()` SFC | — | — | — | ✅ | ❌ | ❌ |
| `slash()` SFC | — | — | — | ❌ | ✅ | ❌ |
| `pause()` SFC | — | — | — | ❌ | ❌ | ✅ |
| Видача ролей SFC | — | — | — | ❌ | ❌ | ✅ |

---

## ⚙️ Функції Контрактів

### SCC — SilkenCarbonCoin

#### `mint(address to, uint256 amount, string calldata treeDid)`

```solidity
function mint(address to, uint256 amount, string calldata treeDid)
    external
    onlyRole(MINTER_ROLE)
    nonReentrant
{
    require(to != address(0), "SCC: zero recipient");
    require(amount > 0, "SCC: zero amount");
    require(bytes(treeDid).length > 0, "SCC: empty treeDid");
    require(bytes(treeDid).length <= 256, "SCC: treeDid too long");
    require(totalSupply() + amount <= MAX_SUPPLY, "SCC: cap exceeded");
    _mint(to, amount);
    emit CarbonMinted(to, amount, keccak256(bytes(treeDid)), treeDid);
}
```

| Параметр | Тип | Опис |
|---|---|---|
| `to` | `address` | Адреса інвестора / власника дерева |
| `amount` | `uint256` | Кількість у wei (1 SCC = 10^18 wei) |
| `treeDid` | `string` | DID дерева (напр. `SNET-00A1B2C3`), max 256 bytes |

- **Модифікатор:** `onlyRole(MINTER_ROLE)`, `nonReentrant`
- **Валідація:** `to != address(0)`, `amount > 0`, `treeDid` не порожній, `treeDid` ≤ 256 bytes (The Graph safety), `totalSupply() + amount <= MAX_SUPPLY` (revert: `"SCC: cap exceeded"`)
- **Guard on pause:** Опосередковано через `_update → whenNotPaused`
- **Виклик з бекенду:** `BlockchainMintingService` → `client.transact(contract, "mintForTree", to, amount, identifier)` (також доступний `"mint"` alias)

#### `batchMint(address[] calldata recipients, uint256[] calldata amounts, string[] calldata treeDids)`

```solidity
function batchMint(
    address[] calldata recipients,
    uint256[] calldata amounts,
    string[] calldata treeDids
) external onlyRole(MINTER_ROLE) nonReentrant {
    uint256 length = recipients.length;
    require(length > 0, "SCC: empty batch");
    require(length == amounts.length && length == treeDids.length, "SCC: array length mismatch");
    require(length <= MAX_BATCH_SIZE, "SCC: batch too large");

    // Gas optimization: single SLOAD for totalSupply + pre-calculated total
    uint256 batchTotal = 0;
    for (uint256 i = 0; i < length; i++) {
        require(recipients[i] != address(0), "SCC: zero recipient");
        require(amounts[i] > 0, "SCC: zero amount");
        require(bytes(treeDids[i]).length > 0, "SCC: empty treeDid");
        require(bytes(treeDids[i]).length <= 256, "SCC: treeDid too long");
        batchTotal += amounts[i];
    }
    require(totalSupply() + batchTotal <= MAX_SUPPLY, "SCC: cap exceeded");

    for (uint256 i = 0; i < length; i++) {
        _mint(recipients[i], amounts[i]);
        emit CarbonMinted(recipients[i], amounts[i], keccak256(bytes(treeDids[i])), treeDids[i]);
    }
}
```

- **Призначення:** Газово-ефективна масова емісія для цілих секторів/кластерів
- **Валідація:** `length > 0` (revert: `"SCC: empty batch"`); рівність довжин масивів; `MAX_BATCH_SIZE = 200` — захист від gas overflow; кожен `recipient != address(0)`, `amount > 0`, `treeDid` не порожній, `treeDid` ≤ 256 bytes; `totalSupply() + batchTotal <= MAX_SUPPLY` перевіряється атомарно до мінтингу
- **Dynamic Tax:** При виклику `batchMint` з бекенду, `BlockchainMintingService` вставляє додаткових отримувачів (`DAO_TREASURY_ADDRESS`) коли баланс Treasury < 100,000 SCC
- **Gas Optimization [PR #253]:** `Treasury::MintBatchCollectorService` (cron кожні 5 хв) агрегує pending TX та відправляє пакетами по 100 через `BlockchainMintingService.call_batch`. `batchMint(100) ≈ 30-40%` дешевше ніж `100 × mint()`. Urgent TX (>30 хв) відправляються негайно.
- **Gas Analysis:** `MAX_BATCH_SIZE = 200` — on-chain safety cap. Backend обмежує до 100. Gas consumption для 200 мінтів з типовими DID (~20 bytes): ~51K gas × 200 ≈ 10.2M gas — в межах Polygon block gas limit (30M). Solidity 0.8+ забезпечує вбудований overflow-захист для `batchTotal += amounts[i]` (revert `Panic(0x11)` при переповненні).
- **Binary Search Isolation [PR #254]:** При `batchMint` dry-run revert замість наївного N×`mint()` fallback використовується Divide & Conquer алгоритм — бінарний пошук "отруйних" записів через `eth_call`. Чисті підбатчі → `batchMint`, отруйні → `mint()` поштучно. Для 1 отруйного з 100: ~14 `eth_call` + 2-3 `batchMint` замість 100 `mint()`. Guards: `MIN_BINARY_SEARCH_SIZE=4`, `MAX_BINARY_SEARCH_DEPTH=6`, `POISONED_RATIO_THRESHOLD=30%`.

#### `slash(address investor, uint256 amount)`

```solidity
function slash(address investor, uint256 amount)
    external
    onlyRole(SLASHER_ROLE)
    nonReentrant
{
    require(investor != address(0), "SCC: zero investor");
    require(amount > 0, "SCC: zero amount");
    require(balanceOf(investor) >= amount, "SCC: insufficient balance");
    _burn(investor, amount);
    emit TokenSlashed(investor, amount);
}
```

- **Модифікатор:** `onlyRole(SLASHER_ROLE)`, `nonReentrant`
- **Валідація:** `investor != address(0)`, `amount > 0`, `balanceOf(investor) >= amount` (revert: `"SCC: insufficient balance"`) — явна перевірка замість generic OZ помилки
- **Тригер:** `BurnCarbonTokensWorker → BlockchainBurningService → slash(investor, amount)` при >20% аномальних дерев у кластері
- **Guard on pause:** `_burn → _update → whenNotPaused` — слешинг заблокований під час паузи
- **Подія:** `TokenSlashed(address indexed investor, uint256 amount)`

#### `recordPremiumPaid(address payer, uint256 amount)`

```solidity
function recordPremiumPaid(address payer, uint256 amount)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
{
    require(payer != address(0), "SCC: zero payer");
    require(amount > 0, "SCC: zero premium");
    emit PremiumPaid(payer, amount);
}
```

- **Модифікатор:** `onlyRole(DEFAULT_ADMIN_ROLE)`
- **Призначення:** Off-chain tracking для Parametric Insurance. Фактична передача токенів відбувається поза контрактом — функція тільки емітує подію `PremiumPaid` для індексації The Graph subgraph
- **Валідація:** `payer != address(0)`, `amount > 0` — запобігає event spoofing (некоректні події індексувались би у subgraph `ProtocolFinancials.totalPremiums`)
- **Подія:** `PremiumPaid(address indexed payer, uint256 amount)` → `handlePremiumPaid` у subgraph

#### `pause()` / `unpause()`

```solidity
function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
```

- **Operational Security:** Для production deployment `DEFAULT_ADMIN_ROLE` має бути призначено Gnosis Safe multisig (3/5 або 2/3) замість EOA (Externally Owned Account). `pause()` — це аварійний механізм для негайної зупинки при exploits, тому timelock **не** додається (під час хаку потрібна реакція за хвилини, а не дні)

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
- Reentrancy protection забезпечується `nonReentrant` guards на `mint()`, `mintForTree()`, `slash()`, `batchMint()` — `nonReentrant` не може бути доданий сюди напряму (вкладений виклик спричинив би revert)

---

### SFC — SilkenForestCoin

#### `mint(address to, uint256 amount, string calldata clusterId)`

```solidity
function mint(address to, uint256 amount, string calldata clusterId)
    external
    onlyRole(MINTER_ROLE)
    nonReentrant
{
    require(to != address(0), "SFC: zero recipient");
    require(amount > 0, "SFC: zero amount");
    require(bytes(clusterId).length > 0, "SFC: empty clusterId");
    require(bytes(clusterId).length <= 256, "SFC: clusterId too long");
    require(totalSupply() + amount <= MAX_SUPPLY, "SFC: cap exceeded");
    _mint(to, amount);
    emit ForestMinted(to, amount, keccak256(bytes(clusterId)), clusterId);
}
```

| Параметр | Тип | Опис |
|---|---|---|
| `to` | `address` | Адреса отримувача (організація / DAO учасник) |
| `amount` | `uint256` | Кількість SFC у wei |
| `clusterId` | `string` | Ідентифікатор кластера, max 256 bytes. Бекенд формує: `"CLUSTER_#{tree.cluster_id}"` або `"CLUSTER_GLOBAL"` |

- **Модифікатор:** `onlyRole(MINTER_ROLE)`, `nonReentrant`
- **Валідація:** `to != address(0)`, `amount > 0`, `clusterId` не порожній, `clusterId` ≤ 256 bytes (The Graph safety), `totalSupply() + amount <= MAX_SUPPLY` (revert: `"SFC: cap exceeded"`)
- **Guard on pause:** Опосередковано через `_update(ERC20, ERC20Votes) → whenNotPaused`
- **Виклик з бекенду:** `BlockchainMintingService` — однакова логіка з SCC, але `token_type == "forest_coin"` → `FOREST_COIN_CONTRACT_ADDRESS`

#### `batchMint(address[] calldata recipients, uint256[] calldata amounts, string[] calldata clusterIds)`

- Аналогічний SCC `batchMint`, але прив'язаний до `clusterId` замість `treeDid`
- Модифікатор: `onlyRole(MINTER_ROLE)`, `nonReentrant`; перевіряє `length > 0`, рівність масивів, `MAX_BATCH_SIZE`; per-element: `recipient != address(0)`, `amount > 0`, `clusterId` не порожній, `clusterId` ≤ 256 bytes; `totalSupply() + batchTotal <= MAX_SUPPLY` атомарно

#### `slash(address investor, uint256 amount)`

```solidity
function slash(address investor, uint256 amount)
    external
    onlyRole(SLASHER_ROLE)
    nonReentrant
{
    require(investor != address(0), "SFC: zero investor");
    require(amount > 0, "SFC: zero amount");
    require(balanceOf(investor) >= amount, "SFC: insufficient balance");
    _burn(investor, amount);
    emit GovernanceSlashed(investor, amount);
}
```

- **Модифікатор:** `onlyRole(SLASHER_ROLE)`, `nonReentrant`
- **Валідація:** `investor != address(0)`, `amount > 0`, `balanceOf(investor) >= amount` (revert: `"SFC: insufficient balance"`)
- **Тригер:** `BurnCarbonTokensWorker → BlockchainBurningService → slash(investor, amount)` при порушенні NaaS контракту
- **Guard on pause:** `_burn → _update → whenNotPaused` — slashing заблокований під час паузи
- **Подія:** `GovernanceSlashed(address indexed investor, uint256 amount)`

#### `_update(address from, address to, uint256 value)` — internal override

```solidity
function _update(address from, address to, uint256 value)
    internal
    override(ERC20, ERC20Votes)
    whenNotPaused
{
    super._update(from, to, value);
}
```

- Override необхідний через конфлікт між `ERC20` та `ERC20Votes`
- Використовує `whenNotPaused` модифікатор — уніфіковано з SCC патерном
- Reentrancy protection забезпечується `nonReentrant` guards на `mint()`, `slash()`, `batchMint()` — `nonReentrant` не може бути доданий сюди напряму (вкладений виклик спричинив би revert)

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
| `CarbonMinted` | `CarbonMinted(address indexed investor, uint256 amount, bytes32 indexed treeDidHash, string treeDid)` | `investor`, `treeDidHash` | ✅ `handleCarbonMinted` |
| `TokenSlashed` | `TokenSlashed(address indexed investor, uint256 amount)` | `investor` | ✅ `handleTokenSlashed` |
| `PremiumPaid` | `PremiumPaid(address indexed payer, uint256 amount)` | `payer` | ✅ `handlePremiumPaid` |

### SFC

| Подія | Сигнатура | Indexed поля | Subgraph |
|---|---|---|---|
| `ForestMinted` | `ForestMinted(address indexed investor, uint256 amount, bytes32 indexed clusterIdHash, string clusterId)` | `investor`, `clusterIdHash` (bytes32 keccak256) | ❌ Не індексується |

### Subgraph vs Контракт — Повна Матриця

| Event у subgraph.yaml | Подія у контракті | Статус |
|---|---|---|
| `CarbonMinted(indexed address,uint256,indexed bytes32,string)` | `CarbonMinted` | ✅ `treeDidHash` (bytes32) |
| `TokenSlashed(indexed address,uint256)` | `TokenSlashed` | ✅ Синхронізовано |
| `PremiumPaid(indexed address,uint256)` | `PremiumPaid` | ✅ Event + handler додано |

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
                    ├── Dynamic Tax: 2% до DAO_TREASURY (якщо batchMint + insurance_pool_requires_funding?)
                    └── [batchMint] eth_call dry-run (batch_dry_run_reverts?)
                         ├── ok  → batchMint() — атомарна пакетна емісія
                         └── revert → 🔍 Binary Search Isolation (Divide & Conquer)
                                       ├── split batch in half → eth_call dry-run per half
                                       ├── clean half → batchMint() (gas-efficient)
                                       ├── poisoned half → recurse (depth < 6, size ≥ 4)
                                       ├── >30% poisoned → fallback to individual mints
                                       └── isolated poisoned → mint_individual() (fails gracefully)
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
SCC: slash(investor, amount)   ← SLASHER_ROLE (`ORACLE_SLASHER_PRIVATE_KEY`)
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
| TX підтвердження | — | `BlockchainConfirmationWorker` | `web3_critical` | 10 |
| Tokenomics eval | — | `TokenomicsEvaluatorWorker` | `default` | — |
| Events indexing | `TheGraph::QueryService` | — | — | — |
| KlimaDAO retire | `KlimaDao::RetirementService` | `KlimaRetirementWorker` | `web3_low` | 3 |
| Rollback | `MintingRollbackService` | — | — | — |

**Rollback:** `MintingRollbackService.call(transactions:)` при вичерпанні 10 retry `BlockchainConfirmationWorker` через `sidekiq_retries_exhausted` (~15-20 хвилин поллінгу мемпулу).

---

## 🌐 Subgraph (The Graph)

**Файли:** `subgraph/schema.graphql`, `subgraph/subgraph.yaml`, `subgraph/src/mapping.ts`
**Мережа:** `polygon-amoy`
**Адреса контракту:** `0x0000000000000000000000000000000000000000` (TODO: замінити після деплою)

```yaml
# subgraph/subgraph.yaml — поточний стан eventHandlers:
- event: CarbonMinted(indexed address,uint256,indexed bytes32,string)
  handler: handleCarbonMinted           # ✅ treeDidHash як bytes32

- event: TokenSlashed(indexed address,uint256)
  handler: handleTokenSlashed           # ✅ Синхронізовано з контрактом

- event: PremiumPaid(indexed address,uint256)
  handler: handlePremiumPaid            # ✅ Event додано до контракту
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
  totalBurned: BigInt!    # ✅ Індексується через TokenSlashed
  totalPremiums: BigInt!  # ✅ Індексується через PremiumPaid
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
| **Oracle wallet** | `ORACLE_MINTER_PRIVATE_KEY` (MINTER_ROLE) + `ORACLE_SLASHER_PRIVATE_KEY` (SLASHER_ROLE) — окремі ключі |
| **The Graph** | `subgraph/` — індексує лише SCC події (SFC — ні) |
| **Chainlink** | Oracle dispatch для Proof of Growth pipeline (⚠️ Hybrid mode) |
| **peaq DID** | Верифікація `did:peaq:0x...` перед мінтингом |
| **IoTeX W3bstream** | ZK-доказ апаратного походження телеметрії |
| **Polygon Hadron** | KYC/KYB (ERC-3643) — `hadron_kyc_status == "approved"` |
| **KlimaDAO** | ESG carbon retirement (approve + retire) |
| **Ethereum L1** | Weekly state root anchoring (SHA-256) |

---

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

---

*Документ згенеровано: Reverse Shaping Cycle 1 Small Batch (Issue #172) · Стан "як є" на 2026-03-23*
*Джерела: `contracts/SilkenCarbonCoin.sol`, `contracts/SilkenForestCoin.sol`,*
*`app/services/blockchain_minting_service.rb`, `app/services/blockchain_burning_service.rb`,*
*`subgraph/subgraph.yaml`,*
*Wiki: [05_01 Multichain Architecture](https://github.com/Alexey-Lukin/silken_net/wiki/05_01_Multichain_Architecture), [05_02 Proof of Growth Pipeline](https://github.com/Alexey-Lukin/silken_net/wiki/05_02_Proof_of_Growth_Pipeline)*

---

## ♻️ Afterlife Economy — Puro.earth Biochar Integration

Коли дерево помирає (природна смерть або катастрофічна подія), його біомаса зберігає економічну цінність через Biochar carbon removal credits (CORCs) на реєстрі [Puro.earth](https://puro.earth).

### Потік

```
Tree dies → Forester extracts dead wood → MaintenanceRecord (biomass_extraction)
         ↓
EcosystemHealingWorker → Tree status → :deceased
         ↓
PuroEarthPassportWorker → D-MRV "Biomass Passport" generated
         ↓
Payload: { tree_did, biomass_yield_kg, extraction_date, gps_coordinates, lifetime_telemetry_hash }
         ↓
blockchain anchoring → biomass_passport_tx_hash stored on MaintenanceRecord
         ↓
Puro.earth registry → Biochar CORC issuance (майбутня інтеграція)
```

### D-MRV Biomass Passport

Digital Measurement, Reporting and Verification (D-MRV) паспорт забезпечує tamper-proof провенанс для видобутої біомаси:

| Поле | Джерело | Призначення |
|------|---------|-------------|
| `tree_did` | Tree.did (SNET-XXXXXXXX) | Унікальна апаратна ідентичність дерева-джерела |
| `biomass_yield_kg` | MaintenanceRecord | Вага видобутої мертвої деревини |
| `extraction_date` | MaintenanceRecord.performed_at | Timestamp фізичного видобутку |
| `gps_coordinates` | MaintenanceRecord або Tree | Географічне підтвердження походження |
| `lifetime_telemetry_hash` | SHA-256 від telemetry history | Tamper-proof зв'язок з сенсорними даними дерева |

### Економічний Impact

- Мертві дерева продовжують генерувати цінність через Biochar CORCs замість того, щоб бути відходами
- Кожен CORC представляє верифіковане видалення вуглецю (методологія Puro Standard)
- Lifetime telemetry hash гарантує, що біомаса походить з моніторованого, верифікованого дерева
- GPS-координати запобігають подвійному підрахунку між лісовими ділянками

> **Статус:** `PuroEarthPassportWorker` — у черзі `web3` (пріоритет 7). Інтеграція з реальним API Puro.earth є наступним кроком після TRL 6 (BLOCKER-5 в `05_01_Multichain_Architecture`).
