# SilkenNet — Security Assurance Case

> **Purpose.** A documented, structured argument that SilkenNet's security requirements are adequately
> justified for its environment. It states the top-level security **claims**, the **threat model**, the
> **trust boundaries** and the guard that enforces each, the **secure-design principles** applied, how
> **common implementation weaknesses** are countered, and — honestly — the **residual risks** that are not
> yet fully closed.
>
> **Scope.** The software produced by the project: the Rails backend (`app/`, `lib/`, `config/`), the STM32
> firmware (`firmware/`), the Solidity contracts (`contracts/`), and the CI/CD + deploy configuration
> (`.github/`, `deploy/`, `terraform/`). It excludes third-party infrastructure operated by others
> (Postgres, Redis, the chains, Chainlink DON, the operator of whatever host runs the backend) except where SilkenNet code defends against
> their misbehaviour.
>
> **Status.** Living document — last reviewed 2026-07-16. This is a *synthesis*: it argues and points to the
> canonical homes for mechanism detail rather than restating them (one-home, registered in
> [`00_06`](00_06_SSOT_Documentation_Standard)). Open items are tracked in
> [`00_07`](00_07_Action_Plan_Tracker) (`SEC.*` / `FW.*` IDs).

---

## 1. Security claims

The argument below justifies these top-level claims:

1. **Telemetry cannot be forged or replayed into a token mint without detection.** A device cannot inflate
   `growth_points` (and therefore SCC) by spoofing firmware, replaying old packets, or tampering on the
   radio link, without tripping at least one independent guard.
2. **Funds cannot be double-minted or double-spent.** A single verified telemetry event mints at most once;
   an ambiguous on-chain state freezes rather than retries.
3. **Signing keys are appropriately separated.** Release-signing keys are ephemeral and never on the
   distribution registry; on-chain `mint()` and `slash()` use physically separate keys; the device-key
   roadmap targets non-extractable hardware keys.
4. **The web tier resists the common web-application weakness classes** (OWASP Top 10, 2021).
5. **Released artifacts are reproducible and cryptographically verifiable** (signed build provenance).

Each claim is backed by the trust-boundary guards (§3), the secure-design argument (§4), the weakness map
(§5), and the verification evidence (§7) — bounded by the residual risks honestly stated in §6.

---

## 2. Threat model

### 2.1 Assets

| Asset | Where it lives | Why it matters |
|---|---|---|
| **Telemetry integrity** (sensor → mint) | `app/services/telemetry_unpacker_service.rb`, firmware sense path; canon [`03_04`](03_04_mruby_Lorenz_Attractor), [`05_02`](05_02_Proof_of_Growth_Pipeline) | Forged/replayed telemetry inflates `growth_points` → false SCC mint → economic fraud. |
| **SCC funds & minting authority** | `contracts/*.sol` (`MINTER_ROLE`), `app/services/blockchain_minting_service.rb`; canon [`05_03`](05_03_Tokenomics_SCC_and_SFC) | Unauthorized minting drains collateral / commits carbon-credit fraud (RWA). |
| **Cryptographic keys** | LoRa AES (per-device, `firmware/common/`), CoAP AES-256 (Queen Flash), Ed25519 device identity (`HardwareKey`), Rails `master.key`, oracle secp256k1 keys (ENV); canon [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security), [`03_06`](03_06_Factory_Flashing_and_Key_Provisioning) | Key compromise → decrypt history, impersonate device, or mint without authority. |
| **DCI anti-fraud signal** (Lorenz Z) | backend `app/services/silken_net/attractor.rb` ⟷ device `firmware/bio_contracts/bio_contract.rb`; canon [`05_02`](05_02_Proof_of_Growth_Pipeline), [`03_04`](03_04_mruby_Lorenz_Attractor) | The cross-check that detects device tampering; its integrity is the fraud tripwire. |
| **Audit-log integrity** | `app/models/audit_log.rb` (per-org SHA-256 hash chain) | A tamper-evident record for forensic reconstruction and dispute resolution. |
| **User credentials & session tokens** | `app/models/user.rb` (Argon2id digest), Rails 8 `generates_token_for` | Theft → impersonation; bounded by hashing + token expiry/invalidation. |

### 2.2 Threat actors & goals

- **LoRa/CoAP MITM** — eavesdrop or forge/replay telemetry on the 868 MHz link or the CoAP backhaul.
- **Hostile host operator** — anyone with root or hypervisor access to the machine running the backend:
  reads `/proc/<pid>/environ`, tampers with the container image or its runtime. Defined by CAPABILITY,
  not by vendor — the capability is identical on a self-managed cloud VM, and naming a specific provider
  here once let the presumption look like a property of that provider rather than of hosting [OPS.37].
- **Replay attacker** — retransmit recorded packets (telemetry or panic) to re-trigger effects.
- **Double-spender** — exploit an RPC reorg/race to mint the same growth twice.
- **Telemetry forger / DCI fraud** — run hacked firmware or spoof a device to fake growth and mint SCC.
- **Compromised RPC / wrong chain** — point the backend at a testnet or hostile RPC to misdirect mints.
- **Credential thief / insider** — exfiltrate an oracle key or issue fake machine tokens.

### 2.3 Attack surfaces

The LoRa radio link · the CoAP backhaul · the public web/API · outbound RPC/oracle calls · the on-chain
contracts · the deploy/supply-chain · physical hardware tamper.

---

## 3. Trust boundaries and their guards

A *trust boundary* is where data or execution changes trust level. The pipeline is
**Soldier → Queen → Rails → chain**, with two on-chain economic gates (mint, slash). Each boundary names
the guard that enforces it.

### Boundary A — Soldier → Queen (LoRa)
*Crosses:* the encrypted sensor packet (vcap, temp, acoustic, Δt, status, growth_points, device-Z, DID).
*Trust shift:* untrusted device output → gateway buffer.
*Guards:*
- **AES-128 link encryption** — shipping build is AES-128-**ECB** (transitional); the authenticated
  AES-128-**CCM** path (8-byte MIC + 24-bit monotonic Frame Counter) is implemented and bench-gated
  (`FW2_CCM_ENABLED` / `TELEMETRY_CCM_ENABLED`). Canon [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security),
  `firmware/common/lora_ccm.h`.
- **Two-key model (FW.2 gate (в), 2026-07-03)** — the money-path (telemetry/panic CCM uplink) rides a
  **per-device session key** (HKDF, so a node compromise cannot forge a neighbour's mint), while the
  control-plane (downlink broadcast + `0x55`/`0x56` requests) rides a deliberate **per-cluster KEYB**
  (broadcast is structurally one-key; same isolation class as K_ota). Honest residual: a compromised node
  exposes the cluster's control-plane; OTA images stay separately authenticated by the K_ota HMAC dual-gate.
  Canon [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security), [`03_06`](03_06_Factory_Flashing_and_Key_Provisioning).
- **Replay protection** — CCM Frame Counter + a backend `SETNX` dedup window; for the interim panic path,
  a monotonic panic counter + `SETNX` (SEC.10). Canon [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security),
  [`05_02`](05_02_Proof_of_Growth_Pipeline).
- **Sanity bounds + DCI** — `TelemetryUnpackerService#valid_sensor_data?` rejects out-of-range ADC/temp;
  `check_z_divergence!` rejects a device whose Z disagrees with the backend recomputation (DCI, SEC.11 in
  [`05_02`](05_02_Proof_of_Growth_Pipeline)).

### Boundary B — Queen → Rails (CoAP)
*Crosses:* an AES-256-CBC batch of per-device-encrypted records.
*Trust shift:* gateway buffer → persisted, auditable backend state.
*Guards:*
- **AES-256-CBC transport** with a per-batch random (HRNG) IV ([`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)).
- **Machine-to-machine auth** — `app/controllers/api/v1/m2m_auth_controller.rb`: gateway authenticates with
  an Ed25519 signature; a `SETNX` nonce + timestamp window blocks replay.
- **L1 gateway attestation** — Ed25519 batch signature verified against the `HardwareKey` registry
  (`firmware/common/queen_attest.h`).
- **L1 device-event channel** — the separate `PUT device/event/<uid>` (SEC.21 canary-trip) crosses the same
  boundary under its OWN Ed25519 gateway signature (domain tag `SLKN-QEVT1`, distinct from the batch's
  `SLKN-QATT2`), verified by `DeviceEventWorker` against the same `HardwareKey.ed25519_public_key_hex` registry —
  Rails never touches a LoRa key here ([`03_05 §2.2а`](03_05_Hardware_Symmetric_Crypto_and_Security)). Trust
  L1-observational: the event never moves the money-path.
- **KENOSIS ingestion boundary** — `TelemetryLog` carries no ActiveRecord validations by design; the single
  validation home is `valid_sensor_data?` in the unpacker service (`CLAUDE.md`,
  [`05_02`](05_02_Proof_of_Growth_Pipeline)).

### Boundary C — Telemetry → IoTeX W3bstream verification
*Crosses:* the device Z-value + DID + chaotic data.
*Trust shift:* backend-unpacked data → externally attested proof.
*Guard:* **Dual-Computation Integrity** — backend (`SilkenNet::Attractor`, IEEE-754 double) and device
(mruby Float) compute Z from the same persisted state with identical Lorenz constants (owned in
[`03_04`](03_04_mruby_Lorenz_Attractor)); a divergence beyond tolerance flags tampering (DCI, SEC.11 in
[`05_02`](05_02_Proof_of_Growth_Pipeline)). Per-device signing strengthens along the trust-origin ladder
(L0 custodial → L1 gateway → L2 SE050 device).

### Boundary D — Chainlink callback → minting trigger
*Crosses:* the oracle result + `request_id`.
*Trust shift:* off-chain oracle computation → on-chain trigger.
*Guards:*
- **HMAC-SHA256 signature verification** — `app/controllers/api/v1/oracle_callbacks_controller.rb`
  (`verify_chainlink_signature!`); under `WEB3_STRICT_MODE` a missing secret fails closed.
- **Atomic, idempotent state machine** — the callback transitions `oracle_status` only `WHERE
  oracle_status = 'dispatched'`; a replayed callback updates zero rows → 409 (no double-trigger).

### Boundary E — Minting gate (verified telemetry → on-chain mint)
*Crosses:* growth_points, recipient, amount.
*Trust shift:* backend-verified data → irreversible token issuance.
*Guards* (`app/services/blockchain_minting_service.rb`):
- **Guard clauses** — Path 1 (telemetry-driven) refuses unless `verified_by_iotex?` **and**
  `oracle_status_fulfilled?`; the KYC gate applies to **ALL paths**: `Wallet#kyc_approved_for_minting?`
  (beneficiary of the destination address — own status, or the custodial organization's; KYC.1) —
  non-approved wallets are per-tx SKIPPED (stay `:pending`); a compromised peaq DID is skipped.
- **Signer separation** — minting uses a different secp256k1 key from slashing (E.2); a leaked minter key
  does not enable slashing.
- **Double-spend guard** — `BlockchainTransaction` AASM `manual_review` state freezes funds when a tx state
  is ambiguous (reorg/race) for human review, instead of auto-retrying (`app/models/blockchain_transaction.rb`).

### Boundary F — Slashing gate (cluster degradation → irreversible burn)
*Crosses:* cluster stress signal, locked investor balance.
*Trust shift:* an unauthenticated stress index → an irreversible burn.
*Guards* (canon [`05_05`](05_05_Slashing_and_Risk_Policy), `app/services/slashing/`):
- **Positive-A-evidence gate (SLASH-1)** — a burn requires proven operator-fault evidence (a critical,
  unresolved tamper alert); absent that, the default-safe action is **freeze** (Field Audit), never burn.
- **Force-majeure separation** — confirmed natural disasters (dClimate/FIRMS) route to insurance, not
  slashing.

---

## 4. Secure-design principles applied (Saltzer–Schroeder)

The principles are implemented in code, not just asserted. This is summarized here and detailed (with the
exact crypto modes and the deployment hardening) in `SECURITY.md` and canon
[`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security):

- **Fail-safe / deny-by-default** — minting and slashing refuse unless every precondition holds (§3 E/F);
  in production `WEB3_STRICT_MODE` turns missing security config into a hard failure rather than a silent
  fallback; `Security::Web3NetworkGuard` refuses to boot against a testnet/misconfigured RPC.
- **Complete mediation** — tenant isolation is enforced *inside the query*
  (`acting_organization!.trees.find(...)`), so a foreign record never materialises; Pundit policies
  (`app/policies/`) cover the predicate surfaces (funds, PII) and role gates guard the
  API base controller; thin controllers and AASM state machines make state changes non-bypassable.
- **Least privilege / separation of privilege** — on-chain roles gated by `onlyRole(...)`, admin actions
  routed through `SilkenTimelock` (48h delay; flash-loan defense, E.35), `mint()`/`slash()` on separate
  keys.
- **Defense in depth** — anomaly/tamper telemetry is zeroed for minting in *both* firmware and backend; the
  `manual_review` double-spend guard; no weak crypto anywhere (no MD5/SHA-1/DES/RC4).
- **Economy of mechanism** — the project's explicit YAGNI "lazy-senior" ladder and Ruthless Pruning
  (`CLAUDE.md`) keep mechanisms minimal; input is validated at trust boundaries.

Secure-by-default deployment (`config/environments/production.rb`): `force_ssl` + HSTS preload, a strict CSP
with a per-request nonce, a full security-header set, and `httponly`/`secure`/`same_site:lax` cookies.

---

## 5. Common implementation weaknesses countered (OWASP Top 10, 2021)

| # | Category | How it is countered | Where |
|---|---|---|---|
| **A01** | Broken Access Control | Tenant scope enforced **inside the query** (`acting_organization!.<assoc>.find`); **Pundit** policies on predicate surfaces (funds/PII) + role gates (`authorize_admin!/forester!`); on-chain **AccessControl** roles + 48h **Timelock** | `app/controllers/api/v1/`, `app/policies/`, `app/controllers/api/v1/base_controller.rb`, `contracts/*.sol` |
| **A02** | Cryptographic Failures | **Argon2id** passwords; AES-256-CBC/AES-128-CCM, HMAC-SHA256, HKDF, **Ed25519**; **no MD5/SHA-1/DES/RC4**; `force_ssl`+HSTS; secret scrubbing | `app/models/concerns/has_argon2_password.rb`, `config/initializers/{filter_parameter_logging,sentry}.rb` |
| **A03** | Injection | Strong-parameter **allowlists**; ActiveRecord parameterized queries; URI allowlist | `app/controllers/**` |
| **A04** | Insecure Design | Fail-safe minting guard clauses; `manual_review` double-spend guard; boot-time `Web3NetworkGuard`; positive-A-evidence slashing gate | `app/services/blockchain_minting_service.rb`, `app/services/security/web3_network_guard.rb`, `app/services/slashing/` |
| **A05** | Security Misconfiguration | Strict **CSP** (nonce, `frame-ancestors 'none'`, `object-src 'none'`); `X-Frame-Options: DENY`, nosniff, Referrer/COOP/CORP/Permissions-Policy; secure cookies; HSTS preload; `RAILS_ALLOWED_HOSTS` | `config/initializers/{content_security_policy,security_headers,session_store}.rb`, `config/environments/production.rb` |
| **A06** | Vulnerable & Outdated Components | **Dependabot** (5 ecosystems), **bundler-audit** + **Brakeman** in CI, **Slither** + **Aderyn**, **OpenSSF Scorecard**, **CodeQL** | `.github/dependabot.yml`, `.github/workflows/{ci,solidity_audit,scorecard}.yml` |
| **A07** | Identification & Auth Failures | **Argon2id**; M2M **Ed25519** + `SETNX` nonce replay guard; one-time **recovery codes**; Rails 8 token expiry/invalidation; **Rack::Attack** Fail2Ban on 401/404 + per-IP throttle | `app/controllers/api/v1/m2m_auth_controller.rb`, `app/models/user.rb`, `config/initializers/rack_attack.rb` |
| **A08** | Software & Data Integrity | `Marshal.load` guarded by **SHA-256** verification; **audit-log SHA-256 hash chain**; firmware **OTA HMAC-SHA256 + CRC**; firmware `binary_sha256`; **Sigstore build-provenance** on the release image | `app/services/insight_generator_service.rb`, `app/models/audit_log.rb`, `app/services/ota_packager_service.rb`, `.github/workflows/mirror-ghcr.yml` |
| **A09** | Logging & Monitoring Failures | Tamper-evident **AuditLog**; Prometheus metrics; **Sentry** with PII disabled + secret scrubbing; `filter_parameters`; Rack::Attack notifications; structured JSON logs | `app/models/audit_log.rb`, `config/initializers/{sentry,filter_parameter_logging,prometheus}.rb` |
| **A10** | SSRF | Open-redirect **referer sanitizer** (scheme + host allowlist); outbound RPC via an ENV-configured connection pool (no caller-supplied URLs) + `Web3NetworkGuard` | `app/controllers/api/v1/locales_controller.rb`, `app/services/web3/rpc_connection_pool.rb` |

---

## 6. Residual risks & assumptions

An assurance case is credible because it states what is **not** yet fully closed. These are tracked in
[`00_07`](00_07_Action_Plan_Tracker):

- **Transitional LoRa AES-128-ECB (no MIC).** The shipping link mode is ECB: deterministic and
  unauthenticated, so a whole-block replay of an old "healthy" packet is possible at the link layer. It is
  bounded today by DCI divergence + sanity bounds + the panic replay counter, and closed by the
  bench-gated **AES-128-CCM** path (`FW.2`). Canon [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security).
- **L0-custodial device signing.** Until the per-device hardware key (L2, SE050) is provisioned, device
  attestation is custodial/gateway-level (L1) — the backend is part of the trust base for device identity.
  Roadmap: SE050-MIGRATION in [`00_07`](00_07_Action_Plan_Tracker).
- **RDP Level 2** (firmware read-out protection) is **pending** (SEC.2) — physical extraction of a deployed
  MCU is not yet locked out.
- **MFA is a live control since 2026-08-20 (`S6.21`, archived): TOTP (RFC 6238, `rotp`) with
  verify-on-login.** `sessions#create` refuses a session after the password for an `mfa_enabled?`
  account (pending marker, 5-min TTL, JSON gets `401 mfa_required`), the second factor is verified with
  anti-replay (`otp_last_used_at`), recovery codes are consumed exactly once and rotate behind a
  step-up. The secret is AR-encrypted at rest. Residual honestly out of scope: WebAuthn/hardware-key
  is deferred until the first B2B client demands it — TOTP shares the secret with the phone, so a
  phishing-proof factor remains unclaimed.
- **Pre-mainnet.** No production deployment has run yet; the deploy-time guards (`verify-secrets`, force_ssl,
  HSTS) are configured and CI-verified but not yet exercised live.
- **External-trust assumptions.** The argument assumes the Chainlink DON behaves per its own fraud-proof
  model, that the chains finalize honestly, and that a hostile host operator cannot defeat container attestation —
  defended where code can (HMAC on callbacks, signed images, multi-RPC fallback) but not eliminated.
- **Secrets live in a running process on a host we do not physically control (at-rest ≠ runtime).** Anyone with
  root on that host reads `/proc/<pid>/environ`, so at-rest encryption cannot hide a secret that must be live
  in the process. The *unbounded-fraud* keys are being moved out of process memory — EVM signing → GCP-KMS
  remote-signer (`SEC.17`, key never in-process); `PROVISIONING_MASTER_KEY` (the HKDF root that derives every
  device key — higher blast-radius than the minter key; on compromise the derived Lorenz seed breaks the DCI
  anti-fraud invariant for the whole flashed fleet until an SWD re-flash) → GCP-KMS-MAC + an Expand-only KDF
  (pre-mainnet, firmware-coordinated). **`RAILS_MASTER_KEY` belongs in the same sentence:** it unlocks the
  credentials vault and — via the entangled `secret_key_base` ([`06_04 §5.2`](06_04_Secrets_Checklist)) —
  forges sessions and every `generates_token_for` token; its *runtime* need is being dissolved
  (credentials→ENV shipped, Phase-2 drop deploy-gated — `SEC.22`), and both master keys are effectively
  un-rotatable today. Until those land they are provider-visible; bounded-blast operational credentials
  (`REDIS_URL`, the DB-access credential, per-vendor API keys, webhook HMACs) stay resident by design.
  **The Solana Ed25519 payout key sits deliberately in the bounded-blast class, not the KMS class — a
  ratified won't-do (⚖️ founder 2026-08-29, `SEC.22`), grounded in construction, not deferral:** it is not a
  mint authority — it authorizes SPL transfers from a pre-funded ATA, so the blast ceiling equals the wallet
  FLOAT (≈0.01–0.02 USDC per event), not the emission; both named alternatives measured WORSE — Vault-Transit
  adds a new Art.28 vendor plus a network call on an otherwise offline in-process hot path while the secret
  merely moves one level (the Vault token lives in the same `/proc/environ`), and pinning the key to the
  Ingress Anchor would CONCENTRATE a money key next to the master key on a deploy-SA host while reversing a
  HARD-gated invariant (`anchor_coap_env_spec` forbids it by name). The KMS path ([`06_04 §5.5`](06_04_Secrets_Checklist)) is
  secp256k1-only by construction and does not reach Ed25519. The float itself is now measured, not assumed:
  `silkennet_payout_float_balance` (declared diagnostic tier; threshold = a deploy-day decision, `SEC.22`).
  ⚠️ [OPS.37] Retiring the decentralized-compute target did NOT close this residual, and saying so matters:
  the earlier wording blamed one platform's lack of Workload Identity Federation, which reads as if a different
  host would fix it. It would not — on a self-managed VM the same variables sit in the same container environ,
  readable by the same root. What the cut DID close is narrower and real: the one long-lived service-account
  key that existed only to authenticate from outside the VPC no longer exists anywhere in the tree. The third at-rest copy in the GCS Terraform-state bucket is now
  CMEK-sealed with public-access-prevention and a deliberately short 10-version/30-day retention
  ([`06_04 §5.6`](06_04_Secrets_Checklist), 2026-07-10). Rotation-on-compromise runbooks for the two master
  keys are **written** — an ordered-degradation playbook, honest that neither key rotates cleanly →
  [`06_04 §5.8`](06_04_Secrets_Checklist). Program + phasing: `SEC.22`
  ([`00_07`](00_07_Action_Plan_Tracker)); mechanism → [`06_04 §5.5`](06_04_Secrets_Checklist).

---

## 7. Verification & evidence

The claims above are backed by enforced, automated evidence — not by assertion:

- **Tests.** RSpec with a hard SimpleCov gate (line 99% / branch 98%, plus per-group floors); Foundry
  contract tests including the security invariants (`testRevert_cannotRemoveLastAdmin`,
  `test_pause_allowsSlash`, `totalSupply() <= MAX_SUPPLY`); the firmware host suite run additionally under
  **AddressSanitizer + UndefinedBehaviorSanitizer** on every CI run.
- **Static analysis (SAST).** Brakeman (Rails) and cppcheck (firmware C) run in `ci.yml`, whose
  `CI passed` aggregate is a merge-required branch-protection check on `main` — a finding blocks the
  merge; cppcheck's MISRA C:2012 addon is opt-in and advisory, not part of the gate. Slither + Aderyn
  (Solidity, fail-on-high), **Halmos** symbolic proofs (`test/symbolic/`) and **Foundry + Medusa**
  property-fuzzing (`test/invariant/`, `test/medusa/`) add depth on the token/governance contracts; they
  run in the separate `solidity_audit.yml`, whose **`Solidity passed` aggregate is a merge-required
  branch-protection check on `main`** (OPS.15, landed 2026-07-19) — each job also fails on its own
  findings, and a red audit now physically blocks the merge. CodeQL (default setup, 6 languages) and
  OpenSSF Scorecard report findings without being merge-required. The exact required-check surface (all
  **9** deterministic PR-gates — `CI passed` + `Docs passed` + `Solidity passed` + `DCO passed` + `Subgraph passed` + the
  CAD/ML/In-silico/IaC smoke aggregates) → [`06_07 §2`](06_07_CICD_and_Runbook_Index).
- **Composition analysis (SCA).** Dependabot (weekly), bundler-audit (every CI), OpenSSF Scorecard (weekly).
- **Supply chain.** Sigstore-signed SLSA build-provenance on the released container — verifiable per
  `SECURITY.md` ("Verifying release artifacts").
- **This badge.** The OpenSSF Best Practices criteria (`crypto_*`, `input_validation`, `hardening`,
  `static_analysis_*`, `dynamic_analysis_*`, `signed_releases`, `implement_secure_design`) corroborate
  individual claims here.

---

## References (canonical homes — one-home)

- `SECURITY.md` — vulnerability reporting, scope, known limitations, release-artifact verification.
- [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security) — AES modes, key management, IV, SE050, PQC roadmap.
- [`03_06`](03_06_Factory_Flashing_and_Key_Provisioning) — per-device key derivation.
- [`05_02`](05_02_Proof_of_Growth_Pipeline) — telemetry → verification → mint, DCI (SEC.11), replay (SEC.10).
- [`05_03`](05_03_Tokenomics_SCC_and_SFC) — token contracts, roles, supply cap.
- [`05_05`](05_05_Slashing_and_Risk_Policy) — slashing categories, positive-A-evidence gate, insurance.
- [`06_07` — CICD and Runbook Index](06_07_CICD_and_Runbook_Index) — supply-chain hardening (IaC policy); CI/CD inventory in [`06_07`](06_07_CICD_and_Runbook_Index).
- [`00_07`](00_07_Action_Plan_Tracker) — open `SEC.*` / `FW.*` items and their status.
