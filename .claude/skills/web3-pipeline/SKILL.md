---
name: web3-pipeline
description: "Use when working on the silken_net Web3 / on-chain surface — the 11-chain Proof-of-Growth pipeline (app/services/ + workers): SCC/SFC Solidity contracts, batchMint + Binary-Search poisoned-record isolation, the BlockchainTransaction AASM (incl. manual_review double-spend guard), minting guard-clauses (IoTeX / Chainlink / Hadron KYC), Dynamic Tax, slashing / penalty-factor de-correlation, Solana micro-rewards (Ed25519, batch payouts), DAO / Governor / Timelock, WEB3_STRICT_MODE. The gotchas — WEB3_STRICT_MODE is belt-and-suspenders not the switch, `:manual_review` is age-unbounded by design, the KYC-gate reads the BENEFICIARY, a money row carries two units in adjacent columns — are indexed here one line each and written in full in this skill's gotchas.md, which loads on demand: open it before touching anything that moves a balance. Routes to CLAUDE.md §1 (11-chain overview) + §5–§6 (the invariants that must be in EVERY prompt, deliberately not demoted into the companion) + the 05_01..05_06 canon (solc One-Home = 05_03), does not restate. Examples: \"add a chain integration\", \"change the minting threshold\", \"why is a tx stuck in manual_review\", \"batchMint reverts on dry-run\", \"edit the slashing penalty\", \"Solana reward formula / batch payout\"."
---

# Web3 Pipeline

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §1` + `§6` | 11-chain overview (§1); web3 gotchas (§6: manual_review, mint guards, partition-pruning) |
| `docs/05_01_Multichain_Architecture.md` | DePIN core/expansion stack, multichain rails, Solana, WEB3_STRICT_MODE (§5 boot-guard + per-service cards) |
| `docs/05_02_Proof_of_Growth_Pipeline.md` | Minting sequence, oracle callbacks, `[DOC.7]` guard inventory, trust-origin ladder L0/L1/L2 |
| `docs/05_03_Tokenomics_SCC_and_SFC.md` | Solidity contracts (SCC ERC-20, SFC), roles, batchMint, **Dynamic Tax** (S6.17 governance-aware — home) |
| `docs/05_04_Ethereum_L1_State_Anchor.md` | Weekly SHA-256 state-root → Ethereum L1; `StateRootAnchor` + the DOUBLE-ANCHOR intent-marker pattern that ARCH.45 idempotency reuses; **§5.1 confirmation-lifecycle [ARCH.66]** (`EthereumAnchorConfirmationWorker` poll→confirm/fail/manual_review + `StuckSentAnchorSweeperWorker` + reorg-gate); ARCH.13 EigenLayer-AVS cost-opt |
| `docs/05_05_Slashing_and_Risk_Policy.md` | Slashing/risk: cause A/B/C, positive-A evidence gate, convex penalty formula + `penalty_factor` de-correlation, insurance |
| `docs/05_06_Governance_and_DAO.md` | DAO Treasury, SilkenGovernor / Timelock, ProtocolParameters |
| `docs/03_05_Hardware_Symmetric_Crypto_and_Security.md` | Edge AES key management / HKDF; AES channel table (§6) |

## Gotchas Not Obvious From Docs

**Bodies live in `gotchas.md` — open it before touching the money path** (minting, slashing,
payouts, the L1 anchor, governance parameters, insurance, anything that moves a balance).
Below is one generated line per gotcha: the line is the CARRIER, meant to stop you mid-action;
the mechanism, the incident and the bounds are in the companion. Numbering is append-only
(`1a` = suffix insert). ⚠️ The invariants you must have without opening anything — the
unit/direction trap, the minting guard-clauses, SLASH-1 positive-A — are inline in `CLAUDE.md`
§5–§6, prepended to every prompt; this section is the SECOND layer.

<!-- WEB3-GOTCHAS-INDEX:AUTO — generated from gotchas.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. `WEB3_STRICT_MODE` is belt-and-suspenders, not the switch — the Hadron stub, the callback HMAC and the IoTeX fallback all fail-closed in prod REGARDLESS of the flag
1a. A monitoring read that MUTATES what it reports is not a probe — and both circuit breakers in this tree had exactly that — **Reflex for any «probe / status / health» method: read what it CALLS, not what it is named — and ask whether the call writes**
1b. `WEB3_STRICT_MODE` is not the switch — but a switch now EXISTS, for the other half of what `production` used to mean
1c. IoTeX/W3bstream is ACTIVATION-GATED since 2026-09-02 — an unconfigured leg enqueues NOTHING, and the «fail-closed raise at call» that gotcha 1 still describes was the shape that burned ~85 % of a slot's jobs — **before writing «fail-closed» for an external leg, ask whether the leg is CONFIGURED anywhere — an unconfigured fail-closed path is a retry ladder, not a guard**
2. manual_review state — **before reading a depth gauge as an incident signal, list every writer that parks a row in that state**
3. `batchMint` bisects a reverting batch to isolate the poisoned record — never bypass the dry-run, and bisect only WITHIN one archive-root subgroup
4. Dynamic tax is governance-read, applies to `batchMint` ONLY, and is on from genesis — a single `mint()` never taxes, and an RPC failure fails to `false` — **умову «чи оподатковується» питай ЛИШЕ через One-Home `taxing?(token_type)` — половин ДВІ (тип І стан пулу), а споживачів теж два: сама ДІЯ і ЗАПИС ПРО ДІЮ, і розходження між ними тихе за побудовою, бо запис ніхто не звіряє з дією**
5. Solana reward is `10,000 + growth_points * 100` lamports, signed Ed25519 — not secp256k1 — with the ATA resolved by owner
6. The partition helper depends on CARDINALITY — one known row versus a SET — and a `status`-scan deliberately stays unbounded
7. Solana payouts flip from per-event to hourly batching the moment `solana_batch_threshold_usdc` rises above zero
8. Slashing fires ONLY on positive Cat-A [SLASH-1 §3.2]
9. Slashing uplift combines CORRELATED signals with `max()`, never a sum — and its two predicates have OPPOSITE defaults (whitelist ⊥ blacklist)
10. Persist the `:pending` intent BEFORE the on-chain call, and treat `:manual_review` as age-UNBOUNDED — a windowed re-fire is a calendar bug, not a race
11. The whole economic parameter set is DAO-live through `SystemParameter` — a hardcoded constant on that path is already wrong
12. The mint KYC-gate reads the BENEFICIARY, not the caller — custodial inherits the org status, and rebinding an address resets it to pending
13. Every `BlockchainTransaction` status change enqueues `AuditLogWorker` [MRV.1 2026-07-04; hook re-based ARCH.57 2026-07-13]
14. `slashUpTo` clamps to the live balance instead of reverting, and its `contextHash` is the only thing tying an on-chain burn back to the backend intent
15. Two systemic stop-losses sit inert at zero by default and HOLD a batch rather than fail it — per-tx guards do not cover aggregate runaway
16. The L1 anchor is no longer fire-and-forget, and its poller gates on FINALITY (64 confirmations), not on first receipt like the money path
17. An insurance payout needs TWO independent triggers — our own AI alone once produced a simultaneous slash and payout
18. `wallets.balance` is a GROSS lifetime counter — the mint never debits it, and anything deciding "how much can be minted" must read `available_balance` — **any new consumer of "how much can this wallet mint" gets `available_balance`; the ratified precedent one file away is `KlimaDao::RetirementService` ([ARCH.56], whose fixing commit says "CHECK зловив латентний money-burn") — and that fix was never swept to its sibling, which is exactly how this shipped**
19. «Скільки SCC існує» has exactly ONE home — `BlockchainTransaction.net_minted_supply` — and it is NOT `sum(:amount)`
20. A money row carries TWO units in adjacent columns; the DIRECTION gap is CLOSED — the unit one is not — **Reflex when you touch any money row: name the UNIT of every scalar you pass, ask what marks its DIRECTION — and ask the same of every GUARD on that path, because a guard is a scalar comparison too, and a fix that moves it within one scale looks exactly like a fix that corrects the scale**
21. A device-side "neutral" fallback constant landed on the MAXIMUM of the money output — a shipped latent defect (no fleet, no incident), and the fix leaves a NEW wire pair every money consumer must know — **when you choose a fallback constant, substitute it through the WHOLE chain and look at what it lands on — a "neutral" input is routinely an extremum of the output**
22. «Скільки намінтовано» рахують ТРИ незалежні поверхні, вони НЕ взаємозамінні, і дві з них подаються на одному екрані — **перш ніж підставити «живе джерело» замість мертвого, спитай не «чи воно правдиве», а «чи про ТУ САМУ множину»**
23. SFC не мінтиться взагалі — заборона стоїть у ДВОХ місцях, і друге з них ПЕРЕЇХАЛО з гарда в ЕНУМ
24. Третя вісь грошового рядка — не одиниця й не напрямок, а ВИБІРКА: хто обирає, які дані оракул узагалі побачить — **Рефлекс перед будь-яким оракулом, агрегатом або вікном: спитай не «чи можна підробити показник», а «ХТО КОНТРОЛЮЄ ВИБІРКУ» — відповідь на перше не каже про друге нічого**
25. Приватний ключ оракула береться ЛИШЕ через seam `Web3::OracleSigner` — інлайновий `Eth::Key.new(priv: ENV[...])` є дефектом, навіть якщо поведінка тотожна — **рефакторячи вираз, що стоїть під придушенням, перепризначай фінгерпринт ТИМ САМИМ комітом**
26. Вирок судиться правом ПОДІЇ, а не правом ВИКОНАННЯ — і знаменник шкоди рахує тих, хто СВІДЧИВ
27. Реалістичне захоплення протоколу — АДМІНІСТРАТИВНЕ, тож рахуй не експлойти, а СТОЯЧІ ПОВНОВАЖЕННЯ після деплою — **перелік того, що складається, пишуть ОДИН раз, а ролі додають окремими комітами — тож він старіє тільки в бік НЕПОВНОТИ. Роздаючи нову роль, допиши її в renounce-перелік ТИМ САМИМ комітом, або вона переживе подію, задля якої перелік існує**
28. Kwarg, якого ПРИЙМАЧ не читає, — оголошення без механізму, і на money-path обидва наші такі kwargʼи були латентні при ЗЕЛЕНИХ спеках — **Рефлекс перед тим, як довіритись kwargʼу третьої сторони на грошовому шляху: прочитай ТІЛО методу-приймача, не докстрінг — докстрінг є заявою про НАМІР, тіло є контрактом; і пінь те, що доходить до ДРОТУ, а не форму виклику**
29. СТЕЛІ ГОЛОСІВ НА АКТОРА НЕМАЄ — і це ⚫ won't-do з підставою роду КОНСТРУКЦІЯ, а не пропуск
30. Природу емісії субграф деривує з ПРЕФІКСА `identifier`, а `GROWTH` є ВІДСУТНІСТЮ мітки — тож розходження двох боків завищує саме те число, яке читає ESG-покупець — **додаєш нову ПРИРОДУ емісії — заводь її префікс константою в обох мовах ТИМ САМИМ комітом, інакше вона мовчки порахується ростом**
31. Fee на EVM-клієнті вже СТОЇТЬ, і поставив його гем — тож новий money-сайт fee не задає, а нова МЕРЕЖА мусить дістати політику, інакше народиться з чужою стелею
32. Hardcoded-фолбек на ГРОШОВОМУ шляху існує рівно щоб пережити брак конфіга — і це небезпека, не зручність; тож чесний лік ЗНЯТТЯ, а не перецілення
32a. Знімаючи фолбек, перелічи споживачів за ФОРМОЮ посилання — і не лікуй їх однаково: серед них майже завжди є ЧИТАЛЬНИЙ, якому fail-loud шкідливий
33. HSM-підпис відрізняється від `Eth::Key#sign` ТРЬОМА речами, і кожну з них робить бекенд, а не HSM

<!-- /WEB3-GOTCHAS-INDEX -->

## Common Tasks

- **Add new chain integration**: service in `app/services/`, worker, ENV vars, guard clause check → update `05_02` + `CLAUDE.md §2` (routing table)
- **Change minting threshold**: `Wallet#lock_and_mint!` conversion (default 10k points = 1 SCC; DAO-live via `TokenomicsEvaluatorWorker.emission_threshold` — GOV.1) → update `05_03` (Конверсія — the one-home per 00_06 §2) + verify `05_01`/`05_02` mirrors
- **Edit / test a contract (`contracts/*.sol`)**: Foundry conventions + invariant gates → `CLAUDE.md §8`; spec/roles → `05_03`. 🔴 **Change a SIGNATURE (add/remove a parameter, add an event field) and you owe the canon mirrors in the SAME commit — `ruby scripts/solidity_signature_arity_check.rb` (HARD, `docs.yml`) will red on `05_03`/`05_01` until you do.** It judges ARITY only, over all of `docs/**`. ⛔ Its declared blind zone is the half that bites: an argument list written with NAMES ONLY — a flow diagram's `mint(to, amount, treeDid)`, or `transact(contract, "mint", …)` where the symbol is a STRING — carries no type token and is invisible to it. Measured 2026-08-26: eight such sites across FIVE docs, all hand-fixed, and widening the gate to reach them was measured at **25% precision and refused**. **So after a signature change, grep the flow diagrams and the `transact(` call sites by hand, corpus-wide — the green gate is a statement about declarations, not about prose.** The CI audit gates live in `.github/workflows/solidity_audit.yml` — each **fail-on in its own job**, and the `Solidity passed` aggregate IS merge-required on `main` (OPS.15 landed 2026-07-19 — money-path no longer merges red; one of the nine required contexts): Slither + Aderyn (static) · Halmos (symbolic, `test/symbolic/` `check_`) · Medusa + Foundry (fuzz/invariant, `test/medusa/` `property_` + `test/invariant/` `invariant_`) · gas-snapshot (`forge snapshot --check` vs committed baseline, tolerance 3%, excluding `invariant_` **and `testFuzz_`**) · coverage-floor (deployable contracts ≥90% lines per-file). Refresh the baseline with the **same** pattern the check uses — `forge snapshot --no-match-test "invariant_|testFuzz_"`. 🔴 **The trigger is "touched a test BODY", NOT "intended a gas change"** — this line said the latter until TEST.14 measured it (2026-08-09). Consequence for a working session: **every commit that touches test bodies carries its own regen**, or the money-path baseline is red BETWEEN commits; and a renamed test hard-fails **regardless of tolerance** (a new key has no baseline to be tolerant about). Magnitudes per axis, and why in-body vs constructor-initialiser differ → `04_06 §B.2` #6 (home — do not restate here). 🔴 The older advice here said `--no-match-test "invariant_"`, i.e. keep fuzz rows, and it went stale when `00bb766e` excluded them from the check: a `+3.1%` fuzz μ-shift under the pinned seed had broken `main` on a docs-only commit. Following the old form now writes **10 foreign `testFuzz_` rows** into a baseline the check never produces. The tell is cheap and beats any doc: the committed `contracts/.gas-snapshot` carries **zero** `invariant_` and **zero** `testFuzz_` lines, so the WRITE pattern is readable off the artefact itself. Reason lives beside the step in `solidity_audit.yml`.
  🔴 **`contracts/medusa-*.json` narrows `platformConfig.target` to the ONE harness file with `args: []`, and that is load-bearing, not tidiness.** crytic-compile cannot parse forge-std's `LibVariable` ABI, so a whole-project build (`--foundry-compile-all`, or a broader `target`) **errors out**; pointing at the single harness makes it compile only that file's import tree — token + OZ, no forge-std. The reason cannot live beside the setting, because JSON carries no comments, so it lives here: **widening that target looks more thorough and breaks the fuzz job with an unrelated-sounding parse error.** Its sibling constraint is already in the harness NatSpec — Medusa has no `targetContract()` routing, so handler wrappers and every `property_*` share ONE contract.
  Remaining memory-only detail is the founder's local darwin install (venv/brew paths, mac release assets) → `reference_solidity_audit_stack`; the rest of that file's stack facts now stand in git — `CLAUDE.md §8` (naming), `contracts/aderyn.toml` (exclude rationale), `solidity_audit.yml` (hash-pin + snapshot cmd), skill `dependency-update` (`gh api code-scanning` + the 280-char `dismissed_comment` wall).
