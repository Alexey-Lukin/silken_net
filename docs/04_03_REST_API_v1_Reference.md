# 04_03: Довідник REST API v1

## 🎯 Мета

Зафіксувати повний контракт REST API v1 як Єдине Джерело Істини (SSOT). Документ описує всі **ендпоінти**, механізми автентифікації, ролеву модель доступу, формати запитів/відповідей та типовий lifecycle взаємодії прошивки Gateway з бекендом.

## ✅ Статус

- **Поточний TRL:** TRL 8 (System Qualified / Production Ready). Впроваджено Zero-Trust (HKDF, Ed25519, HMAC), асинхронну розшифровку телеметрії та Rate Limiting (Rack::Attack).
- **Кількість ендпоінтів:** 84 (включно з `POST /api/v1/auth/m2m_token`, `POST /api/v1/auth/m2m_token/refresh`, `POST /api/v1/gateways/:id/telemetry`, `GET /api/v1/users/:id`, `GET /api/v1/system_audits`)
- **Базовий URL:** `https://<host>/api/v1`
- **Формат відповідей:** JSON (якщо не вказано інше)
- **Пов'язані модулі:**
  - Бізнес-логіка → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - Схема БД → [`04_01_Data_Models_and_Entities`](04_01_Data_Models_and_Entities)
  - Прошивка → [`03_01_Firmware_Lifecycle_and_DMA`](03_01_Firmware_Lifecycle_and_DMA)
  - Токеноміка → [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC)

---

## 1. Автентифікація

API підтримує **два паралельні механізми** автентифікації, реалізованих у `BaseController`:

### 1.1 Bearer Token (для API-клієнтів та прошивки Gateway)

```
Authorization: Bearer <token>
```

- Токен генерується при успішному POST `/api/v1/login` (поле `token` у відповіді).
- Реалізація: `User.find_by_token_for(:api_access, token)` — Rails 8 `generates_token_for`.
- Токен має термін дії 30 днів.
- **Обмеження на вхід:** rate limit — 5 спроб за 1 хвилину (HTTP 429 при перевищенні).
- **M2M Auth (Gateway):** прошивка шлюзу не може інтерактивно оновити токен. Для цього використовується `POST /api/v1/auth/m2m_token` — Ed25519-підпис DID без логіна/пароля (§1.4 та §5.14).

### 1.2 Session Cookie (для браузерного Dashboard)

- Встановлюється автоматично при вході через форму `POST /api/v1/login` (формат HTML).
- Cookie-based session (`session[:user_id]`).
- Захист від Session Fixation: `reset_session` перед встановленням нової сесії.

### 1.3 Публічні ендпоінти (без автентифікації)

| Маршрут | Метод | Опис |
|---|---|---|
| `/api/v1/login` | GET, POST | Форма та обробка входу |
| `/api/v1/logout` | DELETE | Вихід |
| `/api/v1/forgot_password` | GET, POST | Запит скидання пароля |
| `/api/v1/reset_password` | GET, PATCH | Форма та обробка нового пароля |
| `/api/v1/oracle_callbacks` | POST | Chainlink DON callback (HMAC-SHA256 валідація через `X-Chainlink-Signature`) |
| `/api/v1/auth/m2m_token` | POST | M2M автентифікація (Ed25519-підпис, без Bearer token) |

> **Примітка:** `/api/v1/oracle_callbacks` виключено з `authenticate_user!`, але захищено `before_action :verify_chainlink_signature!` — HMAC-SHA256 валідація заголовку `X-Chainlink-Signature` (ENV `CHAINLINK_HMAC_SECRET`). Якщо змінна не встановлена — HMAC пропускається з попередженням (dev/test). **При `WEB3_STRICT_MODE=true` (production) — відсутність `CHAINLINK_HMAC_SECRET` викликає `SecurityError` (fail-fast).**

### 1.4 M2M Auth (для прошивки Gateway)

Gateway-пристрої використовують **Ed25519-підпис** для отримання та оновлення Bearer-токену без логіна/пароля:

```
POST /api/v1/auth/m2m_token
{
  "did": "SNET-A1B2C3D4",
  "timestamp": "2026-03-29T12:00:00Z",
  "signature": "<Ed25519 sig of 'SNET-A1B2C3D4:2026-03-29T12:00:00Z'>"
}
```

- Ed25519 public key реєструється під час provisioning (поле `ed25519_public_key`) і зберігається в `hardware_keys.ed25519_public_key_hex`.
- Бекенд перевіряє підпис та timestamp (±5 хвилин) перед видачею токена.
- **Replay-захист (nonce):** SHA256-дайджест підпису зберігається в Redis із TTL 10 хв (`SET NX`). Повторне використання тієї ж `signature` повертає `401 Unauthorized` із повідомленням `"Replay attack detected"`. **[S6.1]** При Redis outage: fallback на Solid Cache (DB) — шлюзи не отримують `503`.
- Токен дійсний 30 днів. Для оновлення: `POST /api/v1/auth/m2m_token/refresh` з поточним Bearer token (§5.15.1), або повторний `POST /api/v1/auth/m2m_token` з Ed25519-підписом.
- Детальний опис: §5.14.

### 1.5 Тестове Покриття Безпеки

- `spec/initializers/rack_attack_spec.rb` — throttle правила `m2m_auth/ip` та `oracle_callbacks/ip`
- `spec/requests/api/v1/m2m_auth_controller_spec.rb` — некоректний Ed25519 підпис → 401; nonce replay → 401; Redis unavailable → DB fallback (Solid Cache)
- `spec/requests/api/v1/oracle_callbacks_controller_spec.rb` — replay callback → 409 Conflict; state machine guard
- `spec/requests/api/v1/actuators_controller_spec.rb` — відсутній `Idempotency-Key` → 400; ідемпотентний повтор → 202

---

## 2. Стандартний Формат Відповідей

### 2.1 Успішна відповідь

```json
{
  "data": [...],
  "pagy": {
    "page": 1,
    "limit": 20,
    "count": 142,
    "pages": 8
  }
}
```

Для одиночних ресурсів:

```json
{
  "tree": { ... },
  "telemetry": { ... }
}
```

### 2.2 Відповідь з помилкою

| HTTP Статус | Ключ | Приклад |
|---|---|---|
| 401 Unauthorized | `error` | `"Необхідна автентифікація. Брама закрита."` |
| 403 Forbidden | `error` | `"Недостатньо прав для цієї еволюції."` |
| 404 Not Found | `error` | `"Tree не знайдено в матриці лісу."` |
| 400 Bad Request | `error` | `"Відсутній обов'язковий параметр: provisioning"` |
| 409 Conflict | `error` | `"Пристрій з UID ... вже зареєстрований в системі."` |
| 422 Unprocessable | `errors` | `["Name can't be blank", ...]` |
| 429 Too Many Requests | `error` | `"Забагато спроб входу. Спробуйте через хвилину."` |
| 500 Internal Server Error | `error` | `"Збій у ядрі Океану. Повідомте Архітектора."` |

> **Примітка:** у `development` середовищі `StandardError` не перехоплюється — Rails показує детальний backtrace.

### 2.3 Пагінація

Всі list-ендпоінти підтримують стандартну пагінацію Pagy:

| Query-параметр | Тип | За замовчуванням | Опис |
|---|---|---|---|
| `page` | Integer | 1 | Номер сторінки |
| `limit` | Integer | 20 | Кількість записів на сторінку |

> **Виключення розміру сторінки:** `maintenance_records#index` використовує `items: 50` (не 20); `maintenance_records#photos` використовує `items: 6`.

Відповідь містить об'єкт `pagy`:

```json
{
  "page": 1,
  "limit": 20,
  "count": 142,
  "pages": 8
}
```

---

## 3. Ролева Модель Доступу (RBAC)

| Роль | Опис | Доступ |
|---|---|---|
| `investor` | Інвестор (за замовчуванням для OAuth) | Читання фінансових даних своєї організації |
| `forester` / `patrol` | Патрульний / Лісник | + Provisioning, Actuators, Maintenance Records, Oracle Visions. `patrol` є синонімом ролі `forester` (метод `forest_commander?` у моделі User охоплює обидві) |
| `admin` | Адміністратор організації | + Firmwares, TreeFamilies, Settings, AuditLogs, SystemHealth, Users, Simulate |
| `super_admin` | Суперадміністратор | + Organizations (глобальний доступ). `users#index` повертає **всіх** користувачів системи (`scope.all` через `UserPolicy::Scope`) — без фільтрації по org. |

---

## 4. Повна Таблиця Ендпоінтів

| # | Метод | Шлях | Controller#Action | Доступ | Опис |
|---|---|---|---|---|---|
| **🔐 Автентифікація** | | | | | |
| 1 | GET | `/api/v1/login` | `sessions#new` | 🌐 Public | Форма входу (HTML) |
| 2 | POST | `/api/v1/login` | `sessions#create` | 🌐 Public | Вхід (JSON: повертає Bearer token) |
| 3 | DELETE | `/api/v1/logout` | `sessions#destroy` | 🔑 Auth | Вихід |
| 4 | GET | `/api/v1/forgot_password` | `passwords#new` | 🌐 Public | Форма скидання пароля (HTML) |
| 5 | POST | `/api/v1/forgot_password` | `passwords#create` | 🌐 Public | Запит email скидання |
| 6 | GET | `/api/v1/reset_password` | `passwords#edit` | 🌐 Public | Форма нового пароля (HTML, `?token=`) |
| 7 | PATCH | `/api/v1/reset_password` | `passwords#update` | 🌐 Public | Встановити новий пароль |
| 8 | POST | `/api/v1/auth/m2m_token` | `m2m_auth#create` | 🌐 Public (Ed25519) | **M2M Auth:** Gateway отримує Bearer token через Ed25519-підпис DID |
| 8a | POST | `/api/v1/auth/m2m_token/refresh` | `m2m_auth#refresh` | 🔑 Auth (Bearer) | **M2M Refresh:** Оновлення Bearer token без Ed25519 re-auth |
| **🛡️ Безпека Акаунту** | | | | | |
| 9 | GET | `/api/v1/account_security` | `account_security#show` | �� Auth | MFA-стан, прив'язані identity |
| 10 | PATCH | `/api/v1/account_security/mfa` | `account_security#toggle_mfa` | 🔑 Auth | Увімкнути/вимкнути MFA |
| 11 | PATCH | `/api/v1/account_security/password` | `account_security#change_password` | 🔑 Auth | Змінити пароль |
| 12 | DELETE | `/api/v1/account_security/identities/:id` | `account_security#unlink_identity` | 🔑 Auth | Відв'язати OAuth-провайдера |
| 13 | PATCH | `/api/v1/account_security/identities/:id/lock` | `account_security#lock_identity` | 🔑 Auth | Заблокувати OAuth-ідентичність |
| 14 | PATCH | `/api/v1/account_security/identities/:id/unlock` | `account_security#unlock_identity` | 🔑 Auth | Розблокувати OAuth-ідентичність |
| **🏰 Dashboard** | | | | | |
| 15 | GET | `/api/v1/dashboard` | `dashboard#index` | 🔑 Auth | Зведена статистика організації |
| **👤 Користувачі та Організації** | | | | | |
| 16 | GET | `/api/v1/users/me` | `users#me` | 🔑 Auth | Профіль поточного користувача |
| 17 | GET | `/api/v1/users` | `users#index` | 👑 Admin | Список користувачів організації |
| 18 | GET | `/api/v1/users/:id` | `users#show` | 🔑 Auth | Профіль учасника організації (UserBlueprint `:crew`) |
| 19 | GET | `/api/v1/organizations` | `organizations#index` | 👑👑 SuperAdmin | Список усіх організацій |
| 20 | GET | `/api/v1/organizations/:id` | `organizations#show` | 👑👑 SuperAdmin | Деталі організації |
| **🌳 Кластери та Дерева** | | | | | |
| 21 | GET | `/api/v1/clusters` | `clusters#index` | 🔑 Auth | Список кластерів організації |
| 22 | GET | `/api/v1/clusters/:id` | `clusters#show` | 🔑 Auth | Деталі кластера |
| 23 | GET | `/api/v1/clusters/:cluster_id/trees` | `trees#index` | 🔑 Auth | Дерева кластера |
| 24 | GET | `/api/v1/clusters/:cluster_id/actuators` | `actuators#index` | 🌿 Forester | Актуатори кластера |
| 25 | GET | `/api/v1/trees/:id` | `trees#show` | 🔑 Auth | Паспорт дерева (солдата) |
| 26 | GET | `/api/v1/trees/:id/chronicle` | `trees#chronicle` | 🔑 Auth | Цифровий життєпис дерева (HTML Turbo Frame / JSON) |
| 27 | GET | `/api/v1/trees/:id/telemetry` | `telemetry#tree_history` | 🔑 Auth | Телеметрія дерева |
| **🧬 Біологічні Константи** | | | | | |
| 28 | GET | `/api/v1/tree_families` | `tree_families#index` | 👑 Admin | Список порід дерев |
| 29 | GET | `/api/v1/tree_families/:id` | `tree_families#show` | 👑 Admin | Деталі породи |
| 30 | GET | `/api/v1/tree_families/new` | `tree_families#new` | 👑 Admin | Форма нової породи |
| 31 | POST | `/api/v1/tree_families` | `tree_families#create` | 👑 Admin | Створити породу |
| 32 | GET | `/api/v1/tree_families/:id/edit` | `tree_families#edit` | 👑 Admin | Форма редагування |
| 33 | PATCH | `/api/v1/tree_families/:id` | `tree_families#update` | 👑 Admin | Оновити породу |
| **📡 Шлюзи та Телеметрія** | | | | | |
| 34 | GET | `/api/v1/gateways` | `gateways#index` | 🔑 Auth | Список Gateway (Queens) |
| 35 | GET | `/api/v1/gateways/:id` | `gateways#show` | 🔑 Auth | Деталі Gateway |
| 36 | GET | `/api/v1/gateways/:id/telemetry` | `telemetry#gateway_history` | 🔑 Auth | **Читання** збереженої телеметрії Gateway (Dashboard) |
| 37 | POST | `/api/v1/gateways/:id/telemetry` | `telemetry#gateway_uplink` | 🔑 Auth | **HTTP Uplink:** передати зашифрований батч телеметрії від Gateway |
| 38 | GET | `/api/v1/telemetry/live` | `telemetry#live` | 🔑 Auth | Live-стрім телеметрії (HTML/Turbo) |
| **💎 Гаманці та Контракти** | | | | | |
| 39 | GET | `/api/v1/wallets` | `wallets#index` | 🔑 Auth | Список гаманців організації |
| 40 | GET | `/api/v1/wallets/:id` | `wallets#show` | 🔑 Auth | Деталі гаманця + транзакції |
| 41 | GET | `/api/v1/wallets/:id/balance` | `wallets#balance` | 🔑 Auth | Баланс гаманця (JSON + Turbo Frame) |
| 42 | GET | `/api/v1/wallets/:id/metadata` | `wallets#metadata` | 🔑 Auth | Блокчейн-метадані (JSON + Turbo Frame) |
| 43 | GET | `/api/v1/contracts` | `contracts#index` | 🔑 Auth | Список NaaS-контрактів |
| 44 | GET | `/api/v1/contracts/:id` | `contracts#show` | 🔑 Auth | Деталі NaaS-контракту |
| 45 | GET | `/api/v1/contracts/stats` | `contracts#stats` | 🔑 Auth | Фінансова аналітика |
| **⚙️ Актуатори** | | | | | |
| 46 | GET | `/api/v1/actuators/:id` | `actuators#show` | 🌿 Forester | Деталі актуатора + історія команд |
| 47 | POST | `/api/v1/actuators/:id/execute` | `actuators#execute` | 🌿 Forester | Виконати команду на актуаторі |
| 48 | GET | `/api/v1/actuator_commands/:id` | `actuators#command_status` | 🌿 Forester | Статус команди актуатора |
| **🚀 Прошивка (OTA)** | | | | | |
| 49 | GET | `/api/v1/firmwares` | `firmwares#index` | 👑 Admin | Список версій прошивки |
| 50 | GET | `/api/v1/firmwares/new` | `firmwares#new` | 👑 Admin | Форма завантаження прошивки |
| 51 | POST | `/api/v1/firmwares` | `firmwares#create` | 👑 Admin | Завантажити нову прошивку |
| 52 | GET | `/api/v1/firmwares/inventory` | `firmwares#inventory` | 👑 Admin | Статистика версій на пристроях |
| 53 | POST | `/api/v1/firmwares/:id/deploy` | `firmwares#deploy` | 👑 Admin | Запустити OTA-оновлення |
| **⚠️ Тривоги та Обслуговування** | | | | | |
| 54 | GET | `/api/v1/alerts` | `alerts#index` | 🔑 Auth | Список EWS-тривог |
| 55 | GET | `/api/v1/alerts/:id` | `alerts#show` | 🔑 Auth | Деталі EWS-тривоги (з cluster, tree, coordinates, actionable?) |
| 56 | PATCH | `/api/v1/alerts/:id/resolve` | `alerts#resolve` | 🔑 Auth | Закрити тривогу |
| 57 | GET | `/api/v1/maintenance_records` | `maintenance_records#index` | 🌿 Forester | Журнал технічного обслуговування |
| 58 | GET | `/api/v1/maintenance_records/new` | `maintenance_records#new` | 🌿 Forester | Форма нового запису |
| 59 | POST | `/api/v1/maintenance_records` | `maintenance_records#create` | 🌿 Forester | Створити запис обслуговування |
| 60 | GET | `/api/v1/maintenance_records/:id` | `maintenance_records#show` | 🌿 Forester | Деталі запису |
| 61 | PATCH | `/api/v1/maintenance_records/:id` | `maintenance_records#update` | 🌿 Forester | Оновити запис |
| 62 | PATCH | `/api/v1/maintenance_records/:id/verify` | `maintenance_records#verify` | 🌿 Forester | Підтвердити hardware-стан (STM32) |
| 63 | GET | `/api/v1/maintenance_records/:id/photos` | `maintenance_records#photos` | 🌿 Forester | Фото запису (пагінація) |
| 64 | DELETE | `/api/v1/maintenance_records/:maintenance_record_id/photos/:id` | `maintenance_record_photos#destroy` | 🌿 Forester | Видалити фото |
| **⊙ Оракул (AI Insights)** | | | | | |
| 65 | GET | `/api/v1/oracle_visions` | `oracle_visions#index` | 🌿 Forester | AI-прогнози та SCC-врожайність |
| 66 | POST | `/api/v1/oracle_visions/simulate` | `oracle_visions#simulate` | 👑 Admin | Запустити Lorenz-симуляцію |
| 67 | GET | `/api/v1/oracle_visions/stream_config?cluster_id=:id` | `oracle_visions#stream_config` | 🌿 Forester | Конфіг підписки на стрім. `cluster_id` — обов'язковий query param. 404 при невідомому `cluster_id`. |
| **⛓️ Блокчейн** | | | | | |
| 68 | GET | `/api/v1/blockchain_transactions` | `blockchain_transactions#index` | 🔑 Auth | Список блокчейн-транзакцій |
| 69 | GET | `/api/v1/blockchain_transactions/:id` | `blockchain_transactions#show` | 🔑 Auth | Деталі транзакції |
| 70 | GET | `/api/v1/blockchain_transactions/:id/on_chain` | `blockchain_transactions#on_chain` | 🔑 Auth | On-chain верифікація (Turbo Frame) |
| 71 | POST | `/api/v1/oracle_callbacks` | `oracle_callbacks#create` | 🌐 Public (HMAC) | Chainlink Oracle callback — захищено `X-Chainlink-Signature` HMAC-SHA256 |
| **🔔 Сповіщення** | | | | | |
| 72 | GET | `/api/v1/notifications/settings` | `notifications#settings` | 🔑 Auth | Поточні канали сповіщень |
| 73 | PATCH | `/api/v1/notifications/settings` | `notifications#update_settings` | 🔑 Auth | Оновити канали сповіщень |
| **📊 Звіти** | | | | | |
| 74 | GET | `/api/v1/reports` | `reports#index` | 🔑 Auth | Зведена аналітика організації |
| 75 | GET | `/api/v1/reports/carbon_absorption` | `reports#carbon_absorption` | 🔑 Auth | Звіт CO₂-поглинання (JSON/CSV/PDF) |
| 76 | GET | `/api/v1/reports/financial_summary` | `reports#financial_summary` | 🔑 Auth | Фінансовий звіт (JSON/CSV/PDF) |
| **🧠 Налаштування** | | | | | |
| 77 | GET | `/api/v1/settings` | `settings#show` | 👑 Admin | Налаштування організації |
| 78 | PATCH | `/api/v1/settings` | `settings#update` | 👑 Admin | Оновити налаштування |
| **👁️ Аудит** | | | | | |
| 79 | GET | `/api/v1/audit_logs` | `audit_logs#index` | 👑 Admin | Журнал дій (AuditLog) |
| 80 | GET | `/api/v1/audit_logs/:id` | `audit_logs#show` | 👑 Admin | Деталі події аудиту |
| **⚡ Ініціація Пристроїв** | | | | | |
| 81 | GET | `/api/v1/provisioning/new` | `provisioning#new` | 🌿 Forester | Форма реєстрації пристрою |
| 82 | POST | `/api/v1/provisioning/register` | `provisioning#register` | 🌿 Forester | **Реєстрація нового вузла (Tree/Gateway) — HKDF key derivation** |
| **⚙️ Системний Моніторинг** | | | | | |
| 83 | GET | `/api/v1/system_health` | `system_health#show` | 👑 Admin | Стан CoAP/Sidekiq/DB |
| 84 | GET | `/api/v1/system_audits` | `system_audits#index` | 🔑 Auth | Аудит синхронізації DB↔Blockchain |

**Легенда:**

| Символ | Значення |
|---|---|
| 🌐 Public | Без автентифікації |
| 🌐 Public (Ed25519) | Без Bearer token, але верифікується Ed25519-підпис |
| 🌐 Public (HMAC) | Без Bearer token, але верифікується HMAC-SHA256 підпис |
| 🔑 Auth | Будь-який автентифікований користувач |
| 🌿 Forester | Роль `forester` або вище |
| 👑 Admin | Роль `admin` або `super_admin` |
| 👑👑 SuperAdmin | Лише роль `super_admin` |

---

## 5. Ключові Ендпоінти: Детальний Опис

### 5.1 POST `/api/v1/login` — Вхід та отримання Bearer Token

**Призначення:** Першочерговий ендпоінт для API-клієнтів та прошивки Gateway.

**Request Body (JSON або form-data):**

```json
{
  "email": "operator@forest.ua",
  "password": "Secure12CharPass!"
}
```

**Success Response `201 Created`:**

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
    "id": 42,
    "email": "operator@forest.ua",
    "full_name": "Ivan Kovalenko",
    "role": "forester"
  }
}
```

**Error Response `401 Unauthorized`:**

```json
{
  "error": "Невірні координати доступу."
}
```

> **Rate Limit:** 5 запитів за 1 хвилину. При перевищенні — HTTP 429.

> **M2M Gateway:** для прошивки шлюзу реалізовано `POST /api/v1/auth/m2m_token` — Ed25519-підпис DID без логіна/пароля (§5.14). Токен оновлюється перед закінченням 30-денного терміну.

---

### 5.2 POST `/api/v1/provisioning/register` — Реєстрація Вузла (Ключовий для Gateway)

**Призначення:** Ініціація нового Soldier (дерева) або Queen (шлюзу). Повертає DID для прошивки.

**Доступ:** `Authorization: Bearer <token>` з роллю `forester` або вище.

**Request Body:**

```json
{
  "provisioning": {
    "hardware_uid": "STM32-UID-A1B2C3D4",
    "device_type": "tree",
    "cluster_id": 7,
    "family_id": 3,
    "latitude": 50.4501,
    "longitude": 30.5234
  }
}
```

Для реєстрації Gateway (`device_type: "gateway"`):

```json
{
  "provisioning": {
    "hardware_uid": "GW-UID-E5F6G7H8",
    "device_type": "gateway",
    "cluster_id": 7,
    "latitude": 50.4510,
    "longitude": 30.5245
  }
}
```

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `hardware_uid` | String | ✅ | Унікальний UID мікроконтролера STM32 |
| `device_type` | String | ✅ | `"tree"` або `"gateway"` |
| `cluster_id` | Integer | ✅ | ID кластера для прив'язки |
| `family_id` | Integer | Лише для `tree` | ID породи дерева (TreeFamily) |
| `latitude` | Float | ✅ | Широта GPS |
| `longitude` | Float | ✅ | Довгота GPS |
| `ed25519_public_key` | String (HEX) | Опційно | Ed25519 public key для M2M Auth (Gateway) |

**Success Response `201 Created` (Production — HKDF mode):**

```json
{
  "did": "SNET-A1B2C3D4",
  "key_derivation": "hkdf-sha256",
  "device": {
    "id": 156,
    "did": "SNET-A1B2C3D4",
    "status": "active",
    "cluster_id": 7
  }
}
```

> **Zero-Trust: AES-ключ не передається по мережі.** Бекенд та прошивка незалежно деривують однаковий ключ через `HKDF-SHA256(ikm: PROVISIONING_MASTER_KEY, salt: device_uid, info: "silken-aes-256-device-key")`. Встановіть `PROVISIONING_MASTER_KEY` в ENV для активації Production режиму.

**Success Response `201 Created` (TRL4 lab mode — `PROVISIONING_MASTER_KEY` не встановлено):**

```json
{
  "did": "SNET-A1B2C3D4",
  "aes_key": "2B7E151628AED2A6ABF7158809CF4F3C",
  "key_derivation": "hkdf-sha256",
  "warning": "TRL4 lab mode: AES key included in response. Set PROVISIONING_MASTER_KEY for production HKDF derivation.",
  "device": { ... }
}
```

> **`aes_key` в TRL4 mode повертається лише один раз** для ручного прошивання на лабораторному стенді. Зберігайте в захищеній пам'яті (Flash Option Bytes або OTP-region). Деталі: `docs/FIRMWARE.md`. Повторний запит для того ж `hardware_uid` поверне HTTP 409.

**Conflict Response `409 Conflict`:**

```json
{
  "error": "Пристрій з UID STM32-UID-A1B2C3D4 вже зареєстрований в системі."
}
```

---

### 5.3 GET `/api/v1/trees/:id/chronicle` — Цифровий Життєпис Дерева

**Доступ:** `Authorization: Bearer <token>`

**Призначення:** Повертає хронологічний список усіх значущих подій у житті дерева: AI-інсайти (homeostasis / stress / fraud), EWS-тривоги (з відновленням), записи технічного обслуговування та підтверджені blockchain-транзакції. Агрегується на льоту сервісом `TreeChronicleService` — без нових таблиць.

**Content Negotiation:**
- `Accept: application/json` — JSON масив entries з пагінацією
- `Accept: text/html` — Phlex компонент `Trees::Chronicle` (Turbo Frame, `layout: false`) для lazy-loading у `Trees::Show`

**Query Parameters:**

| Параметр | Тип | За замовчуванням | Опис |
|---|---|---|---|
| `page` | Integer | 1 | Сторінка |

**Success Response `200 OK` (JSON):**

```json
{
  "data": [
    {
      "date": "2026-03-15T10:30:00Z",
      "event_type": "homeostasis",
      "icon": "◉",
      "title": "Deep Homeostasis",
      "description": "Tree entered deep homeostasis. Z-value stable: 4.2891 σ",
      "severity": "stable",
      "source_type": "AiInsight",
      "source_id": 4512
    },
    {
      "date": "2026-03-10T08:00:00Z",
      "event_type": "alert",
      "icon": "🔥",
      "title": "Fire Alert: 65.2°C",
      "description": "Critical temperature threshold exceeded. Sensor value: 65.2°C",
      "severity": "critical",
      "source_type": "EwsAlert",
      "source_id": 88
    }
  ],
  "pagy": {
    "page": 1,
    "limit": 20,
    "count": 87,
    "pages": 5
  }
}
```

| Поле | Тип | Опис |
|---|---|---|
| `event_type` | String | `homeostasis / stress / fraud / alert / recovery / maintenance / minting` |
| `severity` | String | `stable / info / warning / critical` |
| `source_type` | String | `AiInsight / EwsAlert / MaintenanceRecord / BlockchainTransaction` |
| `source_id` | Integer | ID вихідного запису |

---

### 5.4 GET `/api/v1/trees/:id/telemetry` — Телеметрія Дерева

**Доступ:** `Authorization: Bearer <token>`

**Query Parameters:**

| Параметр | Тип | За замовчуванням | Опис |
|---|---|---|---|
| `days` | Integer | 7 | Глибина вибірки (у днях) |

**Success Response `200 OK`:**

```json
{
  "did": "SNET-A1B2C3D4",
  "unit": "kOhm",
  "timestamps": [1710000000, 1710003600, 1710007200],
  "impedance":  [12.45, 12.38, 13.01],
  "temperature": [18.2, 18.5, 17.9],
  "stress_index": [0.021, 0.027, 0.014]
}
```

| Поле | Опис |
|---|---|
| `timestamps` | Unix-часові мітки (секунди) |
| `impedance` | Біоімпеданс (кОм) — первинний сигнал EBFC |
| `temperature` | Температура (°C) |
| `stress_index` | Індекс стресу: `1 - (z_value / baseline_impedance)` |

---

### 5.5 GET `/api/v1/gateways/:id/telemetry` — Читання Телеметрії Gateway (Queen)

> **Важливо:** Цей ендпоінт призначений **лише для читання** збереженої телеметрії (Dashboard / Monitoring). Основний канал uplink — **CoAP/UDP на порт 5683** (CoAP listener daemon). Для HTTP fallback використовується `POST /api/v1/gateways/:id/telemetry` (§5.15).

**Query Parameters:**

| Параметр | Тип | За замовчуванням | Опис |
|---|---|---|---|
| `days` | Integer | 7 | Глибина вибірки (у днях) |

**Success Response `200 OK`:**

```json
{
  "uid": "GW-UID-E5F6G7H8",
  "timestamps": [1710000000, 1710003600],
  "voltage":    [3350, 3320],
  "signal":     [18, 22],
  "temp":       [24.1, 25.3]
}
```

| Поле | Опис |
|---|---|
| `voltage` | Напруга живлення (мВ) |
| `signal` | Рівень сигналу LTE (CSQ, 0–31) |
| `temp` | Температура модуля (°C) |

---

### 5.5b GET `/api/v1/wallets/:id/balance` — Баланс Гаманця

**Доступ:** 🔑 Auth (будь-яка роль, Pundit scope).

**Dual-Format:** HTML (Phlex Turbo Frame для lazy-load) + JSON (для API consumers).

**JSON Response `200 OK`:**

```json
{
  "data": {
    "id": 42,
    "scc_balance": "1250.500000",
    "locked_balance": "100.000000",
    "available_balance": "1150.500000",
    "esg_retired_balance": "25.000000"
  }
}
```

| Поле | Тип | Опис |
|------|-----|------|
| `scc_balance` | Decimal (string) | Загальний баланс SCC (alias для `balance`) |
| `locked_balance` | Decimal (string) | Заблоковано для pending blockchain TX |
| `available_balance` | Decimal (string) | Доступно для витрат (`scc_balance - locked_balance`) |
| `esg_retired_balance` | Decimal (string) | ESG-retired SCC (назавжди виведені з обігу) |

**HTML Response:** Повертає `Wallets::BalanceFrame` Phlex-компонент (Turbo Frame `wallet_balance_frame_{id}`), без layout.

---

### 5.5c GET `/api/v1/wallets/:id/metadata` — Блокчейн-Метадані Гаманця

**Доступ:** 🔑 Auth (будь-яка роль, Pundit scope).

**Dual-Format:** HTML (Phlex Turbo Frame для lazy-load) + JSON (для API consumers).

**JSON Response `200 OK`:**

```json
{
  "data": {
    "id": 42,
    "crypto_public_address": "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
    "locked_balance": "100.000000",
    "available_balance": "1150.500000",
    "esg_retired_balance": "25.000000",
    "network": "Polygon PoS (Mainnet)"
  }
}
```

| Поле | Тип | Опис |
|------|-----|------|
| `crypto_public_address` | String / null | Polygon/Ethereum адреса гаманця |
| `locked_balance` | Decimal (string) | Заблоковано для pending TX |
| `available_balance` | Decimal (string) | Доступно для витрат |
| `esg_retired_balance` | Decimal (string) | ESG-retired SCC |
| `network` | String | Мережа блокчейну (`"Polygon PoS (Mainnet)"`) |

**HTML Response:** Повертає `Wallets::MetadataFrame` Phlex-компонент (Turbo Frame `wallet_metadata_frame_{id}`), без layout.

---

### 5.6 POST `/api/v1/actuators/:id/execute` — Виконати Команду

**Доступ:** Роль `forester` або вище.

**Request Headers (JSON):**

| Заголовок | Обов'язковий | Опис |
|---|---|---|
| `Idempotency-Key` | ✅ (JSON запити) | Унікальний ключ клієнта (UUID або будь-який рядок). Запобігає дублюванню фізичних команд при мережевих retry. Відповідь кешується на 24 год у Rails.cache. |

> **Важливо:** для JSON-запитів (`Content-Type: application/json`) заголовок `Idempotency-Key` є обов'язковим. Відсутність заголовка повертає `400 Bad Request`. Turbo Stream-запити (`format.turbo_stream`) не потребують цього заголовка.

**Request Body:**

```json
{
  "action_payload": "VALVE_OPEN",
  "duration_seconds": 300
}
```

| Параметр | Тип | Опис |
|---|---|---|
| `action_payload` | String | Рядкова команда для актуатора (залежить від `device_type`) |
| `duration_seconds` | Integer | Тривалість дії (опційно) |

**Success Response `202 Accepted`:**

```json
{
  "command_id": 89,
  "status": "accepted"
}
```

> **Idempotency:** повторний запит із тим самим `Idempotency-Key` повертає закешовану відповідь (без створення нової команди).

**Conflict Response `409 Conflict`:**

```json
{
  "error": "Актуатор вже має активну команду. Зачекайте на її завершення."
}
```

---

### 5.7 POST `/api/v1/firmwares/:id/deploy` — OTA-розгортання Прошивки

**Доступ:** Роль `admin`.

**Request Body:**

```json
{
  "cluster_id": 7,
  "target_type": "Tree",
  "canary_percentage": 10
}
```

| Параметр | Тип | Опис |
|---|---|---|
| `cluster_id` | Integer | ID кластера (якщо відсутній — оновлення для всього лісу) |
| `target_type` | String | `"Tree"` або `"Gateway"` |
| `canary_percentage` | Integer | 1–100. За замовчуванням 100 (всі пристрої). Canary: поступове розгортання |

**Success Response `202 Accepted`:**

```json
{
  "message": "Наказ на еволюцію v1.4.2 відправлено в ефір.",
  "target": "Кластер #7",
  "canary_percentage": 10
}
```

---

### 5.8 POST `/api/v1/firmwares` — Завантаження Нової Прошивки

**Доступ:** Роль `admin`.  
**Content-Type:** `multipart/form-data`

| Параметр | Тип | Опис |
|---|---|---|
| `firmware[version]` | String | Версія (напр. `"1.4.2"`) |
| `firmware[binary_file]` | File | Бінарний файл прошивки (макс. 20 МБ) |
| `firmware[target_hardware]` | String | `"STM32WLE5JC"` тощо |
| `firmware[notes]` | String | Нотатки до версії (опційно) |
| `firmware[target_hardware_type]` | String | `"Tree"` або `"Gateway"` |
| `firmware[tree_family_id]` | Integer | Прив'язка до породи (опційно) |

**Success Response `201 Created`:**

```json
{
  "message": "Нову еволюцію v1.4.2 завантажено в Океан.",
  "firmware": {
    "id": 12,
    "version": "1.4.2",
    "target_hardware": "STM32WLE5JC",
    "file_size": 245760,
    "checksum": "A3F2...",
    "created_at": "2026-03-22T17:00:00Z"
  }
}
```

---

### 5.9 POST `/api/v1/oracle_callbacks` — Chainlink Oracle Callback

**Доступ:** 🌐 Публічний (без Bearer token — machine-to-machine, захищено HMAC-SHA256).

> **Безпека:** `OracleCallbacksController` має `before_action :verify_chainlink_signature!` — перевіряє `HMAC-SHA256(raw_body, CHAINLINK_HMAC_SECRET)` та порівнює з `X-Chainlink-Signature` через `ActiveSupport::SecurityUtils.secure_compare` (timing-safe). Якщо `CHAINLINK_HMAC_SECRET` не встановлено — HMAC пропускається з попередженням у логах (dev/test mode).
>
> **🔴 SECURITY REQUIREMENT (SEC.5):** При `WEB3_STRICT_MODE=true` (production) відсутність `CHAINLINK_HMAC_SECRET` викликає `SecurityError` (fail-fast). Це запобігає ситуації, коли misconfigured production залишає oracle callback endpoint без HMAC-захисту, що дозволило б зловмиснику фальсифікувати `oracle_status_fulfilled?` та ініціювати неавторизований мінтинг SCC. Перед mainnet deploy **обов'язково** встановити `CHAINLINK_HMAC_SECRET` та `WEB3_STRICT_MODE=true` в ENV.

**Request Headers:**

| Заголовок | Обов'язковий | Опис |
|---|---|---|
| `X-Chainlink-Signature` | ✅ (Production) | HMAC-SHA256(raw_body, `CHAINLINK_HMAC_SECRET`) — підпис від Chainlink DON |

**Request Body:**

```json
{
  "chainlink_request_id": "0xabc123def456...",
  "success": true,
  "created_at": "2026-03-22T15:30:00.000000Z"
}
```

| Параметр | Тип | Опис |
|---|---|---|
| `chainlink_request_id` | String | Унікальний ID запиту Chainlink (обов'язковий) |
| `success` | Boolean | Результат верифікації Oracle |
| `created_at` | ISO8601 | Час створення TelemetryLog (оптимізація партиційного pruning) |
| `error` | String | Повідомлення про помилку (якщо `success: false`) |

**Success Response `200 OK` (fulfilled):**

```json
{
  "status": "fulfilled",
  "telemetry_log_id": 98765
}
```

При успіху автоматично запускаються:
- `MintCarbonCoinWorker` — мінтинг SCC/SFC на Polygon
- `SolanaMicroRewardWorker` — миттєва мікро-винагорода власнику дерева

**Можливі помилки:**

| HTTP Status | Умова |
|---|---|
| `401 Unauthorized` | Відсутній або невалідний `X-Chainlink-Signature` |
| `404 Not Found` | `chainlink_request_id` не знайдено у `TelemetryLog` |

**Success Response `200 OK` (failed):**

```json
{
  "status": "failed",
  "telemetry_log_id": 98765,
  "error": "Oracle verification timeout"
}
```

---

### 5.9b GET `/api/v1/oracle_visions` — AI Прогнози (Oracle Visions Index)

**Доступ:** Роль `forester` або вище.

**Success Response `200 OK`:**

```json
{
  "visions": [
    {
      "id": 1,
      "cluster_id": 7,
      "target_date": "2026-04-01",
      "stress_index": 0.42,
      "summary": "...",
      "recommendation": { "priority": "high", "action_required": "..." }
    }
  ],
  "yield_forecast": 12.5
}
```

| Поле | Тип | Опис |
|---|---|---|
| `visions` | Array | Масив `AiInsight` (до 10 записів, `upcoming`, сортування за `target_date asc`) |
| `yield_forecast` | Float | Прогнозована SCC-врожайність організації |

---

### 5.10 POST `/api/v1/oracle_visions/simulate` — Lorenz Симуляція

**Доступ:** Роль `admin`.

**Request Body:**

```json
{
  "cluster_id": 7,
  "variables": {
    "sigma": 10,
    "rho": 28,
    "beta": 2.6667
  }
}
```

**Success Response `202 Accepted`:**

```json
{
  "message": "Оракул почав симуляцію.",
  "job_id": "abc123def456789abc123def"
}
```

> **`job_id`** — це Sidekiq JID (рядок ~24 hex-символи), а не числовий id. Використовується для відстеження статусу симуляції.

---

### 5.11 POST `/api/v1/maintenance_records` — Фіксація Обслуговування

**Доступ:** Роль `forester` або вище.  
**Content-Type:** `multipart/form-data` (підтримка завантаження фото)

| Параметр | Тип | Опис |
|---|---|---|
| `maintenance_record[maintainable_type]` | String | `"Tree"` або `"Gateway"` |
| `maintenance_record[maintainable_id]` | Integer | ID пристрою |
| `maintenance_record[action_type]` | String | Тип дії (напр. `installation`, `repair`, `inspection`) |
| `maintenance_record[notes]` | String | Опис виконаних робіт |
| `maintenance_record[performed_at]` | DateTime | Час виконання |
| `maintenance_record[labor_hours]` | Float | Витрачені людино-години |
| `maintenance_record[parts_cost]` | Decimal | Вартість запчастин |
| `maintenance_record[hardware_verified]` | Boolean | STM32 підтвердив стан |
| `maintenance_record[latitude]` | Float | GPS широта |
| `maintenance_record[longitude]` | Float | GPS довгота |
| `maintenance_record[photos][]` | File | Фото (масив файлів, опційно) |
| `maintenance_record[ews_alert_id]` | Integer | Прив'язка до EWS-тривоги (опційно) |

**Success Response `201 Created`:**

```json
{
  "message": "Запис про зцілення зафіксовано. Екосистема оновлена.",
  "record": { ... }
}
```

---

### 5.12 GET `/api/v1/alerts` — EWS-Тривоги

**Query Parameters:**

| Параметр | Тип | Опис |
|---|---|---|
| `status` | String | `"active"` (за замовчуванням), `"resolved"` |
| `severity` | String | Фільтр за рівнем небезпеки |
| `cluster_id` | Integer | Фільтр за кластером |

**Success Response `200 OK`:**

```json
{
  "data": [
    {
      "id": 55,
      "status": "active",
      "severity": "critical",
      "cluster": { "id": 7, "name": "Sector Alpha" },
      "tree": { "id": 101, "did": "SNET-A1B2C3D4", "latitude": 50.4501, "longitude": 30.5234 },
      "coordinates": [50.4501, 30.5234],
      "actionable?": true,
      "created_at": "2026-03-22T14:00:00Z"
    }
  ],
  "pagy": { "page": 1, "limit": 20, "count": 3, "pages": 1 }
}
```

---

### 5.13 GET `/api/v1/system_health` — Стан Системи

**Доступ:** Роль `admin`.

**Success Response `200 OK`:**

```json
{
  "checked_at": "2026-03-22T17:10:00Z",
  "coap_listener": {
    "alive": true,
    "port": 5683
  },
  "sidekiq": {
    "enqueued": 12,
    "processed": 450000,
    "failed": 3,
    "workers_size": 8,
    "queues": {
      "uplink": 2,
      "alerts": 0,
      "default": 10
    }
  },
  "database": {
    "connected": true
  }
}
```

---

### 5.14 GET `/api/v1/reports/carbon_absorption` — CO₂ Звіт

Підтримує мультиформатну відповідь через HTTP `Accept` заголовок:

| Accept | Формат | Опис |
|---|---|---|
| `application/json` | JSON | API-відповідь |
| `text/csv` | CSV | Стрімінговий CSV для аудиторів |
| `application/pdf` | PDF | Prawn PDF для інвесторів |

**Success Response `200 OK` (JSON):**

```json
{
  "report": "carbon_absorption",
  "organization": "Forest Corp",
  "generated_at": "2026-03-22T17:10:00Z",
  "data": {
    "total_carbon_points": 1250000,
    "wallets_count": 342,
    "trees_active": 8940,
    "trees_total": 9120
  }
}
```

---

### 5.15 POST `/api/v1/auth/m2m_token` — M2M Автентифікація Gateway (Ed25519)

**Призначення:** Gateway-пристрої отримують та оновлюють Bearer-токен без логіна/пароля через Ed25519-підпис.

**Доступ:** 🌐 Публічний (без Bearer token), але верифікується Ed25519-підпис.

**Передумови:**
- Ed25519 public key зареєстровано під час provisioning (поле `ed25519_public_key` в `POST /provisioning/register`).
- Збережено в `hardware_keys.ed25519_public_key_hex`.

**Request Body:**

```json
{
  "did": "SNET-A1B2C3D4",
  "timestamp": "2026-03-29T12:00:00Z",
  "signature": "a3f2b1c4d5e6..."
}
```

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `did` | String | ✅ | Device ID (реєструється при provisioning) |
| `timestamp` | ISO8601 | ✅ | Поточний час UTC (максимальне відхилення ±5 хв від серверного часу) |
| `signature` | String (HEX) | ✅ | Ed25519 підпис рядка `"#{did}:#{timestamp}"` приватним ключем пристрою |

**Replay-захист:**

SHA256-дайджест значення `signature` зберігається в Redis як nonce (`SET NX`, TTL 10 хв). Перший запит проходить — всі наступні з тією ж підписом повертають `401 Unauthorized` (`"Replay attack detected"`). **[S6.1]** Якщо Redis недоступний — fallback на Solid Cache (DB-backed): nonce зберігається в БД з TTL 10 хв. Шлюзи залишаються активними замість отримання `503 Service Unavailable`.

**Підпис на прошивці (псевдокод):**

```c
// message = "SNET-A1B2C3D4:2026-03-29T12:00:00Z"
uint8_t sig[64];
ed25519_sign(sig, message, strlen(message), private_key);
// hex-encode sig → signature field
```

**Success Response `201 Created`:**

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "device_uid": "SNET-A1B2C3D4",
  "expires_in": "30 days",
  "token_type": "Bearer"
}
```

**Error Responses:**

| Статус | Причина |
|---|---|
| 404 Not Found | `did` не знайдено в `hardware_keys` |
| 422 Unprocessable | Ed25519 public key не зареєстровано для пристрою |
| 400 Bad Request | Невалідний формат `timestamp` |
| 401 Unauthorized | `timestamp` прострочено (>5 хв) або підпис не валідний або повтор нonce (Replay attack) |
| 503 Service Unavailable | Redis недоступний ТА Solid Cache fallback також відмовив |

---

### 5.15.1 POST `/api/v1/auth/m2m_token/refresh` — M2M Token Refresh (Sliding Window)

**Призначення:** Оновлення Bearer-токена без повторної Ed25519 автентифікації. Gateway надсилає поточний валідний токен і отримує новий 30-денний токен.

**Доступ:** 🔑 Автентифікований (Bearer token обов'язковий).

**Мотивація (S3.4):** 30-денний M2M token може протухнути під час тривалого uplink. Цей ендпоінт дозволяє Gateway автоматично оновити токен без Ed25519 криптографії (яка потребує CPU + часу).

**Request:**

```
POST /api/v1/auth/m2m_token/refresh
Authorization: Bearer <current_valid_token>
```

Тіло запиту не потрібне — автентифікація відбувається через Bearer header.

**Success Response `201 Created`:**

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "expires_in": "30 days",
  "token_type": "Bearer",
  "refreshed_at": "2026-04-18T13:00:00Z"
}
```

**Error Responses:**

| Статус | Причина |
|---|---|
| 401 Unauthorized | Токен прострочений, невалідний або відсутній |

**Firmware flow (псевдокод):**

```c
// Перевірка перед кожним CoAP flush:
if (days_until_token_expiry() < 7) {
    http_post("/api/v1/auth/m2m_token/refresh",
              headers: {"Authorization": "Bearer " + current_token});
    // Зберегти новий token + timestamp
}
```

---

### 5.16 POST `/api/v1/gateways/:id/telemetry` — HTTP Telemetry Uplink

**Призначення:** HTTP fallback для передачі зашифрованого батчу телеметрії від Gateway до бекенду. Основний канал — CoAP/UDP порт 5683 (daemon).

**Сценарії використання HTTP uplink:**
1. CoAP/UDP заблоковано корпоративним фаєрволом або LTE-обмеженнями
2. Phase 3 Starlink Mini з TCP/IP мостом (ESP32/SIM8200G-M2)
3. Ручне завантаження телеметрії через Dashboard (forester upload)

**Доступ:** `Authorization: Bearer <token>` (будь-який автентифікований користувач організації).

**Request Body:**

```json
{
  "payload": "base64_encoded_binary_batch..."
}
```

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `payload` | String (Base64) | ✅ | Base64-encoded бінарний батч: `[IV:16][AES-256-CBC encrypted records]`. Формат ідентичний CoAP uplink |

**Success Response `202 Accepted`:**

```json
{
  "status": "accepted",
  "gateway_uid": "GW-UID-E5F6G7H8"
}
```

> **Обробка:** `UnpackTelemetryWorker.perform_async(payload, request.remote_ip, gateway_uid)` — сигнатура ідентична виклику з CoAP daemon (`lib/daemons/coap_listener`). Gateway також оновлює `last_seen_at` та IP-адресу.

---

## 6. Приклад Взаємодії Gateway (Queen) з API

Нижче наведено типовий lifecycle запитів від прошивки Gateway.

> **Примітка:** Основний канал **передачі телеметрії** від Queen до Backend — **CoAP/UDP на порт 5683** (CoAP listener daemon). HTTP API використовується для управління, реєстрації та звітності. HTTP fallback uplink реалізовано як `POST /api/v1/gateways/:id/telemetry`.

```text
1. [Одноразово] POST /api/v1/provisioning/register
   → Передає STM32 UID + Ed25519 public key (опційно).
   → Відповідь містить DID та key_derivation: "hkdf-sha256".
   → Обидві сторони математично деривують AES-ключ через HKDF без передачі по мережі.
   → Встановіть PROVISIONING_MASTER_KEY в ENV для Production режиму.

2. [За потреби] POST /api/v1/auth/m2m_token
   → Шлюз підписує "did:timestamp" Ed25519 private key.
   → Отримує 30-денний Bearer token без логіна/пароля.
   → Повторювати перед закінченням терміну дії.

3. [Регулярно] CoAP PUT → порт 5683 (основний канал uplink)
   → 21-байтовий зашифрований AES-256-CBC батч від кожного Soldier → Queen → бекенд.

   [Fallback] POST /api/v1/gateways/:id/telemetry
   → Base64-encoded бінарний батч у тілі запиту (якщо CoAP/UDP недоступний).
   → НЕ використовувати GET для передачі телеметрії.

4. [За потребою] GET /api/v1/oracle_visions/stream_config?cluster_id=7
   → Отримати токен підписки на ActionCable/SolidCable стрім.

5. [Автоматично] POST /api/v1/oracle_callbacks
   → Chainlink викликає цей endpoint після on-chain верифікації.
   → Авторизація через HMAC-SHA256 підпис в заголовку X-Chainlink-Signature.
   → Встановіть CHAINLINK_HMAC_SECRET в ENV для Production режиму.
```

---

## 7. Заголовки Запитів

| Заголовок | Обов'язковий | Значення |
|---|---|---|
| `Authorization` | ✅ (для захищених ендпоінтів) | `Bearer <token>` |
| `Content-Type` | ✅ (для POST/PATCH з body) | `application/json` або `multipart/form-data` |
| `Accept` | Опційно | `application/json` (за замовчуванням) |
| `X-Chainlink-Signature` | ✅ (Production) для `/oracle_callbacks` | `HMAC-SHA256(raw_body, CHAINLINK_HMAC_SECRET)` — підпис від Chainlink DON |
| `Idempotency-Key` | ✅ (JSON) для `POST /actuators/:id/execute` | Унікальний клієнтський ключ (UUID рекомендовано). Запобігає дублюванню фізичних команд при retry. |
