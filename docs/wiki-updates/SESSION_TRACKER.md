# Wiki Updates — Session Tracker

Цей файл відстежує прогрес інтеграції нотаток у wiki-сторінки SSOT.
Кожна сесія читає повний вміст wiki-сторінок, інтегрує нотатки і зберігає
оновлений markdown тут (`docs/wiki-updates/`). Ти вручну копіюєш у wiki.

---

## Вихідні нотатки (Raw Notes) — Класифікація

| # | Нотатка | Куди | Сесія |
|---|---------|------|-------|
| N1 | Starlink Direct-to-Cell через Київстар — модем Starlink не потрібен | `02_05` | 1 ✅ |
| N2 | nTop ліцензія, 100 одиниць з Києва/Дніпра DMLS | `01_02`, `07_02` | 2 |
| N3 | ЧНУ — тест ксилемного соку, 4-річний еквівалент за місяць | `08_01` | 2 |
| N4 | Штучний аналог ксилемного соку (pH 4.5–5.5, ICP-MS, електрохімічне прискорення) | `08_01` | 2 |
| N5 | LTspice (симуляція аналогових ланцюгів), KiCad (PCB), Wokwi/Proteus (MCU) | `02_01` | 2 |
| N6 | STM32CubeIDE для прошивки STM32 | `03_01` | 2 |
| N7 | Akash + GCP гібридний деплой, менеджер секретів (Bitwarden/1Password) | `06_01` | 1 ✅ |
| N8 | DNS-пастка (Let's Encrypt потребує A-запис до kamal setup) | `06_01` | 1 ✅ |
| N9 | `.kamal/secrets` файл — чеклист перед деплоєм | `06_01` | 1 ✅ |
| N10 | Газ для Web3-воркерів (MATIC, ETH, SOL, CELO) | `06_01` | 1 ✅ |
| N11 | LoRa-антена — ніколи не вмикати без антени (SX1262 згорить) | `06_01` | 1 ✅ |
| N12 | AES-ключ — Soldier і Queen повинні бути ідентичними | `06_01`, `03_05` | 1 ✅ / 3 |
| N13 | Governance DAO для констант протоколу (σ, ρ, β, поріг Slashing) | `05_03` | 3 |
| N14 | Forester Guild — Proof-of-Physical-Work, bounty для лісників | `04_02` | 3 |
| N15 | Cross-Registry API (Verra, Gold Standard, UNFCCC) | `05_01` | 3 |
| N16 | Federated Learning Loop — авто-перенавчання TinyML-моделі | `04_02`, `03_03` | 3 |
| N17 | Гранти (Gitcoin/Giveth), інструкція монтажу вже написана | `07_03` | — вже є |
| N18 | Terraform + Kamal покроковий деплой | `06_01` | 1 ✅ |

---

## Прогрес по Сесіях

### ✅ Сесія 1 (поточна)
**Файли:** `02_05_Queen_Hardware_and_Starlink.md`, `06_01_Deployment_Kamal_Terraform.md`

- [x] N1 — Starlink DTC у `02_05`: оновлено статус таблиці, BLOCKER-1 переформульовано — DTC через Київстар не потребує Starlink-термінала/модема; SIM7070G достатньо
- [x] N7, N8, N9, N10, N11, N12, N18 — у `06_01`: додано розділ "⚠️ Pre-Flight Checklist" (5 пунктів) + "Secrets Manager" + "🚀 Quickstart"

### ✅ Сесія 2 (виконано)
**Файли:** `02_01_Hardware_Architecture_and_BOM.md`, `01_02_Ti6Al4V_PATCH.md`, `08_01_University_R_D_PATCH.md`, `03_01_Firmware_Lifecycle_PATCH.md`

- [x] N5 — `02_01`: Повна оновлена сторінка з новим розділом "Development Toolchain" (LTspice, KiCad, Wokwi/Proteus)
- [x] N2 — `01_02_Ti6Al4V_PATCH.md`: Патч — добавити "Manufacturing Status" (nTop ліцензія ✅, 100 шт. DMLS Київ/Дніпро)
- [x] N3, N4 — `08_01_University_R_D_PATCH.md`: Патч — оновити статус (перший візит заплановано), деталі тесту (pH 4.5-5.5, ICP-MS, електрохімічне прискорення, 1 міс = 4 роки)
- [x] N6 — `03_01_Firmware_Lifecycle_PATCH.md`: Патч — додати "Development Toolchain" (STM32CubeIDE, Clock Tree, host-tests)

**Тип файлів:**
- `02_01_Hardware_Architecture_and_BOM.md` — **повна сторінка** (замінює цілком)
- `01_02_Ti6Al4V_PATCH.md` — **патч** (показує що/де додати в існуючу сторінку)
- `08_01_University_R_D_PATCH.md` — **патч** (показує що/де додати в існуючу сторінку)
- `03_01_Firmware_Lifecycle_PATCH.md` — **патч** (показує що/де додати в існуючу сторінку)

### ✅ Сесія 3 (виконано)
**Файли:** `03_05_AES256_Security_PATCH.md`, `05_03_Tokenomics_PATCH.md`, `04_02_Business_Logic_PATCH.md`

- [x] N12 — `03_05_AES256_Security_PATCH.md`: Патч — операційне попередження про AES-мисматч (мовчазна втрата телеметрії + vault рекомендація)
- [x] N13 — `05_03_Tokenomics_PATCH.md`: Патч — Governance DAO (GovernorContract, ProtocolParameters, `Governance::ParameterSyncWorker`, dynamic backend constants)
- [x] N14 — `04_02_Business_Logic_PATCH.md`: Патч — Forester Guild (ForestBountyService, ProofOfPhysicalWork, USDC bounty, MaintenanceRecord розширення)
- [x] N15 — `04_02_Business_Logic_PATCH.md`: Патч — Cross-Registry API (Verra/Gold Standard/UNFCCC, CrossRegistryExportService, MRV Report)
- [x] N16 — `04_02_Business_Logic_PATCH.md`: Патч — Federated Learning Loop (FederatedLearningWorker, ModelValidationService, auto-retrain + OTA)

---

## ✅ Всі Нотатки Оброблено

| # | Нотатка | Файл | Статус |
|---|---------|------|--------|
| N1 | Starlink DTC через Київстар | `02_05_Queen_Hardware_and_Starlink.md` | ✅ Сесія 1 |
| N2 | nTop ліцензія, 100 шт. DMLS | `01_02_Ti6Al4V_PATCH.md` | ✅ Сесія 2 |
| N3, N4 | ЧНУ тест ксилемного соку | `08_01_University_R_D_PATCH.md` | ✅ Сесія 2 |
| N5 | LTspice, KiCad, Wokwi/Proteus | `02_01_Hardware_Architecture_and_BOM.md` | ✅ Сесія 2 |
| N6 | STM32CubeIDE | `03_01_Firmware_Lifecycle_PATCH.md` | ✅ Сесія 2 |
| N7–N12, N18 | Pre-Flight Checklist + Quickstart | `06_01_Deployment_Kamal_Terraform.md` | ✅ Сесія 1 |
| N13 | Governance DAO | `05_03_Tokenomics_PATCH.md` | ✅ Сесія 3 |
| N14 | Forester Guild | `04_02_Business_Logic_PATCH.md` | ✅ Сесія 3 |
| N15 | Cross-Registry API | `04_02_Business_Logic_PATCH.md` | ✅ Сесія 3 |
| N16 | Federated Learning Loop | `04_02_Business_Logic_PATCH.md` | ✅ Сесія 3 |
| N17 | Гранти + монтажна інструкція | — | ✅ Вже є у `07_03` |

---

## Правила для наступних сесій

1. Завжди читай ПОВНИЙ вміст wiki-сторінки (fetch start_index 0 і 8000+ якщо >8KB)
2. Зберігай оновлений markdown у `docs/wiki-updates/<PageName>.md`
3. Не переписуй структуру — тільки інтегруй у відповідні існуючі секції
4. Оновлюй цей трекер: ставь ✅ на виконані нотатки
5. Стиль: інженерний, markdown таблиці, bullet-lists, без води
