# 05_03: Токеноміка — SCC & SFC (Смарт-контракти на Polygon)

## 🎯 Мета

Зафіксувати реальний стан («як є») смарт-контрактів токеноміки Gaia 2.0 — `SilkenCarbonCoin` (SCC) та `SilkenForestCoin` (SFC). Документ описує стандарти токенів, ієрархію ролей, ключові функції, механізм Dynamic Tax, зв'язок з бекендом та повний перелік знайдених блокерів.

---

## ✅ Статус

- **Поточний TRL:** TRL 9 — всі контракти production-ready, готові до Mainnet deployment та зовнішнього аудиту
- **SCC контракт:** ✅ Production-ready (MAX_SUPPLY=1B, MINTER/SLASHER split, ReentrancyGuard, NatSpec, PremiumPaid event, mintForTree alias, audit hardening, slash bypasses pause, admin protection, locked pragma)
- **SFC контракт:** ✅ Production-ready (MAX_SUPPLY=100M, SLASHER_ROLE + slash(), ReentrancyGuard, NatSpec, slash bypasses pause, auto-delegation, admin protection, locked pragma)
- **Аудит-зміцнення:** ✅ Явна перевірка балансу в `slash()`, валідація нульових значень у `mint()`/`slash()`, перевірка порожнього батчу у `batchMint()`, NatSpec, захист від The Graph DoS (`treeDid`/`clusterId` length ≤256 bytes), валідація `recordPremiumPaid()`, per-element string validation у `batchMint()` для обох контрактів
- **Зовнішній аудит (19 findings):** ✅ Аналіз 19 знахідок: 9 виправлено on-chain (slash bypass pause, admin protection, auto-delegate, batch size 100, anchor interval, locked pragma, mint dedup, rootHistory, timestamp NatSpec), 10 задокументовано як operational/by-design
- **Backend інтеграція:** ✅ `BlockchainMintingService` + `BlockchainBurningService`
- **The Graph subgraph:** ✅ `TokenSlashed` виправлено, `PremiumPaid` додано, `treeDidHash` (bytes32) додано. ✅ SFC: `ForestMintEvent` + `GovernanceSlashEvent` + handlers додано (Sprint 3, S3.5). ⚠️ SFC contract address — placeholder до Mainnet deploy.
- **Відкрите:** SFC contract address placeholder до Mainnet deploy; зовнішній аудит execution → [`09_06`](09_06_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [05_01_Multichain_Architecture](05_01_Multichain_Architecture) | Мультичейн (Polygon у стеку) |
| [05_02_Proof_of_Growth_Pipeline](05_02_Proof_of_Growth_Pipeline) | Pipeline (мінтинг-тригер) |
| [04_02_Business_Logic_and_Services](04_02_Business_Logic_and_Services) | `BlockchainMinting`/`BlockchainBurning` сервіси |
| [09_06_Action_Plan_Tracker](09_06_Action_Plan_Tracker) | Open backlog (Mainnet deploy, audit) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Dual Token System (Архітектура)](#-dual-token-system-архітектура)
- [OpenZeppelin — Успадковані Стандарти](#-openzeppelin--успадковані-стандарти)
- [Ієрархія Ролей (AccessControl)](#-ієрархія-ролей-accesscontrol)
- [Функції Контрактів](#-функції-контрактів)
- [Події (Events)](#-події-events)
- [Dynamic Tax — HYBRID PROTOCOL GAIA](#-dynamic-tax--hybrid-protocol-gaia)
- [Потік Мінтингу (Поточний Стан)](#-потік-мінтингу-поточний-стан)
- [Потік Slashing (Поточний Стан)](#-потік-slashing-поточний-стан)
- [Зв'язок з Rails Backend](#-звязок-з-rails-backend)
- [Subgraph (The Graph)](#-subgraph-the-graph)
- [Зовнішні Залежності](#-зовнішні-залежності)
- [Структура Файлів (File Map)](#-структура-файлів-file-map)
- [Governance DAO (Законодавча Гілка Влади) → 05_06](#-governance-dao-законодавча-гілка-влади--05_06)
- [Smart Contract Audit Roadmap](#-smart-contract-audit-roadmap)
- [Посмертна Економіка — Інтеграція Puro.earth Biochar](#-посмертна-економіка--інтеграція-puroearth-biochar)
<!-- TOC:AUTO:END -->

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
| **Pragma** | `0.8.28` (locked) | `0.8.28` (locked) |
| **Максимальна емісія** | ✅ `MAX_SUPPLY = 1_000_000_000 SCC` | ✅ `MAX_SUPPLY = 100_000_000 SFC` |
| **Slash / Burn** | ✅ `slash()` через `SLASHER_ROLE` | ✅ `slash()` через `SLASHER_ROLE` (B-06 виправлено) |
| **Gasless approvals** | ✅ EIP-2612 / EIP-712 (PR #253) | ✅ EIP-2612 / EIP-712 |
| **DAO голосування** | ❌ | ✅ `ERC20Votes` |
| **Subgraph індексація** | ✅ `CarbonMinted`, ✅ `TokenSlashed`, ✅ `PremiumPaid` | ✅ `ForestMintEvent`, ✅ `GovernanceSlashEvent` (⚠️ contract address placeholder) |

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
| `Pausable` | Екстрене заморожування всіх трансферів (override `_update`). Аварійна зупинка через `pause()` / `unpause()` |
| `ERC20Permit` | **[PR #253]** Gasless approvals через EIP-2612 / EIP-712 підписи (`permit()`). Дозволяє DEX/P2P marketplace інтеграцію без газу для власників SCC. `nonces(address)` override для MRO сумісності з Nonces. |

### SilkenForestCoin (SFC)

```solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract SilkenForestCoin is ERC20, AccessControl, Pausable, ReentrancyGuard, ERC20Permit, ERC20Votes { ... }
```

| Базовий контракт | Призначення |
|---|---|
| `ERC20` | Стандартний fungible token |
| `AccessControl` | Ієрархія ролей |
| `Pausable` | Аварійна зупинка |
| `ReentrancyGuard` | Превентивний захист від reentrancy атак |
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

### 🔐 Admin-Role → Gnosis Safe [SEC.1]

`DEFAULT_ADMIN_ROLE` (SCC, SFC, StateRootAnchor, SilkenTimelock, ProtocolParameters) дає повний контроль (pause, видача/відкликання ролей). У production він **мусить** належати **Gnosis Safe multisig (3/5 або 2/3)**, не EOA.

**Контракти ще ніде не задеплоєно → міграція ролей не потрібна;** admin виставляється правильно одразу на genesis-деплої через `ADMIN_ADDRESS`:

| Крок | Дія |
|------|-----|
| 1 | Створити Gnosis Safe (3/5 або 2/3) на Polygon — `app.safe.global` |
| 2 | `ADMIN_ADDRESS=<Safe>` у deploy ENV |
| 3 | `REQUIRE_SAFE_ADMIN=true` (mainnet) → `Deploy.s.sol` hard-fail якщо admin = EOA |
| 4 | `forge script script/Deploy.s.sol --rpc-url $RPC --broadcast` |
| 5 | Верифікація (нижче) |

**Guard у `Deploy.s.sol` [SEC.1]:** при `REQUIRE_SAFE_ADMIN=true` деплой ревертиться, якщо `ADMIN_ADDRESS` — EOA (`admin.code.length == 0`); інакше — warning (testnet/local EOA допустимо).

**Last-admin guard (код SCC/SFC):** `_revokeRole` блокує видалення останнього `DEFAULT_ADMIN_ROLE` (`require(_adminCount > 1)`) — захист від lockout (релевантно лише при майбутньому reassign на live-контракті: grant-before-renounce).

**Верифікація (`cast`):**
```bash
ADMIN=0x0000000000000000000000000000000000000000000000000000000000000000  # DEFAULT_ADMIN_ROLE
cast call $SCC "hasRole(bytes32,address)(bool)" $ADMIN $SAFE      # → true
cast call $SCC "hasRole(bytes32,address)(bool)" $ADMIN $DEPLOYER  # → false
# повторити для $SFC, $ANCHOR, $TIMELOCK, $PROTOCOL_PARAMS
```

> `MINTER_ROLE` / `SLASHER_ROLE` належать backend-оракулам (operational, не admin) — нормально. `ProtocolParameters` керується `SilkenTimelock` (DAO).

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
    _mintSCC(to, amount, treeDid);
}
```

| Параметр | Тип | Опис |
|---|---|---|
| `to` | `address` | Адреса інвестора / власника дерева |
| `amount` | `uint256` | Кількість у wei (1 SCC = 10^18 wei) |
| `treeDid` | `string` | DID дерева (напр. `SNET-00A1B2C3`), max 256 bytes |

- **Модифікатор:** `onlyRole(MINTER_ROLE)`, `nonReentrant`
- **Делегує до:** `_mintSCC()` — внутрішня реалізація, спільна з `mintForTree()`
- **Guard on pause:** Опосередковано через `_update` — мінтинг блокується при паузі, слешинг дозволений
- **Виклик з бекенду:** `BlockchainMintingService` → `client.transact(contract, "mintForTree", to, amount, identifier)` (також доступний `"mint"` alias)

#### `_mintSCC(address to, uint256 amount, string calldata treeDid)` — internal

```solidity
function _mintSCC(address to, uint256 amount, string calldata treeDid) internal {
    require(to != address(0), "SCC: zero recipient");
    require(amount > 0, "SCC: zero amount");
    require(bytes(treeDid).length > 0, "SCC: empty treeDid");
    require(bytes(treeDid).length <= 256, "SCC: treeDid too long");
    require(totalSupply() + amount <= MAX_SUPPLY, "SCC: cap exceeded");
    _mint(to, amount);
    emit CarbonMinted(to, amount, keccak256(bytes(treeDid)), treeDid);
}
```

- **Призначення:** Усунення дублювання коду між `mint()` та `mintForTree()`. Будь-які зміни валідації або логіки застосовуються до обох entry points одночасно.
- **Валідація:** `to != address(0)`, `amount > 0`, `treeDid` не порожній, `treeDid` ≤ 256 bytes (The Graph safety), `totalSupply() + amount <= MAX_SUPPLY` (revert: `"SCC: cap exceeded"`)

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
- **Валідація:** `length > 0` (revert: `"SCC: empty batch"`); рівність довжин масивів; `MAX_BATCH_SIZE = 100` — захист від gas overflow (зменшено з 200 після аудиту для гарантії gas safety з максимальними рядками 256 bytes); кожен `recipient != address(0)`, `amount > 0`, `treeDid` не порожній, `treeDid` ≤ 256 bytes; `totalSupply() + batchTotal <= MAX_SUPPLY` перевіряється атомарно до мінтингу
- **Dynamic Tax:** При виклику `batchMint` з бекенду, `BlockchainMintingService` вставляє додаткових отримувачів (`DAO_TREASURY_ADDRESS`) коли баланс Treasury < 100,000 SCC
- **Gas Optimization [PR #253]:** `Treasury::MintBatchCollectorService` (cron кожні 5 хв) агрегує pending TX та відправляє пакетами по 100 через `BlockchainMintingService.call_batch`. `batchMint(100) ≈ 30-40%` дешевше ніж `100 × mint()`. Urgent TX (>30 хв) відправляються негайно.
- **Gas Analysis:** `MAX_BATCH_SIZE = 100` — on-chain safety cap (і backend, і контракт обмежують до 100). Gas consumption для 100 мінтів з максимальними DID (~256 bytes): ~10M gas — в межах Polygon block gas limit (30M). Solidity 0.8+ забезпечує вбудований overflow-захист для `batchTotal += amounts[i]` (revert `Panic(0x11)` при переповненні).
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
- **Guard on pause:** Слешинг **НЕ блокується** при паузі — `_update` дозволяє `_burn()` (to == address(0)) навіть коли контракт призупинено. Це запобігає governance attack vector де адмін захищає порушників від слешингу.
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
{
    // Allow burn (slash) to bypass pause — to == address(0) means _burn() was called.
    // Minting (from == 0, to != 0) and transfers (from != 0, to != 0) are still blocked.
    if (paused() && to != address(0)) {
        revert EnforcedPause();
    }
    super._update(from, to, value);
}
```

- Блокує мінтинг і трансфери при активній паузі, але **дозволяє burn (slash)** — слешинг є механізмом безпеки, який не повинен блокуватись адміном
- Reentrancy protection забезпечується `nonReentrant` guards на `mint()`, `mintForTree()`, `slash()`, `batchMint()` — `nonReentrant` не може бути доданий сюди напряму (вкладений виклик спричинив би revert)

#### Admin Protection — `_grantRole` / `_revokeRole` overrides

- `_adminCount` лічильник інкрементується при `_grantRole(DEFAULT_ADMIN_ROLE)` і декрементується при `_revokeRole(DEFAULT_ADMIN_ROLE)`
- `_revokeRole` блокує видалення останнього адміна: `require(_adminCount > 1, "SCC: cannot remove last admin")`
- Захищає від `renounceRole()` і `revokeRole()` — обидва проходять через `_revokeRole` internal

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
    // Auto-delegate to self if not yet delegated
    if (delegates(to) == address(0)) {
        _delegate(to, to);
    }
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
- **Auto-delegation:** При першому мінті для адреси автоматично делегує voting power до самого себе (`_delegate(to, to)`). Без цього ERC20Votes вимагає явний `delegate()` виклик, і більшість отримувачів не знатимуть про необхідність делегації, що призводить до штучно низького governance quorum.
- **Guard on pause:** Мінтинг блокується при паузі через `_update`, слешинг дозволений
- **Виклик з бекенду:** `BlockchainMintingService` — однакова логіка з SCC, але `token_type == "forest_coin"` → `FOREST_COIN_CONTRACT_ADDRESS`

#### `batchMint(address[] calldata recipients, uint256[] calldata amounts, string[] calldata clusterIds)`

- Аналогічний SCC `batchMint`, але прив'язаний до `clusterId` замість `treeDid`
- Модифікатор: `onlyRole(MINTER_ROLE)`, `nonReentrant`; перевіряє `length > 0`, рівність масивів, `MAX_BATCH_SIZE = 100`; per-element: `recipient != address(0)`, `amount > 0`, `clusterId` не порожній, `clusterId` ≤ 256 bytes; `totalSupply() + batchTotal <= MAX_SUPPLY` атомарно
- **Auto-delegation:** Як і в `mint()`, автоматично делегує voting power при першому мінті для кожної адреси

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
- **Guard on pause:** Слешинг **НЕ блокується** при паузі — `_update` дозволяє `_burn()` навіть коли контракт призупинено. Видалення voting power у порушників має бути завжди можливим.
- **Подія:** `GovernanceSlashed(address indexed investor, uint256 amount)`

#### `_update(address from, address to, uint256 value)` — internal override

```solidity
function _update(address from, address to, uint256 value)
    internal
    override(ERC20, ERC20Votes)
{
    if (paused() && to != address(0)) {
        revert EnforcedPause();
    }
    super._update(from, to, value);
}
```

- Override необхідний через конфлікт між `ERC20` та `ERC20Votes`
- Блокує мінтинг і трансфери при паузі, але **дозволяє burn (slash)** — уніфіковано з SCC патерном
- Reentrancy protection забезпечується `nonReentrant` guards на `mint()`, `slash()`, `batchMint()` — `nonReentrant` не може бути доданий сюди напряму (вкладений виклик спричинив би revert)

#### Admin Protection — `_grantRole` / `_revokeRole` overrides

- Аналогічно SCC: `_adminCount` лічильник захищає від видалення останнього `DEFAULT_ADMIN_ROLE`
- `require(_adminCount > 1, "SFC: cannot remove last admin")`

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
| `ForestMinted` | `ForestMinted(address indexed investor, uint256 amount, bytes32 indexed clusterIdHash, string clusterId)` | `investor`, `clusterIdHash` (bytes32 keccak256) | ✅ `handleForestMinted` (⚠️ contract address placeholder `0x0000...`) |
| `GovernanceSlashed` | `GovernanceSlashed(address indexed investor, uint256 amount)` | `investor` | ✅ `handleGovernanceSlashed` (⚠️ contract address placeholder) |

### Subgraph vs Контракт — Повна Матриця

| Event у subgraph.yaml | Подія у контракті | Статус |
|---|---|---|
| `CarbonMinted(indexed address,uint256,indexed bytes32,string)` | `CarbonMinted` | ✅ `treeDidHash` (bytes32) |
| `TokenSlashed(indexed address,uint256)` | `TokenSlashed` | ✅ Синхронізовано |
| `PremiumPaid(indexed address,uint256)` | `PremiumPaid` | ✅ Event + handler додано |
| `ForestMinted(indexed address,uint256,indexed bytes32,string)` | `ForestMinted` (SFC) | ✅ Handler додано (Sprint 3, S3.5) |
| `GovernanceSlashed(indexed address,uint256)` | `GovernanceSlashed` (SFC) | ✅ Handler додано (Sprint 3, S3.5) |

> ⚠️ SFC data source в `subgraph.yaml` використовує placeholder `0x0000000000000000000000000000000000000000` — блокує deploy subgraph до Mainnet. Замінити після деплою SFC контракту.

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

> **⚠️ [Lorenz de-risk]** Перший крок потоку (`Lorenz Z-value → growth_points`) спирається на **недоведену гіпотезу** «Z = здоров'я» ([`05_05 §8`](05_05_Slashing_and_Risk_Policy)). Slashing/мінтинг-рішення вимагають ≥1 прямого сигналу (sap_flow / VPD / acoustic), не лише Z ([`05_05 §7`](05_05_Slashing_and_Risk_Policy)). Lorenz-DCI (anti-fraud) валідний незалежно.

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

# SCC data source
- event: CarbonMinted(indexed address,uint256,indexed bytes32,string)
  handler: handleCarbonMinted           # ✅ treeDidHash як bytes32

- event: TokenSlashed(indexed address,uint256)
  handler: handleTokenSlashed           # ✅ Синхронізовано з контрактом

- event: PremiumPaid(indexed address,uint256)
  handler: handlePremiumPaid            # ✅ Event додано до контракту

# SFC data source (додано Sprint 3, S3.5)
- event: ForestMinted(indexed address,uint256,indexed bytes32,string)
  handler: handleForestMinted           # ✅ clusterIdHash як bytes32

- event: GovernanceSlashed(indexed address,uint256)
  handler: handleGovernanceSlashed      # ✅ Governance slashing tracking
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
  totalBurned: BigInt!           # ✅ Індексується через TokenSlashed (SCC)
  totalPremiums: BigInt!         # ✅ Індексується через PremiumPaid
  totalForestMinted: BigInt!     # ✅ Індексується через ForestMinted (SFC)
  totalGovernanceSlashed: BigInt! # ✅ Індексується через GovernanceSlashed (SFC)
}
```

---

## 🌍 Зовнішні Залежності

| Параметр | Значення |
|---|---|
| **Мережа** | Polygon PoS (Amoy testnet → Mainnet) |
| **Toolchain** | Foundry (forge, cast, anvil) |
| **OpenZeppelin** | 5.6.x (`pragma solidity 0.8.28` — locked) |
| **RPC** | `ALCHEMY_POLYGON_RPC_URL` (через `Web3::RpcConnectionPool`) |
| **Oracle wallet** | `ORACLE_MINTER_PRIVATE_KEY` (MINTER_ROLE) + `ORACLE_SLASHER_PRIVATE_KEY` (SLASHER_ROLE) — окремі ключі |
| **The Graph** | `subgraph/` — SCC та SFC events індексуються (⚠️ SFC: contract address placeholder) |
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
├── StateRootAnchor.sol               # Ethereum L1 state root anchoring (weekly finality)
├── SilkenGovernor.sol                # ✅ [ARCH.4] DAO Governor (OZ Governor + TimelockControl + flash loan defense)
├── SilkenTimelock.sol                # ✅ [ARCH.4] TimelockController (48h min delay)
└── ProtocolParameters.sol            # ✅ [ARCH.4] On-chain protocol parameter registry (governance-controlled)

app/services/
├── blockchain_minting_service.rb     # SCC + SFC mint / batchMint + Dynamic Tax
└── blockchain_burning_service.rb     # SCC slash + SFC slash

app/workers/
├── mint_carbon_coin_worker.rb        # queue: web3_critical, retry: 5
├── burn_carbon_tokens_worker.rb      # queue: critical, retry: 5
├── blockchain_confirmation_worker.rb # queue: web3_critical, retry: 5
├── tokenomics_evaluator_worker.rb    # cron: 0 * * * *, queue: default
└── governance/
    └── parameter_sync_worker.rb      # ✅ [ARCH.4] queue: web3_low, cron: 0 3 * * *, sync on-chain → SystemParameter

subgraph/
├── schema.graphql                    # CarbonMintEvent (treeDidHash), SlashingEvent, ProtocolFinancials
├── subgraph.yaml                     # ✅ PremiumPaid handler (event додано до контракту)
└── src/mapping.ts                    # handleCarbonMinted, handleTokenSlashed, handlePremiumPaid

spec/services/
├── blockchain_minting_service_spec.rb
└── blockchain_burning_service_spec.rb

spec/workers/governance/
└── parameter_sync_worker_spec.rb  # ✅ [ARCH.4] RSpec тести для governance sync worker

contracts/test/
├── SilkenCarbonCoin.t.sol           # ✅ Foundry тести SCC (mint, slash, batchMint, access control, pause)
├── SilkenForestCoin.t.sol           # ✅ Foundry тести SFC (mint, slash, votes, delegation, governance)
├── StateRootAnchor.t.sol            # ✅ Foundry тести L1 anchor (store, interval, dedup, admin)
├── SilkenGovernor.t.sol             # ✅ [ARCH.4] Foundry тести Governor (propose, vote, execute, quorum)
├── SilkenTimelock.t.sol             # ✅ [ARCH.4] Foundry тести Timelock (delay, roles, scheduling)
└── ProtocolParameters.t.sol         # ✅ [ARCH.4] Foundry тести registry (set, batch, access, defaults)

contracts/foundry.toml               # ✅ Foundry config: solc 0.8.28, EVM cancun, profiles (default/ci/production)
```

---

## 🗳️ Governance DAO (Законодавча Гілка Влади) → 05_06

On-chain governance (SFC-голосування за протокольні параметри: Lorenz σ/ρ/β, slashing-пороги, tokenomics-курс) виокремлено у власний дім — [`05_06 Governance & DAO`](05_06_Governance_and_DAO). Там: `SilkenGovernor` / `SilkenTimelock` / `ProtocolParameters`, Flash-Loan-захист, Apex Predator Defense, governance-aware backend (`SystemParameter` / `Governance::ParameterSyncWorker`). База — SFC `ERC20Votes` (§SFC — Ролі вище).

## 🔍 Smart Contract Audit Roadmap

### Етапи аудиту перед Mainnet Deployment

| Фаза | Інструмент / Постачальник | Тип | Коли | Статус |
|------|--------------------------|-----|------|--------|
| **1. Automated Static Analysis** | [Slither](https://github.com/crytic/slither) | Безкоштовний open-source | Зараз (CI/CD) | ✅ Реалізовано (Сесія 19): `.github/workflows/solidity_audit.yml` |
| **1b. Symbolic Execution** | [Mythril](https://github.com/Consensys/mythril) | Безкоштовний open-source | Зараз (CI/CD) | 🟡 TODO |
| **2. Manual Audit (Pre-Testnet)** | [Hacken](https://hacken.io/) або [Hashlock](https://hashlock.com/) | Платний аудит | Перед Amoy → Mainnet | 🔴 TODO |
| **3. Runtime Monitoring** | [CertiK Skynet](https://skynet.certik.com/) | 24/7 моніторинг | Після Mainnet deploy | 🔴 TODO |

**Scope аудиту (6 контрактів):**
1. `SilkenCarbonCoin.sol` — mint/burn/batchMint, MINTER/SLASHER roles
2. `SilkenForestCoin.sol` — governance token, ERC20Votes, slash
3. `StateRootAnchor.sol` — L1 finality, state root storage
4. `SilkenGovernor.sol` — ✅ DAO governance (OZ Governor, flash loan defense)
5. `SilkenTimelock.sol` — ✅ 48h TimelockController
6. `ProtocolParameters.sol` — ✅ On-chain parameter registry

**Slither в CI (✅ Реалізовано):**
```yaml
# .github/workflows/solidity_audit.yml
# Тригер: зміни в contracts/ на PR або push to main
# crytic/slither-action@v0.4.0, solc 0.8.28, fail-on: high
# OpenZeppelin 5.x через contracts/package.json
```

**Foundry Deploy Script (✅ Реалізовано — Сесія 23):**
```bash
# contracts/script/Deploy.s.sol — деплой всіх 6 контрактів у правильному порядку:
# 1. SCC → 2. SFC → 3. StateRootAnchor → 4. Timelock → 5. Governor → 6. ProtocolParameters
# Потрібні ENV: DEPLOYER_PRIVATE_KEY, ADMIN_ADDRESS, MINTER_ORACLE, SLASHER_ORACLE, ANCHOR_ORACLE
# Dry-run: forge script script/Deploy.s.sol --rpc-url $RPC_URL
# Broadcast: FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

**Mythril (TODO):**
```bash
myth analyze contracts/SilkenCarbonCoin.sol --solv 0.8.28
```

**Operational Security (production):**
- `DEFAULT_ADMIN_ROLE` → Gnosis Safe multisig (3/5 або 2/3) — **TODO** (SEC.1)
- `MINTER_ROLE` / `SLASHER_ROLE` → окремі Oracle EOA (✅ реалізовано, E.2)
- `pause()` → без timelock (потрібна миттєва реакція при exploits)
- Всі інші governance-зміни → через Timelock 48h

---

## ♻️ Посмертна Економіка — Інтеграція Puro.earth Biochar

Коли дерево помирає (природна смерть або катастрофічна подія), його біомаса зберігає економічну цінність через Biochar carbon removal credits (CORCs) на реєстрі [Puro.earth](https://puro.earth).

### Потік

```
Дерево помирає → Лісник видобуває мертву деревину → MaintenanceRecord (biomass_extraction)
         ↓
EcosystemHealingWorker → статус дерева → :deceased
         ↓
PuroEarthPassportWorker → генерація D-MRV "Паспорт Біомаси"
         ↓
Payload: { tree_did, biomass_yield_kg, extraction_date, gps_coordinates, lifetime_telemetry_hash }
         ↓
Phase 1: blockchain anchoring → biomass_passport_tx_hash збережено в MaintenanceRecord
         ↓
Phase 2: REST API submission → Puro.earth → puro_earth_corc_ref збережено в MaintenanceRecord
         ↓
Реєстр Puro.earth → видача Biochar CORC (автоматична інтеграція через RegistryApiService)
```

### D-MRV Паспорт Біомаси

D-MRV (Digital Measurement, Reporting and Verification) паспорт забезпечує захищений від підробки провенанс для видобутої біомаси:

| Поле | Джерело | Призначення |
|------|---------|-------------|
| `tree_did` | Tree.did (SNET-XXXXXXXX) | Унікальна апаратна ідентичність дерева-джерела |
| `biomass_yield_kg` | MaintenanceRecord | Вага видобутої мертвої деревини |
| `extraction_date` | MaintenanceRecord.performed_at | Timestamp фізичного видобутку |
| `gps_coordinates` | MaintenanceRecord або Tree | Географічне підтвердження походження |
| `lifetime_telemetry_hash` | SHA-256 від telemetry history | Tamper-proof зв'язок з сенсорними даними дерева |
| `puro_earth_corc_ref` | Puro.earth REST API response | CORC reference ID для відстеження сертифікації |

### Економічний Вплив

- Мертві дерева продовжують генерувати цінність через Biochar CORCs замість того, щоб бути відходами
- Кожен CORC представляє верифіковане видалення вуглецю (методологія Puro Standard)
- Lifetime telemetry hash гарантує, що біомаса походить з моніторованого, верифікованого дерева
- GPS-координати запобігають подвійному підрахунку між лісовими ділянками

> **Статус:** `PuroEarthPassportWorker` — у черзі `web3` (пріоритет 7). ✅ Повна інтеграція: on-chain anchoring (`PassportService`) + REST API submission (`RegistryApiService`). Двофазний pipeline: Phase 1 зберігає `biomass_passport_tx_hash`, Phase 2 зберігає `puro_earth_corc_ref`.
