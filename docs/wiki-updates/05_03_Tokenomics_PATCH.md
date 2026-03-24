# PATCH: 05_03_Tokenomics_SCC_and_SFC

## Що додати (нотатка N13 — Governance DAO для змінних протоколу)

### Де вставити

Додати нову секцію **в кінець документа** (після розділу "🌍 Зовнішні Залежності" або перед закриваючим рядком документа):

---

```markdown
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
```
