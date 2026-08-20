# 05_03: Токеноміка — SCC & SFC (Смарт-контракти на Polygon)

## 🎯 Мета

Зафіксувати реальний стан («як є») смарт-контрактів токеноміки SilkenNet — `SilkenCarbonCoin` (SCC) та `SilkenForestCoin` (SFC). Документ описує стандарти токенів, ієрархію ролей, ключові функції, механізм Dynamic Tax, зв'язок з бекендом та повний перелік знайдених блокерів.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 (Module 05 Web3 — канон-матриця [`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond): поточний 8, ціль 9, гейт «SFC address»). Контракти code-complete, Foundry-tested, Slither + Aderyn + Halmos + Medusa у CI — **готові до** testnet→mainnet deploy + зовнішнього аудиту. TRL 9 = mainnet-deployed ([`00_03`](00_03_TRL_Matrix_HIL_and_Beyond): «TRL 9 → mainnet») — ще не досягнуто (placeholder-адреси, manual audit + Gnosis multisig = TODO).
- **SCC контракт:** ✅ Production-ready (MAX_SUPPLY=1B, MINTER/SLASHER split, ReentrancyGuard, NatSpec, mintForTree alias, audit hardening, slash bypasses pause, admin protection, locked pragma)
- **SFC контракт:** ✅ Production-ready (MAX_SUPPLY=100M, SLASHER_ROLE + slash(), ReentrancyGuard, NatSpec, slash bypasses pause, auto-delegation, admin protection, locked pragma)
- **Аудит-зміцнення:** ✅ Явна перевірка балансу в `slash()`, валідація нульових значень у `mint()`/`slash()`, перевірка порожнього батчу у `batchMint()`, NatSpec, захист від The Graph DoS (`treeDid`/`clusterId` length ≤256 bytes), per-element string validation у `batchMint()` для обох контрактів
- **Внутрішній аудит-розбір (self-review — НЕ платний зовнішній; Hacken/Hashlock ще 👤 TODO ↓):** ✅ знахідки самоаудиту опрацьовано — частину виправлено on-chain (slash-bypass-pause, admin-protection, auto-delegate, batch-size, anchor-interval, locked-pragma, mint-dedup, rootHistory, timestamp-NatSpec), решту задокументовано як operational/by-design (деталі → §Smart Contract Audit Roadmap)
- **Backend інтеграція:** ✅ `BlockchainMintingService` + `BlockchainBurningService`
- **The Graph subgraph:** ✅ `TokenSlashed` виправлено, `treeDidHash` (bytes32) додано. ✅ SFC: `ForestMintEvent` + `GovernanceSlashEvent` + handlers додано (S3.5). ⚠️ SFC contract address — placeholder до Mainnet deploy.
- **Відкрите:** SFC contract address placeholder до Mainnet deploy; зовнішній аудит execution → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) | Мультичейн (Polygon у стеку) |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Pipeline (мінтинг-тригер) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `BlockchainMinting`/`BlockchainBurning` сервіси |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (Mainnet deploy, audit) |

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

> **Чому власний токен (SCC), а не USDC?** USDC представляє **минулу** цінність (фіат); SCC — **майбутній верифікований ріст біомаси** (Proof of Growth). Ключове: власний ERC-20 дозволяє **алгоритмічний Slashing** — спалення токенів порушника при стійкому порушенні NaaS-контракту ([`05_05 §3`](05_05_Slashing_and_Risk_Policy)), чого зі стороннім стейблкоїном без централізованого контролю зробити **неможливо**. SCC + Slashing = trustless accountability учасників екосистеми (SFC аналогічно несе `slash()` для governance-порушень).

| Параметр | SCC — Silken Carbon Coin | SFC — Silken Forest Coin |
|---|---|---|
| **Тип** | Utility Token | Governance Token |
| **Ticker** | SCC | SFC |
| **Стандарти** | ERC-20 + AccessControl + Pausable + ERC20Permit | ERC-20 + AccessControl + Pausable + ERC20Permit + ERC20Votes |
| **Мережа** | Polygon (Amoy testnet → Mainnet) | Polygon (Amoy testnet → Mainnet) |
| **Файл** | `contracts/SilkenCarbonCoin.sol` | `contracts/SilkenForestCoin.sol` |
| **ENV адреса** | `CARBON_COIN_CONTRACT_ADDRESS` | `FOREST_COIN_CONTRACT_ADDRESS` |
| **Pragma** | `0.8.36` (locked) | `0.8.36` (locked) |
| **Максимальна емісія** | ✅ `MAX_SUPPLY = 1_000_000_000 SCC` — [CONTRACT.1] деривація: 10k GP=1 SCC · 2k SCC=1 tCO2 → ≈500k tCO2 ≈ 20M дерево-років (≈2M дерев × 10 р.) = свідомо-скромна launch-стеля pilot-горизонту; планетарний масштаб = новий деплой/L2, не підняття константи. **NB:** «2k SCC=1 tCO₂» = внутрішня облікова конвенція Proof-of-Growth/Condition-токена, НЕ registry-визнаний offset (продаваний кредит лише через незалежну методологію → [`07_01 §3`](07_01_Nature_as_a_Service_Contracts), [`00_07`](00_07_Action_Plan_Tracker) BIZ.9) | ✅ `MAX_SUPPLY = 100_000_000 SFC` |
| **Slash / Burn** | ✅ `slash()` + `slashUpTo()` [SLASH.2] через `SLASHER_ROLE` | ✅ `slash()` + `slashUpTo()` [SLASH.2] через `SLASHER_ROLE` (B-06 виправлено) |
| **Gasless approvals** | ✅ EIP-2612 / EIP-712 (PR #253) | ✅ EIP-2612 / EIP-712 |
| **DAO голосування** | ❌ | ✅ `ERC20Votes` |
| **Subgraph індексація** | ✅ `CarbonMinted`, ✅ `TokenSlashed` | ✅ `ForestMintEvent`, ✅ `GovernanceSlashEvent` (⚠️ contract address placeholder) |

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
| `DEFAULT_ADMIN_ROLE` | `0x00` (OpenZeppelin default) | `admin` — у production = **SilkenTimelock** (48h) | Видача / відкликання будь-яких ролей (у т.ч. `MINTER_ROLE`) — **за 48h-затримкою** [SEC.1] |
| `PAUSER_ROLE` | `keccak256("PAUSER_ROLE")` | `pauser` — у production = **Gnosis Safe** | `pause()`, `unpause()` — **миттєво, поза Timelock** [SEC.1] |
| `MINTER_ROLE` | `keccak256("MINTER_ROLE")` | `minterOracle` (окремий параметр) | `mintForTree()`, `mint()`, `batchMint()` |
| `SLASHER_ROLE` | `keccak256("SLASHER_ROLE")` | `slasherOracle` (окремий параметр) | `slash()` |

```solidity
constructor(address admin, address pauser, address minterOracle, address slasherOracle)
    ERC20("Silken Carbon Coin", "SCC")
    ERC20Permit("Silken Carbon Coin")
{
    require(admin != address(0), "SCC: zero admin");        // production: Timelock
    require(pauser != address(0), "SCC: zero pauser");      // production: Gnosis Safe [SEC.1]
    require(minterOracle != address(0), "SCC: zero minter oracle");
    require(slasherOracle != address(0), "SCC: zero slasher oracle");
    _grantRole(DEFAULT_ADMIN_ROLE, admin);   // 48h-gated role grants (Timelock)
    _grantRole(PAUSER_ROLE, pauser);         // instant emergency pause (Safe) [SEC.1]
    _grantRole(MINTER_ROLE, minterOracle);
    _grantRole(SLASHER_ROLE, slasherOracle);
}
```

### SFC — Ролі

| Роль | Константа | Призначається в конструкторі | Можливості |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | `0x00` | `admin` — у production = **SilkenTimelock** (48h) | Видача / відкликання ролей (у т.ч. `MINTER_ROLE`) — **за 48h-затримкою** [SEC.1] |
| `PAUSER_ROLE` | `keccak256("PAUSER_ROLE")` | `pauser` — у production = **Gnosis Safe** | `pause()`, `unpause()` — **миттєво, поза Timelock** [SEC.1] |
| `MINTER_ROLE` | `keccak256("MINTER_ROLE")` | `oracle` (параметр конструктора) | `mint()`, `batchMint()` |
| `SLASHER_ROLE` | `keccak256("SLASHER_ROLE")` | `slasherOracle` | `slash()` — спалення governance-токенів при breach |

```solidity
constructor(address admin, address pauser, address oracle, address slasherOracle)
    ERC20("Silken Forest Coin", "SFC")
    ERC20Permit("Silken Forest Coin")
{
    require(admin != address(0), "SFC: zero admin");        // production: Timelock
    require(pauser != address(0), "SFC: zero pauser");      // production: Gnosis Safe [SEC.1]
    require(oracle != address(0), "SFC: zero oracle");
    require(slasherOracle != address(0), "SFC: zero slasher oracle");
    _grantRole(DEFAULT_ADMIN_ROLE, admin);   // 48h-gated role grants (Timelock)
    _grantRole(PAUSER_ROLE, pauser);         // instant emergency pause (Safe) [SEC.1]
    _grantRole(MINTER_ROLE, oracle);
    _grantRole(SLASHER_ROLE, slasherOracle);
}
```

### Матриця Дозволів

_[SEC.1] PAUSER (Safe) ≠ ADMIN (Timelock): pause — швидко; видача ролей — за 48h._

| Дія | SCC MINTER | SCC SLASHER | SCC PAUSER | SCC ADMIN | SFC MINTER | SFC SLASHER | SFC PAUSER | SFC ADMIN |
|---|---|---|---|---|---|---|---|---|
| `mintForTree()` / `mint()` SCC | ✅ | ❌ | ❌ | ❌ | — | — | — | — |
| `batchMint()` SCC | ✅ | ❌ | ❌ | ❌ | — | — | — | — |
| `slash()` SCC | ❌ | ✅ | ❌ | ❌ | — | — | — | — |
| `pause()` / `unpause()` SCC | ❌ | ❌ | ✅ | ❌ | — | — | — | — |
| Видача ролей SCC | ❌ | ❌ | ❌ | ✅ | — | — | — | — |
| `mint()` SFC | — | — | — | — | ✅ | ❌ | ❌ | ❌ |
| `batchMint()` SFC | — | — | — | — | ✅ | ❌ | ❌ | ❌ |
| `slash()` SFC | — | — | — | — | ❌ | ✅ | ❌ | ❌ |
| `pause()` / `unpause()` SFC | — | — | — | — | ❌ | ❌ | ✅ | ❌ |
| Видача ролей SFC | — | — | — | — | ❌ | ❌ | ❌ | ✅ |

---

### 🔐 Admin-Role Split: Timelock + Safe + PAUSER [SEC.1]

**Загроза:** `DEFAULT_ADMIN_ROLE` може `grantRole(MINTER_ROLE, …)` → намінтити до `MAX_SUPPLY`. Якщо він у EOA/Safe **без затримки**, скомпрометований ключ дає миттєвий катастрофічний mint. Тому SCC/SFC рознесено на дві осі:

| Роль | Власник (production) | Швидкість | Що тримає |
|------|----------------------|-----------|-----------|
| `DEFAULT_ADMIN_ROLE` | **SilkenTimelock** (48h) | повільно | видача/відкликання будь-якої ролі (у т.ч. MINTER) — публічна 48h-затримка → час на veto/alert |
| `PAUSER_ROLE` | **Gnosis Safe** (3/5 або 2/3) | миттєво | `pause()`/`unpause()` — негайна реакція на exploit (поза Timelock) |

Тобто **навіть multisig не може миттєво намінтити** — `grantRole(MINTER)` мусить пройти 48h-Timelock; pause лишається швидким (`SilkenTimelock.sol` явно декларує цей намір — «pause НЕ через Timelock»).

**Контракти ще ніде не задеплоєно → міграція ролей не потрібна;** ролі виставляються одразу на genesis (`Deploy.s.sol`):

| Крок | Дія |
|------|-----|
| 1 | Створити Gnosis Safe (3/5 або 2/3) на Polygon — `app.safe.global` |
| 2 | `ADMIN_ADDRESS=<Safe>` у deploy ENV (= token PAUSER + Timelock admin); `DAO_TREASURY_ADDRESS=<Safe>` (скарбниця: Dynamic-Tax + INS.2-резерв — on-chain ролі не має, лише custody-гейт) |
| 3 | `REQUIRE_SAFE_ADMIN=true` (mainnet) → деплой hard-fail якщо `ADMIN_ADDRESS` **або** `DAO_TREASURY_ADDRESS` = EOA |
| 4 | `forge script script/Deploy.s.sol --rpc-url $RPC --broadcast` |
| 5 | Верифікація (нижче) |

**Deploy-послідовність [SEC.1]:** Timelock деплоїться **першим** (deployer = тимчасовий admin) → токени з `admin=Timelock`, `pauser=Safe` → Anchor/Governor/Params → wire Timelock-ролей (Governor = PROPOSER+CANCELLER; **Safe = PROPOSER** — bootstrap: може *планувати* `grantRole(MINTER)` з 48h-затримкою до активації DAO) → передати Timelock-admin Safe + **renounce deployer** (deployer лишається без жодної ролі). StateRootAnchor admin = Timelock теж (uniform «admin=Timelock, окрім pause»): контракт не має `pause()`, а видача `ANCHOR_ROLE` — management-влада, не аварійне гальмо → governance-gated; 6-денний `MIN_ANCHOR_INTERVAL` + off-chain верифікація root роблять повільніше (48h) oracle-rotation некритичним (low-sev). **ProtocolParameters admin = Timelock** (як токени, 2026-06-15): DEFAULT_ADMIN не може `grantRole(GOVERNANCE_ROLE, self)` в обхід 48h → зміна економічних параметрів (dynamic-tax / slash-curve / fallback-ціна, які бекенд читає через `SystemParameter`) теж за 48h-veto, тобто [E.35] правда як написано.

**Guard у `Deploy.s.sol`:** при `REQUIRE_SAFE_ADMIN=true` деплой ревертиться, якщо custody-адреса — EOA (`code.length == 0`); інакше — warning (testnet/local EOA допустимо). Один прапор гейтить **обидві** custody-адреси: `ADMIN_ADDRESS` (ролі: PAUSER + Timelock-admin) і `DAO_TREASURY_ADDRESS` (кошти: отримувач Dynamic-Tax + резерв INS.2 — reserve-adequacy проти EOA-скарбниці була б театром; on-chain ролі адреса не має, тож deploy-гейт = її єдина custody-перевірка). Той самий прапор hard-fail'ить і **сколапсований E.2 key-split** (`MINTER_ORACLE == SLASHER_ORACLE` — конструктори токенів приймають два oracle-параметри, але не перевіряють що вони різні; backend `Web3NetworkGuard` ловить однакові ключі лише на Sidekiq-boot, ПІСЛЯ незворотного on-chain гранту з 48h-Timelock unwind). Пін усіх трьох гейтів: `testRevert_run_mainnetSafetyGates` (`Deploy.t.sol`).

**Last-admin guard (код SCC/SFC):** `_revokeRole` блокує видалення останнього `DEFAULT_ADMIN_ROLE` (`require(_adminCount > 1)`) — захист від lockout (останній admin = Timelock).

**Операційна реальність (solo-founder):** «3/5 multisig», де всі ключі в однієї особи = театр; справжній Safe потребує зовнішніх co-signer'ів (HW-wallet'и + social recovery). Bootstrap-PROPOSER Safe + Timelock-admin renounce-аються на `address(0)`, коли DAO активний з реальними виборцями. → [`00_07` — SEC.1](00_07_Action_Plan_Tracker).

**Верифікація (`cast`):**
```bash
ADMIN=0x0000000000000000000000000000000000000000000000000000000000000000  # DEFAULT_ADMIN_ROLE
cast call $SCC "hasRole(bytes32,address)(bool)" $ADMIN $SAFE      # → true
cast call $SCC "hasRole(bytes32,address)(bool)" $ADMIN $DEPLOYER  # → false
# повторити для $SFC, $ANCHOR, $TIMELOCK, $PROTOCOL_PARAMS

# On-chain grant ↔ backend signer: деплой грантить ролі адресам X, backend підписує ключами Y —
# розбіжність self-reveals лише AccessControl-revert'ом на ПЕРШОМУ mint/slash, тому звір явно:
cast call $SCC "hasRole(bytes32,address)(bool)" $(cast keccak "MINTER_ROLE")  $(cast wallet address --private-key $ORACLE_MINTER_PRIVATE_KEY)   # → true
cast call $SCC "hasRole(bytes32,address)(bool)" $(cast keccak "SLASHER_ROLE") $(cast wallet address --private-key $ORACLE_SLASHER_PRIVATE_KEY)  # → true
```

> `MINTER_ROLE` / `SLASHER_ROLE` належать backend-оракулам (operational, не admin) — нормально. `ProtocolParameters` **повністю** керується `SilkenTimelock` — і `GOVERNANCE_ROLE` (зміна параметрів), і `DEFAULT_ADMIN` (видача ролей) → обидва за 48h (Safe НЕ admin Params).

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
- **Виклик з бекенду:** `BlockchainMintingService` → `client.transact(contract, "mint", to, amount, identifier)` — контракт експонує і `mintForTree()`, і `mint()` alias, але бекенд-ABI (`CONTRACT_ABI`) реєструє лише `"mint"` + `"batchMint"`

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
    // Manual DAO/Timelock-шлях — без бекенд-інтенту, contextHash порожній.
    emit TokenSlashed(investor, amount, bytes32(0));
}
```

- **Модифікатор:** `onlyRole(SLASHER_ROLE)`, `nonReentrant`
- **Валідація:** `investor != address(0)`, `amount > 0`, `balanceOf(investor) >= amount` (revert: `"SCC: insufficient balance"`) — явна перевірка замість generic OZ помилки
- **Тригер:** `BurnCarbonTokensWorker → BlockchainBurningService → slash(investor, amount)` — health-check `>20%` аномальних дерев лише **ініціює** перевірку; реальний slash проходить тільки за positive-A-evidence gate ([`05_05 §3.2`](05_05_Slashing_and_Risk_Policy)), інакше `:frozen` + Field Audit.
- **Guard on pause:** Слешинг **НЕ блокується** при паузі — `_update` дозволяє `_burn()` (to == address(0)) навіть коли контракт призупинено. Це запобігає governance attack vector де адмін захищає порушників від слешингу.
- **Подія:** `TokenSlashed(address indexed investor, uint256 amount, bytes32 contextHash)` — manual `slash()` емітить `bytes32(0)`; [CONTRACT.1]-атрибуція живе у `slashUpTo` ↓
- **[ARCH.45] Idempotency на crash-window:** on-chain `require(balanceOf >= amount)` — лише **латентний частковий** захист (повторний slash на ту саму суму ревертне, якщо перший зменшив баланс; але при `damage_ratio < 1` баланс може лишитись достатнім → частковий double-burn). Exactly-once гарантує backend: durable intent-marker + `BlockchainTransaction.in_flight` guard у `BlockchainBurningService` ([`04_02 §4`](04_02_Business_Logic_and_Services)), не явний on-chain nonce/marker.

#### `slashUpTo(address investor, uint256 maxAmount, bytes32 contextHash) → uint256 slashed` [SLASH.2]

```solidity
function slashUpTo(address investor, uint256 maxAmount, bytes32 contextHash)
    external
    onlyRole(SLASHER_ROLE)
    nonReentrant
    returns (uint256 slashed)
{
    require(investor != address(0), "SCC: zero investor");
    require(maxAmount > 0, "SCC: zero amount");
    slashed = balanceOf(investor);
    if (slashed > maxAmount) slashed = maxAmount;
    require(slashed > 0, "SCC: nothing to slash");
    _burn(investor, slashed);
    emit TokenSlashed(investor, slashed, contextHash);
}
```

- **Навіщо (SLASH.2):** бекенд рахує `burn_amount` з **pre-tax** суми намінтованого, а порушник on-chain тримає менше (DynamicTax пішов у treasury; SCC вільно переказуваний). Строгий `slash(amount)` тоді **revert-ив** (`balanceOf < amount`) — покарання тихо не застосовувалось; переказ 1 wei перед транзакцією Оракула скасовував би **повний** slash (evasion). `slashUpTo` палить `min(maxAmount, balanceOf)` **атомарно** — clamp замість revert, TOCTOU-safe (дрейф балансу лише зменшує спалене).
- **Виконавець (backend):** `BlockchainBurningService` кличе `slashUpTo` (не `slash`) + pre-read `balanceOf` для (1) чесного обліку (`effective_burn = min(burn, balance)` в intent/метриці) і (2) tripwire на **повне** виведення (balance ≈ 0 → `escalate_evasion!` → `:evaded` + Field Audit, юридичний трек, БЕЗ приреченої revert-tx). Дім — [`05_05 §3.2`](05_05_Slashing_and_Risk_Policy).
- **Валідація:** `investor != address(0)`, `maxAmount > 0`, `balanceOf > 0` (revert: `"SCC: nothing to slash"` — повне виведення бекенд ескалює як evasion). **Пауза не блокує** (той самий `_burn`-bypass, що `slash()`). Подія — `TokenSlashed(investor, slashed, contextHash)` з **фактично** спаленою сумою. Доведено Halmos (`check_slashUpTo_clampsToBalance`) + Medusa (`property_supplyAccounting`).
- **[CONTRACT.1] `contextHash`-атрибуція:** `bytes32(intent BlockchainTransaction.id)` — subgraph/аудитор атрибутує on-chain slash-подію прямо до backend-інтенту (ARCH.45 durable marker створюється ДО broadcast, тож id уже існує); manual DAO/Timelock `slash()` емітить `bytes32(0)`. Subgraph: `SlashingEvent.contextHash` / `GovernanceSlashEvent.contextHash` (`subgraph/schema.graphql`).

> **Страхова премія — НЕ on-chain SCC-подія (знято [SEC.1], 2026-06-15).** Премія NaaS-контракту (5% від funding) — **off-chain USDC-факт** у БД (`NaasContract`; концепт-дім [`07_01`](07_01_Nature_as_a_Service_Contracts), ризик-політика [`05_05`](05_05_Slashing_and_Risk_Policy)). Колишній `recordPremiumPaid()` + `PremiumPaid`-event на SCC-токені був **never-fed** (жоден backend-виклик) і архітектурно чужорідним (SCC-event для USDC-факту) → видалено з контракту/тестів/subgraph. Real-Yield звіт бере премію з БД (`NaasContract.total_insurance_premiums`, [`04_03`](04_03_REST_API_v1_Reference) `reports#financial_summary`). Не плутати з **Dynamic-Tax SCC-пулом** — окремий on-chain механізм поповнення страхового пулу ([`05_02`](05_02_Proof_of_Growth_Pipeline)).

#### `pause()` / `unpause()`

```solidity
function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }
```

- **Operational Security [SEC.1]:** `pause()`/`unpause()` гейтяться `PAUSER_ROLE` — у production = Gnosis Safe multisig (3/5 або 2/3), миттєва реакція на exploit ПОЗА Timelock (під час хаку потрібна реакція за хвилини, а не дні). `DEFAULT_ADMIN_ROLE` (видача ролей, у т.ч. `MINTER_ROLE`) у production = `SilkenTimelock` (48h-затримка) — НЕ той самий ключ, що pause (див. таблицю ролей вище). Жоден не EOA.

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
    // Manual DAO/Timelock-шлях — без бекенд-інтенту, contextHash порожній.
    emit GovernanceSlashed(investor, amount, bytes32(0));
}
```

- **Модифікатор:** `onlyRole(SLASHER_ROLE)`, `nonReentrant`
- **Валідація:** `investor != address(0)`, `amount > 0`, `balanceOf(investor) >= amount` (revert: `"SFC: insufficient balance"`)
- **Тригер:** `BurnCarbonTokensWorker → BlockchainBurningService → slash(investor, amount)` при порушенні NaaS контракту
- **Guard on pause:** Слешинг **НЕ блокується** при паузі — `_update` дозволяє `_burn()` навіть коли контракт призупинено. Видалення voting power у порушників має бути завжди можливим.
- **Подія:** `GovernanceSlashed(address indexed investor, uint256 amount, bytes32 contextHash)` — manual `slash()` емітить `bytes32(0)`

#### `slashUpTo(address investor, uint256 maxAmount, bytes32 contextHash) → uint256 slashed` [SLASH.2]

Дзеркало SCC `slashUpTo`: палить `min(maxAmount, balanceOf)` атомарно (revert замінено clamp), тож переказ 1 wei до транзакції Оракула більше не рятує **voting power** порушника від slash. Валідація як SCC (`"SFC: nothing to slash"` при повному виведенні); подія — `GovernanceSlashed(investor, slashed, contextHash)` з фактично спаленою сумою та [CONTRACT.1]-атрибуцією (`bytes32(intent BlockchainTransaction.id)` — як у SCC); `getVotes` падає в lockstep (Halmos `check_slashUpTo_clampsToBalance` доводить, що після clamped-slash voting power == post-burn balance).

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
| `TokenSlashed` | `TokenSlashed(address indexed investor, uint256 amount, bytes32 contextHash)` | `investor` | ✅ `handleTokenSlashed` (пише `contextHash` — CONTRACT.1) |

### SFC

| Подія | Сигнатура | Indexed поля | Subgraph |
|---|---|---|---|
| `ForestMinted` | `ForestMinted(address indexed investor, uint256 amount, bytes32 indexed clusterIdHash, string clusterId)` | `investor`, `clusterIdHash` (bytes32 keccak256) | ✅ `handleForestMinted` (⚠️ contract address placeholder `0x0000...`) |
| `GovernanceSlashed` | `GovernanceSlashed(address indexed investor, uint256 amount, bytes32 contextHash)` | `investor` | ✅ `handleGovernanceSlashed` (пише `contextHash`; ⚠️ contract address placeholder) |

### Subgraph vs Контракт — Повна Матриця

| Event у subgraph.yaml | Подія у контракті | Статус |
|---|---|---|
| `CarbonMinted(indexed address,uint256,indexed bytes32,string)` | `CarbonMinted` | ✅ `treeDidHash` (bytes32) |
| `TokenSlashed(indexed address,uint256,bytes32)` | `TokenSlashed` | ✅ Синхронізовано (contextHash — CONTRACT.1) |
| `ForestMinted(indexed address,uint256,indexed bytes32,string)` | `ForestMinted` (SFC) | ✅ Handler додано (S3.5) |
| `GovernanceSlashed(indexed address,uint256,bytes32)` | `GovernanceSlashed` (SFC) | ✅ Handler додано (S3.5; contextHash — CONTRACT.1) |

> ⚠️ SFC data source в `subgraph.yaml` використовує placeholder `0x0000000000000000000000000000000000000000` — блокує deploy subgraph до Mainnet. Замінити після деплою SFC контракту.

---

## 💸 Dynamic Tax — HYBRID PROTOCOL GAIA

`BlockchainMintingService#build_batch_arrays` реалізує механізм автоматичного 2% відрахування від кожного SCC мінтингу до `DAO_TREASURY_ADDRESS` (ставка `dynamic_tax_rate` — governance-aware, S6.17):

```ruby
# При batchMint для carbon_coin — [O2/O4] податок агрегується:
taxing = token_type == "carbon_coin" && insurance_pool_requires_funding?
txs.each do |tx|
  tax_amount = taxing ? (tx.amount * dynamic_tax_rate).round(4) : 0
  tax_total += tax_amount
  recipients.push(tx.to_address)
  amounts.push(to_wei(tx.amount - tax_amount))
end

# ОДИН агрегований treasury-запис на під-батч (N+1 записів ≤ 100, НЕ 2N):
if tax_total.positive?
  recipients.push(ENV.fetch("DAO_TREASURY_ADDRESS"))
  amounts.push(to_wei(tax_total))
  identifiers.push("TAX_BATCH_#{identifier_for(txs.first)}")
end
```

> ⚠️ `ENV.fetch` тут — під E.46 rescue-парасолькою (`insurance_pool_requires_funding?` → `false` при будь-якій помилці): зламаний/відсутній `DAO_TREASURY_ADDRESS` НЕ падає на use — tax тихо вимикається, лог хибно каже «RPC degraded». Гучність забезпечує boot-guard `Web3NetworkGuard.address_violations` ([`04_02 §8`](04_02_Business_Logic_and_Services)).

```ruby
def insurance_pool_requires_funding?
  # On-chain query: балансOf DAO Treasury < INSURANCE_POOL_THRESHOLD (default 100_000 SCC)
  # Кешується 15 хв. [E.46] Failsafe: FALSE при збої RPC — НЕ штрафуємо мінтинг
  # під час деградації мережі (пропущений внесок безпечніший за постійний 2% податок).
  Rails.cache.fetch(TREASURY_CACHE_KEY, expires_in: TREASURY_CACHE_TTL) do
    fetch_treasury_balance_wei < INSURANCE_POOL_THRESHOLD_WEI
  end
end
```

**Наслідок:** Dynamic Tax застосовується коли баланс DAO Treasury < порогу. **[S6.17]** Ставка (default 2%) і поріг (default 100,000 SCC) — **governance-aware** через `SystemParameter` ← on-chain `ProtocolParameters.sol` (не хардкод-константи). Одиночний `mint()` (не `batchMint`) Dynamic Tax **не застосовує**.

---

## 🔄 Потік Мінтингу (Поточний Стан)

> **⚠️ [Lorenz de-risk]** Перший крок потоку (`Lorenz Z-value → growth_points`) спирається на **недоведену гіпотезу** «Z = здоров'я» ([`05_05 §8`](05_05_Slashing_and_Risk_Policy)). Slashing/мінтинг-рішення вимагають ≥1 прямого сигналу (sap_flow / VPD / acoustic), не лише Z ([`05_05 §7`](05_05_Slashing_and_Risk_Policy)). Lorenz-DCI (anti-fraud) валідний незалежно.

```
Telemetry → Lorenz Z-value → growth_points++
                                    ↓
                    TokenomicsEvaluatorWorker (щогодини, cron: 0 * * * *)
                                    ↓
                    Wallet.available_balance >= 10,000? → lock_and_mint!
                    (NET, не gross — [ARCH.94]: сконвертоване лишається в
                     locked_balance назавжди, тож фільтр по balance вічно
                     переобирав гаманці, які змінтувати вже нічого не можуть)
                                    ↓
                    MintCarbonCoinWorker [queue: web3_critical]
                                    ↓
                    Oracle-guards (лише якщо telemetry_log переданий, Path 1):
                    ├── verified_by_iotex? == true
                    └── oracle_status_fulfilled? (enum method)
                    (TokenomicsEvaluatorWorker без log → oracle-guard НЕ діє: оптимістичний мінт,
                     anti-fraud = ex-post clawback, не цей gate — 05_02 §Модель довіри / 00_07 ARCH.53)
                    KYC-guard (УСІ шляхи, поза telemetry_log-гілкою — KYC.1):
                    └── wallet.kyc_approved_for_minting? (бенефіціар; non-approved → per-tx SKIP, :pending)
                                    ↓
                    BlockchainMintingService#perform
                    ├── Oracle balance ≥ 0.05 MATIC
                    ├── Kredis lock (120s) — запобігає подвійному мінтингу
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

> **Політика slashing** — коли/чи взагалі палити (cause-classification A/B/C, поріг «>20% дерев stress≥0.83», convex-формула `damage_ratio^GAMMA`, de-risk-інваріант «не лише Z») — канон [`05_05`](05_05_Slashing_and_Risk_Policy) (§3 формула, §7 multi-signal). Нижче — лише контрактно-воркерна механіка потоку (`slash()` — дім цього доку).

```
ClusterHealthCheckWorker (02:00 UTC) [queue: default]
        ↓
NaasContract#check_cluster_health!
        ↓
> 20% дерев з stress_index >= 0.83?
        ↓
flag_degradation! → verdict :degraded (БЕЗ pre-breach; крон гейтить Celo за verdict)
        ↓
BurnCarbonTokensWorker [queue: critical]
        ↓
BlockchainBurningService#call → positive-A gate (SLASH-1, 05_05 §3.2):
   доказ Кат-A є → slash + status = :breached  |  нема → :frozen + Field Audit (no burn)
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

> **⚠️ The Graph = off-chain analytics, НЕ realtime (нот.2).** Subgraph має **eventual consistency** (indexing-lag секунди–хвилини, більше при reorg на Polygon). UI-баланс гаманця читається з **Rails DB** (`Wallets::BalanceFrame` Phlex Turbo Frame — [`04_03 §5`](04_03_REST_API_v1_Reference)), а **не** з subgraph — тому indexing-lag НЕ спричиняє «застарілий баланс → повторний mint». Subgraph живить лише протокольну статистику (`ProtocolFinancials`), не user-facing баланс.

```yaml
# subgraph/subgraph.yaml — поточний стан eventHandlers:

# SCC data source
- event: CarbonMinted(indexed address,uint256,indexed bytes32,string)
  handler: handleCarbonMinted           # ✅ treeDidHash як bytes32

- event: TokenSlashed(indexed address,uint256,bytes32)
  handler: handleTokenSlashed           # ✅ Синхронізовано (contextHash — CONTRACT.1)

# SFC data source (додано S3.5)
- event: ForestMinted(indexed address,uint256,indexed bytes32,string)
  handler: handleForestMinted           # ✅ clusterIdHash як bytes32

- event: GovernanceSlashed(indexed address,uint256,bytes32)
  handler: handleGovernanceSlashed      # ✅ Governance slashing tracking (contextHash)
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
| **OpenZeppelin** | 5.7.x (`pragma solidity 0.8.36` — locked) |
| **RPC** | `ALCHEMY_POLYGON_RPC_URL` (через `Web3::RpcConnectionPool`) |
| **Oracle wallet** | `ORACLE_MINTER_PRIVATE_KEY` (MINTER_ROLE) + `ORACLE_SLASHER_PRIVATE_KEY` (SLASHER_ROLE) — окремі ключі (E.2; custody-поріг = GCP-KMS remote-signer → [`06_04 §5.5`](06_04_Secrets_Checklist)) |
| **The Graph** | `subgraph/` — SCC та SFC events індексуються (⚠️ SFC: contract address placeholder) |
| **Chainlink** | Oracle dispatch для Proof of Growth pipeline (⚠️ Hybrid mode) |
| **peaq DID** | Верифікація `did:peaq:0x...` перед мінтингом |
| **IoTeX W3bstream** | ZK-доказ цілісності pipeline + DID-binding (апаратне *походження* = true-DePIN roadmap — [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)) |
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
├── subgraph.yaml                     # SCC: CarbonMinted + TokenSlashed; SFC: ForestMinted + GovernanceSlashed
└── src/mapping.ts                    # handleCarbonMinted, handleTokenSlashed (+ SFC handlers)

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

contracts/foundry.toml               # ✅ Foundry config: solc 0.8.36, EVM cancun, profiles (default/production)
```

---

## 🗳️ Governance DAO (Законодавча Гілка Влади) → 05_06

On-chain governance (SFC-голосування за протокольні параметри: slashing-пороги/криву, tokenomics-курс, ціни; Lorenz-ключі контракту — DCI-locked резерв OTA-ери, GOV.1) виокремлено у власний дім — [`05_06` — Governance & DAO](05_06_Governance_and_DAO). Там: `SilkenGovernor` / `SilkenTimelock` / `ProtocolParameters`, Flash-Loan-захист, Auto-Immune Sentinel, governance-aware backend (`SystemParameter` / `Governance::ParameterSyncWorker`). База — SFC `ERC20Votes` (§SFC — Ролі вище).

## 🔍 Smart Contract Audit Roadmap

### Етапи аудиту перед Mainnet Deployment

| Фаза | Інструмент / Постачальник | Тип | Коли | Статус |
|------|--------------------------|-----|------|--------|
| **1. Static Analysis** | [Slither](https://github.com/crytic/slither) | Безкоштовний open-source | Зараз (CI/CD) | ✅ Реалізовано: `solidity_audit.yml` `slither` job (fail-on high) |
| **1a. Static Analysis (2-й прохід)** | [Aderyn](https://github.com/Cyfrin/aderyn) | Безкоштовний open-source | Зараз (CI/CD) | ✅ Реалізовано: `aderyn` job (gate на high + SARIF → Security tab) |
| **1b. Property Fuzzing** | Foundry invariant + [Medusa](https://github.com/crytic/medusa) | Безкоштовний open-source | Зараз (CI/CD) | ✅ Реалізовано: `medusa` job (`test/medusa/`) + `forge` invariant (`test/invariant/`) |
| **1c. Symbolic Execution** | [Halmos](https://github.com/a16z/halmos) | Безкоштовний open-source | Зараз (CI/CD) | ✅ Реалізовано: `halmos` job (proof-и money-path інваріантів — `test/symbolic/`) |
| **2. Manual Audit (Pre-Testnet)** | [Hacken](https://hacken.io/) або [Hashlock](https://hashlock.com/) | Платний аудит | Перед Amoy → Mainnet | 🔴 TODO |
| **3. Runtime Monitoring** | [CertiK Skynet](https://skynet.certik.com/) | 24/7 моніторинг | Після Mainnet deploy | 🔴 TODO |

> **Mythril знято** (раніше планований symbolic-tool, 1b): занедбаний (остання версія v0.24.8 / 2024, без EVM cancun, зависає на OZ-важких контрактах) → замінений на **Halmos** (foundry-native, читає наш `foundry.toml` solc 0.8.36 / cancun). 2025-26 enterprise-стек = static (Slither + Aderyn) → property-fuzz (Foundry + Medusa) → symbolic (Halmos) → manual audit (Hacken) → runtime (CertiK).

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
# Тригер: зміни в contracts/ (або в самому workflow) на PR/push to main; + workflow_dispatch
# Компілюємо самі: forge build --build-info (solc 0.8.36 з foundry.toml), далі
# crytic/slither-action@v0.4.2 з ignore-compile: true (читає build-info; forge install не потрібен — deps npm)
# slither-version запінено: SHA-пін екшена НЕ тримає його начинку (образ тягне
# slither-analyzer з PyPI свіжим щоразу) → 06_07 §1a, стан 00_07 OPS.21
# slither.config.json: fail-on high, filter_paths node_modules|test/ (аудит лише деплойних контрактів)
# OpenZeppelin 5.x через contracts/package.json
```

**Foundry Deploy Script (✅ Реалізовано):**
```bash
# contracts/script/Deploy.s.sol — деплой всіх 6 контрактів у правильному порядку:
# 1. Timelock → 2. SCC → 3. SFC → 4. StateRootAnchor → 5. Governor → 6. ProtocolParameters
# Потрібні ENV: DEPLOYER_PRIVATE_KEY, ADMIN_ADDRESS, MINTER_ORACLE, SLASHER_ORACLE, ANCHOR_ORACLE
# Dry-run: forge script script/Deploy.s.sol --rpc-url $RPC_URL
# Broadcast: FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

**Halmos · Aderyn · Medusa (✅ Реалізовано):**
```bash
# Symbolic proofs of money-path invariants (cap / last-admin / pause-allows-slash):
halmos --function "^check_" --solver-threads 1 --loop 3        # test/symbolic/*
# 2nd static pass (gate on high; SARIF → Security tab):
aderyn . --skip-update-check -o aderyn-report.sarif            # aderyn.toml
# Property fuzzing (single-file target keeps crytic-compile off forge-std/LibVariable):
medusa fuzz --config medusa-scc.json && medusa fuzz --config medusa-sfc.json
```

> **Medusa `panicCodeConfig` — що ловимо і ЧОМУ саме так** [CONTRACT.2, 2026-07-25]. JSON коментарів не тримає, тож рішення живе тут. Увімкнено `failOnAssertion` + **шість logic-error панік**: `0x21` enum-конверсія · `0x22` incorrect storage access · `0x31` pop порожнього масиву · `0x32` вихід за межі масиву · `0x41` надмірне виділення пам'яті · `0x51` виклик неініціалізованої змінної. Це справжні логічні помилки, і на money-path вони мусять валити білд.
>
> **`failOnArithmeticUnderflow` (0x11) і `failOnDivideByZero` (0x12) лишаються `false` СВІДОМО** — на Solidity 0.8+ це не баги, а навмисні safety-реверти самого компілятора; фейл на них позначав би КОЖЕН інтенційний revert як знахідку й утопив би сигнал. `failOnCompilerInsertedPanic` off із тієї ж причини (він вмикає весь клас гуртом).
>
> ⚠️ **Чесна межа цього гейта.** Обидва конфіги мають `targetContracts: ["SCCMedusaTest"]` + `testAllContracts: false`, тобто Medusa набирає ABI **обгортки**, а не SCC/SFC. У харнесі — чотири функції, і кожна знезброює вхід фаззера ще до контракту (`amount = (amount % remaining) + 1`, `amount % (bal + 1)`). Тому **сьогодні жоден із шести кодів не має досяжного шляху**: вмикання — defense-in-depth на майбутнє (спрацює в мить, коли харнес розшириться), а не активний детектор. Найгостріший наслідок цієї межі — `batchMint` (єдина money-path функція з масивами під контролем фаззера) **взагалі поза фаззингом** → відкрите в [`00_07`](00_07_Action_Plan_Tracker) CONTRACT.2.

**Operational Security (production) [SEC.1] — деталі §Admin-Role Split вище:**
- `DEFAULT_ADMIN_ROLE` (токени + `ProtocolParameters`) → **SilkenTimelock** (48h) — ✅ `Deploy.s.sol`; видача будь-якої ролі за 48h
- `PAUSER_ROLE` → **Gnosis Safe** (3/5 або 2/3) — миттєва пауза поза Timelock; 👤 **TODO**: реальний Safe + зовнішні co-signer'и
- `StateRootAnchor` admin → **SilkenTimelock** (нема `pause()`; видача `ANCHOR_ROLE` = management → governance-gated; uniform «admin=Timelock, окрім pause»)
- `MINTER_ROLE` / `SLASHER_ROLE` → окремі Oracle EOA (✅ реалізовано, E.2)
- `pause()` → без timelock (потрібна миттєва реакція при exploits)

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
Phase 1: blockchain anchoring → biomass_passport_tx_hash + status :sent у MaintenanceRecord
         ↓
Phase 2: PuroEarthConfirmationWorker → receipt-полл → :confirmed / :failed / :manual_review
         ↓
Phase 3 (лише після :confirmed): REST API submission → Puro.earth → puro_earth_corc_ref
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

> **Статус:** `PuroEarthPassportWorker` — у черзі `web3` (пріоритет 7). ✅ Трифазний pipeline [PERF.1(д), 2026-08-20]: Phase 1 зберігає `biomass_passport_tx_hash` + `:sent`; Phase 2 — власний receipt-полл (`PuroEarthConfirmationWorker`, `web3_low`) з lifecycle на `biomass_passport_status` (прецедент `EthereumAnchor`); Phase 3 зберігає `puro_earth_corc_ref` — гейтована на `:confirmed`, тож on_chain_proof не віддається в зовнішній реєстр, доки receipt не доведено. Доти конфірмейшн-нога вела в `blockchain_transactions`, куди паспортний хеш не потрапляє ніколи.
