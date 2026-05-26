---
name: api
description: "Navigation + gotchas for REST API v1. Read SSOT docs first."
---

# API

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §8` | Key endpoints, roles, pagination |
| `CLAUDE.md §9` | Security: Argon2id, MFA, OAuth2, tokens, Sentry |
| `docs/04_03_REST_API_v1_Reference.md` | Full 82-endpoint reference |
| `docs/04_05_Authentication_and_Authorization.md` | Auth flow, M2M tokens, HMAC oracle |
| `docs/03_05_Security_Architecture.md` | AES keys in-process only, timing-safe HMAC |

## Gotchas Not Obvious From Docs

1. **oracle_callbacks has NO Bearer auth** — public endpoint, protected by HMAC-SHA256 only (`ActiveSupport::SecurityUtils.secure_compare`, timing-safe). Don't add `before_action :authenticate!`.
2. **Wallets balance/metadata return HTML** — Phlex Turbo Frame responses, NOT JSON. `Accept: text/html` only.
3. **Actuators execute needs Idempotency-Key** — JSON requests MUST include `Idempotency-Key` header. Without it → 422.
4. **Role hierarchy is numeric** — `investor(0) < forester(1) < admin(2) < super_admin(3)`. `patrol` is an alias for `forester`.
5. **M2M replay protection** — Redis nonce (SHA256 of Ed25519 signature, TTL 10 min). Same signature can't be reused.
6. **send_default_pii: false** — Sentry Zero-Trust. Never log user data. Check Sentry config before adding breadcrumbs.
7. **AES keys never leave Ruby process** — no Redis serialization. LRU cache (SinLruRedux) is in-process only.
