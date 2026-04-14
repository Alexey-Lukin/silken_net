# 05_03: Tokenomics — SCC & SFC (Смарт-контракти на Polygon)

**Модуль:** 05_03 — Tokenomics: SilkenCarbonCoin & SilkenForestCoin
**Пов'язані модулі:** [05_01 Multichain Architecture](BLOCKCHAIN_DEVELOPMENT.md) · [05_02 Proof of Growth Pipeline](TOKENOMICS.md)
**Поточний TRL:** 7 (Контракти існують, але SSOT є неправильною/застарілою)
**Цільовий TRL:** 8 (Повна синхронізація логіки токеноміки з Wiki)
**Статус Аудиту:** Reverse Shaping — лише документація, без рефакторингу коду

> **⚠️ SSOT Sync:** Цей документ синхронізовано з кодбейсом станом на 2026-03-23.
> **Джерела правди:** `contracts/SilkenCarbonCoin.sol`, `contracts/SilkenForestCoin.sol`,
> `app/services/blockchain_minting_service.rb`, `app/services/blockchain_burning_service.rb`,
> `subgraph/subgraph.yaml`

---

## 🎯 Мета (Objective)

Зафіксувати реальний стан ("як є") смарт-контрактів токеноміки Gaia 2.0 — `SilkenCarbonCoin` (SCC) та `SilkenForestCoin` (SFC). Документ описує стандарти токенів, ієрархію ролей, ключові функції, механізм Dynamic Tax, зв'язок з бекендом та повний перелік знайдених блокерів.

---

## ✅ Статус (Status)

- **SCC контракт:** ✅ Задеплоєний (логіка мінту та slash реалізована)
- **SFC контракт:** ✅ Задеплоєний (логіка мінту + Votes + Permit реалізована)
- **Backend інтеграція:** ✅ `BlockchainMintingService` + `BlockchainBurningService`
- **The Graph subgraph:** ⚠️ Event name mismatch (`Slashed` vs `TokenSlashed`) — [05_01 BLOCKER-2]
- **Mainnet deployment:** 🔴 Заблоковано критичними блокерами (деталі нижче)

---

## 🏗️ Dual Token System (Архітектура)

| Параметр | SCC — Silken Carbon Coin | SFC — Silken Forest Coin |
|---|---|---|
| **Тип** | Utility Token | Governance Token |
| **Ticker** | SCC | SFC |
| **Стандарти** | ERC-20 + AccessControl + Pausable | ERC-20 + AccessControl + Pausable + ERC20Permit + ERC20Votes |
| **Мережа** | Polygon (Amoy testnet → Mainnet) | Polygon (Amoy testnet → Mainnet) |
| **Файл** | `contracts/SilkenCarbonCoin.sol` | `contracts/SilkenForestCoin.sol` |
| **ENV адреса** | `CARBON_COIN_CONTRACT_ADDRESS` | `FOREST_COIN_CONTRACT_ADDRESS` |
| **Pragma** | `^0.8.20` | `^0.8.20` |
| **Максимальна емісія** | ❌ Не обмежена | ❌ Не обмежена |
| **Slash / Burn** | ✅ `slash()` через `SLASHER_ROLE` | ❌ Відсутній |
| **Gasless approvals** | ❌ | ✅ EIP-2612 / EIP-712 |
| **DAO голосування** | ❌ | ✅ `ERC20Votes` |
| **Subgraph індексація** | ✅ `CarbonMinted`, ⚠️ `Slashed` (помилка) | ❌ Немає |

---

## 📦 OpenZeppelin — Успадковані Стандарти

### SilkenCarbonCoin (SCC)

```solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract SilkenCarbonCoin is ERC20, AccessControl, Pausable { ... }
```

| Базовий контракт | Призначення |
|---|---|
| `ERC20` | Стандартний fungible token: `transfer`, `approve`, `transferFrom`, `balanceOf`, `totalSupply` |
| `AccessControl` | Ієрархія ролей через `bytes32` hash — `grantRole`, `revokeRole`, `hasRole` |
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
- **Dynamic Tax:** При виклику `batchMint` з бекенду, `BlockchainMintingService` може вставляти додаткових отримувачів (`DAO_TREASURY_ADDRESS`) для Dynamic Tax — BLOCKER B-05

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
| `Slashed(indexed address,uint256,indexed string)` | `TokenSlashed` | 🚨 MISMATCH — [05_01 BLOCKER-2] |
| `PremiumPaid(indexed address,uint256)` | ❌ **Відсутня в контракті** | 🚨 Подія не існує — BLOCKER B-11 |

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
# TODO: Інтегрувати з реальним балансом DAO Treasury через on-chain query.
def insurance_pool_requires_funding?
  true  # ⚠️ ЗАВЖДИ TRUE — BLOCKER B-05
end
```

**Наслідок:** Dynamic Tax застосовується на **кожен** пакетний мінт незалежно від стану страхового пулу. Одиночний `mint()` (не `batchMint`) Dynamic Tax **не застосовує**.

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
                    Guards (лише якщо telemetry_log переданий):
                    ├── verified_by_iotex? == true
                    ├── oracle_status == "fulfilled"
                    └── hadron_kyc_status == "approved"
                    ⚠️ TokenomicsEvaluatorWorker НЕ передає telemetry_log → Guards пропускаються [05_02 BLOCKER-11]
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
⚠️ The Graph НЕ індексує (subgraph слухає "Slashed", а не "TokenSlashed")
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

## 🚨 Блокери (Needs Action)

Нижче зафіксовані всі відхилення, хардкод та проблеми, виявлені під час аудиту коду. **Жодного рефакторингу в цьому циклі.** Кожен блокер — передумова для Mainnet deployment або зовнішнього аудиту (CertiK/Hacken).

---

### 🔴 КРИТИЧНО (P0 — Security / Mainnet Blocker)

#### B-01: Відсутність максимальної емісії (No Max Supply)

**Контракти:** SCC та SFC
**Файли:** `contracts/SilkenCarbonCoin.sol:29–55`, `contracts/SilkenForestCoin.sol:28–52`

Жодного `maxSupply` параметра або перевірки в `_mint`. Компрометований oracle може необмежено емітувати токени, що призведе до гіперінфляції та знецінення.

```solidity
// Поточний стан — НЕ МАЄ:
// uint256 public constant MAX_SUPPLY = ...;
// require(totalSupply() + amount <= MAX_SUPPLY, "SCC: cap exceeded");

function mint(address to, uint256 amount, string calldata treeDid)
    external onlyRole(MINTER_ROLE)
{
    _mint(to, amount);  // ← Необмежена емісія
    ...
}
```

**Ризик:** Компрометований `ORACLE_PRIVATE_KEY` → безмежна інфляція.
**Потрібно (наступний цикл):** `uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18` та перевірка перед `_mint`.

---

#### B-02: Єдиний `ORACLE_PRIVATE_KEY` = MINTER + SLASHER (Single Point of Failure)

**Контракт:** SCC
**Файл:** `contracts/SilkenCarbonCoin.sol:20–24`

Конструктор SCC надає **одній** oracle адресі і `MINTER_ROLE`, і `SLASHER_ROLE`. Один компрометований ключ (`ORACLE_PRIVATE_KEY`) дозволяє одночасно карбувати нові токени для себе та спалювати токени інших.

```solidity
constructor(address admin, address oracle) ERC20("Silken Carbon Coin", "SCC") {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(MINTER_ROLE, oracle);    // ← Той самий oracle...
    _grantRole(SLASHER_ROLE, oracle);   // ← ...і тут
}
```

**Ризик:** Критичний — повний контроль над economy lifecycle одним ключем.
**Потрібно (наступний цикл):** Розділити на `minterOracle` та `slasherOracle` — окремі гаманці, окремі права.

---

#### B-03: Відсутність zero-address validation в конструкторах

**Контракти:** SCC та SFC
**Файли:** `contracts/SilkenCarbonCoin.sol:20`, `contracts/SilkenForestCoin.sol:20`

Конструктори не валідують `admin != address(0)` та `oracle != address(0)`. Якщо помилково передати нульову адресу — роль видається назавжди недоступному акаунту. Виправлення вимагає повного редеплою контракту.

```solidity
// Поточний стан — НЕ МАЄ перевірки:
constructor(address admin, address oracle) ERC20("Silken Carbon Coin", "SCC") {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);  // admin може бути address(0)!
    ...
}
```

**Потрібно (наступний цикл):**
```solidity
require(admin != address(0), "SCC: zero admin");
require(oracle != address(0), "SCC: zero oracle");
```

---

### 🟠 ВАЖЛИВО (P1 — Функціональні/Довірчі Проблеми)

#### B-04: Відсутній ліміт розміру масиву в `batchMint`

**Контракти:** SCC та SFC
**Файли:** `contracts/SilkenCarbonCoin.sol:43–55`, `contracts/SilkenForestCoin.sol:40–52`

`batchMint` не обмежує кількість елементів. При >200–500 записів транзакція може перевищити gas limit блоку Polygon (~30M gas) та reverted.

**Ризик:** DoS вектор; `BlockchainMintingService` не має власного ліміту.
**Потрібно:** `require(length <= 200, "SCC: batch too large");`

---

#### B-05: `insurance_pool_requires_funding?` завжди повертає `true`

**Файл:** `app/services/blockchain_minting_service.rb:194–196`

```ruby
def insurance_pool_requires_funding?
  true  # TODO: Інтегрувати з реальним балансом DAO Treasury через on-chain query.
end
```

**Наслідок:** Dynamic Tax (2%) застосовується на **кожен** пакетний мінт SCC незалежно від стану страхового пулу. 100% пакетних транзакцій розщеплюються між форестером та `DAO_TREASURY_ADDRESS`, що порушує умови NaaS-контрактів (інвестори отримують 98% замість 100%).
**Потрібно:** On-chain query до DAO Treasury контракту для перевірки балансу пулу. (Також задокументовано у [05_02 BLOCKER-05])

---

#### B-06: Відсутній `slash` механізм для SFC

**Контракт:** SFC
**Файл:** `contracts/SilkenForestCoin.sol`

SFC не має `SLASHER_ROLE` та функції `slash()`. При активації slashing protocol (>20% аномальних дерев) спалюються лише SCC. Governance токени залишаються у "нечесних" учасників, що дозволяє їм впливати на DAO-голосування навіть після порушення NaaS контракту.

**Питання:** Архітектурне рішення чи технічний борг? Потрібне явне рішення від команди.

---

#### B-07: Непослідовна реалізація паузи між SCC та SFC

**Файли:** `contracts/SilkenCarbonCoin.sol:73–79`, `contracts/SilkenForestCoin.sol:62–70`

SCC використовує `whenNotPaused` модифікатор в `_update`. SFC — ручну перевірку `if (paused()) revert EnforcedPause()`. Різні патерни для однієї функції — ускладнює аудит (функціонально еквівалентно, але потребує уніфікації).

---

#### B-08: `PremiumPaid` event у subgraph відсутня в контракті

**Файли:** `subgraph/subgraph.yaml:36–38`, `contracts/SilkenCarbonCoin.sol`

Subgraph підписаний на `PremiumPaid(indexed address,uint256)`, але цієї події не існує в `SilkenCarbonCoin.sol`. `handlePremiumPaid`ніколи не буде викликана — `ProtocolFinancials.totalPremiums` завжди `0`.

```yaml
# subgraph.yaml — підписано на неіснуючу подію:
- event: PremiumPaid(indexed address,uint256)
  handler: handlePremiumPaid
```

**Потрібно:** Або додати event `PremiumPaid` до контракту, або видалити handler зі subgraph.

---

#### B-09: Event name mismatch у subgraph — `Slashed` vs `TokenSlashed`

**(Перехресне посилання: [05_01 BLOCKER-2])**

**Файли:** `subgraph/subgraph.yaml:32–34`, `contracts/SilkenCarbonCoin.sol:18`

```yaml
# subgraph.yaml:
- event: Slashed(indexed address,uint256,indexed string)   # ← НЕПРАВИЛЬНО

# Контракт:
event TokenSlashed(address indexed investor, uint256 amount); # ← Правильна назва
```

**Наслідок:** Slashing-події не індексуються The Graph. `ProtocolFinancials.totalBurned` завжди `0`. CertiK/Hacken аудитори побачать нульовий burn у протоколі.
**Фікс:** Змінити `Slashed` → `TokenSlashed` у `subgraph/subgraph.yaml`.

---

#### B-10: Indexed `string` у Events — втрата читабельності

**Контракти:** SCC та SFC
**Файли:** `contracts/SilkenCarbonCoin.sol:17`, `contracts/SilkenForestCoin.sol:18`

`string indexed treeDid` та `string indexed clusterId` зберігаються як `keccak256` хеш. Off-chain підписники не можуть прочитати DID/clusterId з event logs без окремого lookup.

**Потрібно:** Прибрати `indexed` з рядкових полів; якщо пошук потрібен — додати `bytes32 treeDidHash = keccak256(treeDid)` як окреме indexed поле.

---

#### B-11: TokenomicsEvaluatorWorker оминає Trustless Guards

**(Перехресне посилання: [05_02 BLOCKER-11])**

**Файл:** `app/services/blockchain_minting_service.rb:52–57`

```ruby
if @telemetry_log
  raise "Security Breach: Data not verified by IoTeX" unless @telemetry_log.verified_by_iotex?
  raise "Security Breach: Chainlink Oracle consensus not fulfilled" unless ...
end
# ⚠️ Якщо telemetry_log == nil — всі guard checks пропускаються
```

**Наслідок:** `TokenomicsEvaluatorWorker` запускає `MintCarbonCoinWorker` без `telemetry_log`, і всі trustless guards (IoTeX ZK, Chainlink) не спрацьовують. Токени можуть бути відмінтовані для незверифікованих даних.

---

### 🟡 ТЕХНІЧНИЙ БОРГ (P2–P3)

#### B-12: `mintForTree` vs `mint` — розбіжність назви функції з Wiki

**Файли:** `contracts/SilkenCarbonCoin.sol:29`, Wiki 05_01, Wiki 05_02

Wiki та `docs/TOKENOMICS.md` посилаються на `mintForTree`, але реальна функція називається `mint`. Аудиторам (CertiK/Hacken) потрібна узгоджена документація.

#### B-13: Відсутній `ReentrancyGuard`

**Контракти:** SCC та SFC

Контракти не успадковують `ReentrancyGuard`. Стандартні ERC-20 операції безпечні від reentrancy (без ETH transfers), але відсутність guard є ризиком при майбутніх розширеннях.

#### B-14: Неповний NatSpec у SFC

**Файл:** `contracts/SilkenForestCoin.sol:28–35, 54–60`

`mint()`, `pause()`, `unpause()` у SFC не мають `@notice`, `@param` NatSpec коментарів. SCC має часткову документацію. Аудитори потребують повного NatSpec.

#### B-15: `startBlock: 0` у subgraph конфігурації

**Файл:** `subgraph/subgraph.yaml`

```yaml
address: "0x0000000000000000000000000000000000000000"  # TODO: замінити
startBlock: 0  # TODO: встановити номер блоку деплою
```

`startBlock: 0` означає індексацію з genesis блоку Polygon — надзвичайно довга синхронізація. Потрібно встановити реальний блок деплою контракту.

---

## 📊 Матриця Ризиків

| # | Блокер | Область | Вплив | Пріоритет |
|---|---|---|---|---|
| B-01 | Відсутність max supply | Security | Безмежна інфляція | P0 |
| B-02 | Єдиний oracle = minter + slasher | Security | Повний контроль одним ключем | P0 |
| B-03 | Zero address check відсутній | Security | Нерозгортувана помилка | P0 |
| B-04 | Відсутній ліміт batchMint | Functional | DoS / Gas limit revert | P1 |
| B-05 | `insurance_pool_requires_funding?` = true | Financial | 2% Dynamic Tax на кожен mint | P1 |
| B-06 | SFC без slash механізму | Governance | DAO атака після breach | P1 |
| B-07 | Непослідовна реалізація паузи | Maintainability | Ускладнений аудит | P1 |
| B-08 | `PremiumPaid` відсутня в контракті | Subgraph | `totalPremiums` завжди 0 | P1 |
| B-09 | `Slashed` vs `TokenSlashed` mismatch | Subgraph | `totalBurned` завжди 0 | P1 |
| B-10 | Indexed string → keccak256 | Observability | Нечитабельні event logs | P2 |
| B-11 | TokenomicsEvaluator оминає guards | Security | Незверифікований мінтинг | P1 |
| B-12 | `mintForTree` vs `mint` назва | Documentation | Розбіжність з Wiki | P3 |
| B-13 | Відсутній ReentrancyGuard | Security | Превентивний ризик | P2 |
| B-14 | Неповний NatSpec у SFC | Documentation | Ускладнений аудит | P3 |
| B-15 | `startBlock: 0` у subgraph | Performance | Надповільна синхронізація | P2 |

**Легенда пріоритетів:** P0 = Блокує Mainnet негайно (security breach) · P1 = Потрібно вирішити до Mainnet · P2 = Потрібно для виробничої відповідності · P3 = Технічний борг

**Загальний висновок:** Контракти функціонально реалізують базову логіку мінтингу та slashing і мають RSpec-покриття через сервіси. Проте **3 критичні блокери (B-01, B-02, B-03)** та **6 важливих (B-04 – B-09, B-11)** унеможливлюють production/Mainnet deployment та зовнішній аудит.

---

## 📂 Структура Файлів (File Map)

```
contracts/
├── SilkenCarbonCoin.sol              # SCC: ERC-20 + AccessControl + Pausable
└── SilkenForestCoin.sol              # SFC: ERC-20 + AccessControl + Pausable + Permit + Votes

app/services/
├── blockchain_minting_service.rb     # SCC + SFC mint / batchMint + Dynamic Tax
└── blockchain_burning_service.rb     # SCC slash

app/workers/
├── mint_carbon_coin_worker.rb        # queue: web3_critical, retry: 5
├── burn_carbon_tokens_worker.rb      # queue: critical, retry: 5
├── blockchain_confirmation_worker.rb # queue: web3_critical, retry: 5
└── tokenomics_evaluator_worker.rb    # cron: 0 * * * *, queue: default

subgraph/
├── schema.graphql                    # CarbonMintEvent, SlashingEvent, ProtocolFinancials
├── subgraph.yaml                     # ⚠️ Event name mismatch (B-09, B-08)
└── src/mapping.ts                    # handleCarbonMinted, handleSlashed, handlePremiumPaid

spec/services/
├── blockchain_minting_service_spec.rb
└── blockchain_burning_service_spec.rb
```

---


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
