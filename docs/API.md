# API Reference

Base URL: `/api/v1`

## Authentication

All endpoints require authentication unless noted otherwise.

**Bearer Token:** Include `Authorization: Bearer <token>` header. Tokens are generated via `POST /api/v1/login`.

**Session:** Cookie-based session authentication is also supported for dashboard access.

## Endpoints

### Sessions

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/login` | None | Login with email + password, returns Bearer token |
| `DELETE` | `/logout` | Required | Destroy current session |

**POST /login**

Request:
```json
{ "email_address": "user@example.com", "password": "secret" }
```

Response (200):
```json
{ "token": "eyJfcmFpbHMi...", "user": { "id": 1, "email_address": "...", "role": "forester" } }
```

---

### Dashboard

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/dashboard` | Required | Summary: active trees, online gateways, open alerts, recent transactions |

---

### Users

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/users/me` | Required | Current user profile |
| `GET` | `/users` | Admin | List organization users |
| `GET` | `/users/:id` | Admin | User profile |

**GET /users/me** - Returns `{ id, email_address, first_name, last_name, role, full_name, last_seen_at }`

---

### Clusters

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/clusters` | Required | List all cluster sectors with GeoJSON |
| `GET` | `/clusters/:id` | Required | Cluster details with gateways, contracts, health metrics |

**GET /clusters/:id** - Returns `{ id, name, region, geojson_polygon, health_index, total_active_trees, geo_center, active_threats }`

---

### Trees

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/clusters/:cluster_id/trees` | Required | List active trees in cluster |
| `GET` | `/trees/:id` | Required | Tree passport with telemetry, wallet, insights |

**GET /trees/:id** - Returns `{ id, did, status, latitude, longitude, tree_family_name, current_stress, under_threat, wallet_balance, latest_telemetry }`

---

### Tree Families (DNA Registry)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/tree_families` | Required | List all species profiles with Lorenz thresholds |
| `POST` | `/tree_families` | Admin | Register new species |
| `GET` | `/tree_families/:id` | Required | Species details (`critical_z_min`, `critical_z_max`) |
| `PATCH` | `/tree_families/:id` | Admin | Update thresholds |
| `DELETE` | `/tree_families/:id` | Admin | Remove species |

---

### Gateways (Queens)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/gateways` | Required | List gateways (Queens) with online/offline status |
| `GET` | `/gateways/:id` | Required | Gateway details: UID, state, voltage, signal, actuators |
| `GET` | `/gateways/:id/telemetry` | Required | Gateway diagnostics time-series |

**GET /gateways/:id** - Returns `{ uid, state, online, last_seen_at, latest_voltage_mv, ip_address, cluster_id }`

---

### Wallets

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/wallets` | Required | List wallets for current user's organization |
| `GET` | `/wallets/:id` | Required | Wallet details with balance and transaction history |

---

### Blockchain Transactions

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/blockchain_transactions` | Required | Ledger: all on-chain transactions |
| `GET` | `/blockchain_transactions/:id` | Required | Transaction details: tx_hash, status, amount, token_type |

---

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/trees/:tree_id/telemetry` | Required | Tree telemetry time-series |
| `GET` | `/gateways/:gateway_id/telemetry` | Required | Gateway diagnostics time-series |

**Parameters:** `?days=7&resolution=hourly`

---

### Organizations

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/organizations` | Admin | List all organizations |
| `GET` | `/organizations/:id` | Admin | Organization profile with clusters and metrics |

---

### Alerts (EWS)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/alerts` | Required | Real-time alert stream (max 50) |
| `GET` | `/alerts/:id` | Required | Alert incident details |
| `PATCH` | `/alerts/:id/resolve` | Required | Close alert with resolution notes |

**GET /alerts** - Parameters: `?status=active&severity=critical&cluster_id=5`

**PATCH /alerts/:id/resolve** - Request: `{ "resolution_notes": "Issue resolved by field team" }`

---

### Actuators

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/clusters/:cluster_id/actuators` | Required | List actuators in cluster |
| `POST` | `/actuators/:id/execute` | Forester+ | Manual command dispatch |
| `GET` | `/actuator_commands/:id` | Required | Track command execution status |

**POST /actuators/:id/execute** - Request: `{ "command_payload": "OPEN", "duration_seconds": 3600 }`

**Command statuses:** `issued` → `sent` → `acknowledged` → `confirmed` / `failed`

---

### Contracts (NaaS)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/contracts` | Required | Portfolio of NaaS contracts |
| `GET` | `/contracts/:id` | Required | Contract details with emission history |
| `GET` | `/contracts/stats` | Required | Financial analytics |

**GET /contracts/stats** - Returns `{ total_invested, tokens_minted, portfolio_health, market_value_usd }`

---

### Firmwares

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/firmwares` | Admin | List firmware versions |
| `POST` | `/firmwares` | Admin | Upload new firmware |
| `GET` | `/firmwares/inventory` | Admin | Device firmware inventory |
| `POST` | `/firmwares/:id/deploy` | Admin | Trigger OTA deployment |

**POST /firmwares/:id/deploy** - Parameters: `{ "cluster_id": 1 }` or `{ "target_type": "bio_contract" }`

---

### Maintenance Records

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/maintenance_records` | Forester+ | List maintenance records |
| `POST` | `/maintenance_records` | Forester+ | Create Proof of Care record |
| `GET` | `/maintenance_records/:id` | Forester+ | Record details |

**POST /maintenance_records** - Request:
```json
{
  "maintainable_type": "Tree",
  "maintainable_id": 42,
  "action_type": "repair",
  "notes": "Replaced piezo sensor and recalibrated",
  "performed_at": "2026-02-28T10:00:00Z",
  "ews_alert_id": 15
}
```

---

### Oracle Visions (AI Insights)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/oracle_visions` | Forester+ | Portfolio of AI forecasts |
| `POST` | `/oracle_visions/simulate` | Forester+ | Trigger what-if simulation |
| `GET` | `/oracle_visions/stream_config` | Forester+ | Hotwire TurboStream channel config |

---

### Provisioning

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/provisioning/register` | Forester+ | Hardware-to-DID binding |

**POST /provisioning/register** - Request:
```json
{
  "hardware_uid": "STM32F4A1B2C3",
  "device_type": "tree",
  "cluster_id": 1,
  "family_id": 3,
  "latitude": 49.4285,
  "longitude": 32.0620
}
```

Response: `{ "did": "SNET-A1B2C3D4", "aes_key": "0A1B2C...", "device": { ... } }`

---

### Notifications

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/notifications/settings` | Required | Current notification preferences |
| `PATCH` | `/notifications/settings` | Required | Update SMS/Telegram notification settings |

---

### Reports (Archive)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/reports` | Required | List available report types |
| `GET` | `/reports/carbon_absorption` | Required | Carbon absorption analytics per cluster |
| `GET` | `/reports/financial_summary` | Admin | Financial summary: investment, tokens minted, market value |

---

### Audit Logs

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/audit_logs` | Admin | Full system action log |
| `GET` | `/audit_logs/:id` | Admin | Audit log entry details |

---

### System Audits

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/system_audits` | Admin | Security and integrity audit reports |

---

### System Health

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/system_health` | Admin | Backend health: DB, Sidekiq, Redis, queue depths |

---

### Settings

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/settings` | Admin | System-wide configuration |
| `PATCH` | `/settings` | Admin | Update system settings |

---

## Error Responses

| Status | Meaning |
|--------|---------|
| 400 | Missing required parameter |
| 401 | Authentication required |
| 403 | Insufficient permissions |
| 404 | Resource not found |
| 422 | Validation errors |
| 500 | Internal server error |

All errors return `{ "error": "message" }` or `{ "errors": ["message1", "message2"] }`.
