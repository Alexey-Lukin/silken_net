---
name: api
description: "Domain knowledge for REST API v1 — auth stack (Argon2id/MFA/OAuth2/M2M), role hierarchy, pagination, idempotency, HMAC oracle"
---

# REST API v1

All endpoints live under `/api/v1`. Base controller: `Api::V1::BaseController < ActionController::Base`.

## Auth Stack

1. **Passwords** — Argon2id via `HasArgon2Password` concern.
2. **Tokens** — Rails 8 `generates_token_for` with TTLs: `:password_reset` 15 min, `:email_verify` 24 h, `:api_access` 30 days.
3. **Session auth** — cookie-based (`session[:user_id]`), `reset_session` on login (session-fixation guard). Rate-limited: 5 attempts/min on `sessions#create`.
4. **Bearer auth** — `authenticate_with_http_token` resolves `User.find_by_token_for(:api_access, token)`. CSRF bypassed for Bearer requests (browsers never auto-attach `Authorization`).
5. **MFA** — TOTP + 10 recovery codes. Managed via `PATCH /account_security/mfa`.
6. **OAuth2** — google, facebook, linkedin, twitter. Identity lock/unlock via `PATCH/DELETE /account_security/identities/:id`.

## M2M Auth (Machine-to-Machine)

`POST /auth/m2m_token` — public (skips `authenticate_user!`).
Flow: gateway sends `{did, timestamp, signature}` where `signature = Ed25519.sign(pk, "#{did}:#{timestamp}")`.
- Timestamp tolerance: +/- 5 minutes.
- **Replay protection**: `SHA256(signature)` used as nonce, stored in Redis via `SET NX` with TTL 600s. On Redis outage, falls back to `Rails.cache` (Solid Cache / DB-backed) with `SilkenNet::Metrics::M2M_NONCE_FALLBACK_TOTAL` counter.
- Returns Bearer token (30-day `:api_access`).
- `POST /auth/m2m_token/refresh` — requires valid Bearer, issues new 30-day token (sliding window).

## Role Hierarchy

```
investor(0) < forester/patrol(1) < admin(2) < super_admin(3)
```

- `forest_commander?` = forester OR admin OR super_admin.
- Pundit policies use helpers: `admin_or_above?`, `super_admin?`, `forester_or_above?`, `same_organization?(org_id)`.
- `ApplicationPolicy` defaults: `index?`/`show?` = true; `create?`/`update?`/`destroy?` = `admin_or_above?`.
- Scopes enforce org-level tenancy (e.g., `TreePolicy::Scope` filters by `clusters.organization_id`; `super_admin` sees all).
- Legacy helpers (`authorize_admin!`, `authorize_forester!`) still used in some controllers (migration to Pundit ongoing).

## Pagination

Pagy via `include Pagy::Method`. Default: `?page=N&limit=21`. Response includes `pagy: {page, limit, count, pages}`. Exception: `maintenance_records` uses `limit: 50` for index, `limit: 6` for some views.

## Key Endpoint Behaviors

| Endpoint | Behavior |
|----------|----------|
| `POST /actuators/:id/execute` | **Requires `Idempotency-Key` header** for JSON requests. SHA256-hashed key cached in Redis 24h. Returns 400 without it. Returns cached response on duplicate key. |
| `GET /wallets/:id/balance` | Returns **Phlex Turbo Frame** (HTML only, `Wallets::BalanceFrame`), not JSON. JSON also available via `respond_to`. |
| `GET /wallets/:id/metadata` | Same pattern — `Wallets::MetadataFrame` Phlex component for HTML. |
| `POST /oracle_callbacks` | **Public** (skips `authenticate_user!`). Protected by HMAC-SHA256: `X-Chainlink-Signature = HMAC(body, CHAINLINK_HMAC_SECRET)`, verified with `ActiveSupport::SecurityUtils.secure_compare` (timing-safe). Fails fast in production when `WEB3_STRICT_MODE=true` and secret is missing. Atomic state guard: `WHERE oracle_status='dispatched'` prevents replay (409 Conflict on duplicate). |
| `POST /provisioning/register` | Registers new device, triggers `PeaqRegistrationWorker`. |

## Adding a New API Endpoint

1. **Route** — add to `config/routes.rb` inside `namespace :api / :v1`.
2. **Controller** — create action in `app/controllers/api/v1/`, inherit from `BaseController`. Use `respond_to` for JSON + HTML (Phlex dashboard).
3. **Policy** — create `app/policies/<model>_policy.rb` inheriting `ApplicationPolicy`. Define action predicates (`show?`, `create?`) and `Scope#resolve` for org-tenancy.
4. **Serializer** — use Blueprinter (`app/blueprints/`) for JSON, Phlex component for HTML.
5. **Spec** — request spec in `spec/requests/api/v1/`, policy spec in `spec/policies/`.

## Gotchas

- **oracle_callbacks has NO Bearer auth** — HMAC-SHA256 only. Do not add `authenticate_user!`.
- **`send_default_pii: false`** in Sentry — never log user emails/IPs to error tracker.
- **AES keys never leave Ruby process** — `HardwareKey.cached_binary_key` uses in-process LRU (`SinLruRedux`), never serialized to Redis.
- **Composite PK on `TelemetryLog`** — partitioned by `created_at`. Always pass both `id` and `created_at` for partition pruning (use `find_with_partition_pruning` or scope by `created_at`).
- **`ensure_organization!`** — opt-in `before_action`; returns 422 if user has no org (covers system bots / incomplete onboarding).
- **Error responses** are i18n-backed (`I18n.t("errors.api.*")`). Never hardcode English strings in new error handlers.
