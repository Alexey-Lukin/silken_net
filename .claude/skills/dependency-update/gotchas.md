# Dependency update — hard-won gotchas (the bodies)

> **Companion file of the `dependency-update` skill. Open it before you merge, bump, pin or quarantine
> a dependency — any domain.** The one-line index in `SKILL.md` §Hard-won gotchas is the CARRIER; this
> file is the mechanism, the incident that bought it, and its bounds. Edit rules HERE — the index is
> generated (`ruby scripts/guard_craft_index.rb --write`).
>
> **Numbered on 2026-09-19, append-only from then on.** Before the split these were unnumbered
> bullets, so older citations name the section and never a number; the numbers follow the pre-split
> order. Cite `dependency-update #N`.

1. 🔴 **A vendored front-end package has its version in TWO places, and the tool sees only one** [TEST.7, 2026-08-03]. `leaflet` is pinned locally: JS in `vendor/javascript/leaflet.js` (visible to `bin/importmap outdated`) **plus** CSS and 5 PNGs in `vendor/assets/stylesheets/leaflet/` — ordinary files no inventory command knows about. So a bump must be **paired**, or the halves drift silently: a mismatched CSS raises nothing, it just breaks the map's layout. Three traps around it. (a) Re-pin with the **default jspm provider** — `--from unpkg` serves UMD with no ESM exports, so `import L from "leaflet"` dies. (b) The CSS ships **relative** `url(images/*.png)`, and Propshaft rewrites those to digested paths only while the images sit next to it — keep the `images/` subdir. (c) After ANY new pin, run `RAILS_ENV=test bin/rails assets:precompile` locally: a stale `public/assets/.manifest.json` keeps Propshaft on the **Static** resolver, and then every browser example fails **at login** (asset missing → the layout stub blanks the tags → page without JS). That symptom reads as broken authentication and costs an hour. ⊕ The notice layer moves with the bytes — `LICENSE-leaflet.txt` · `NOTICE` · `THIRD_PARTY_NOTICES` (SKILL.md §Domains, JS row).
2. **Post-cutoff versions are real. This repo runs ahead of the model's knowledge cutoff**
  (a gem two majors behind what `bundle outdated` reports is the normal case — ⛔ do not pin an example version here, it is the very drift this paragraph warns about). Web *search* lags; fetch the gem's own
  `CHANGES.md` / `gh api .../releases` for the exact version, and trust `bundle outdated` /
  `gh` / rubygems over memory. If a changelog truly isn't retrievable, say so + classify.
3. 🔴 **`--upgrade-package` names a target; it does NOT bound the resolution** (2026-08-06). `uv pip
  compile … --upgrade-package gitpython==3.1.57 --output-file <FRESH path>` bumped **twelve** packages,
  including `cryptography 50.0.0` at age 6 days — i.e. straight past the quarantine, under a command
  whose flag said "one package". The existing lock **is** the preference set: writing to a new path
  discards it and re-resolves everything to latest. **Always point `--output-file` at the committed
  lock** (or copy it there first), and verify by counting: `git diff <lock> | grep -E '^[+-][a-z0-9_.-]+=='`
  must yield exactly as many version lines as packages you named. Same family as "age the DIFF, not the
  PR title" — except here the stowaways come from your own command, not from Dependabot's.
4. **Release-age quarantine: a version younger than ~7 days waits — but the clock is a PROXY for how
  UNEXAMINED the release is, so weigh the publisher profile, not the calendar.** The last ~7 days are the prime
  window for a hijacked-maintainer / malicious-postinstall compromise — these get caught and yanked
  within days, so a short wait kills most of the class for free. Default: **don't auto-take a version
  younger than ~7 days; let it age** — a security fix you actually need discharges it (take it now).
  🔴 Examination discharges it too (2026-08-06, founder push): `cryptography 50.0.0` was taken deliberately at **age 6 days**, and that is
  neither the exception nor a bend. The threat class (hijacked maintainer / malicious postinstall) is
  ≈nil for pyca/cryptography: PyPI trusted publishing, wheels with no postinstall scripts (Rust/C
  extension), one of the most-watched packages in the ecosystem — so 6 days there buys what 7 buys for a
  random package. **The reasoning error to avoid is ASYMMETRY:** I had measured the CVE-exploitability
  side carefully (≈0 — we never decrypt PKCS#7) and taken the release-risk side *on faith*, then let two
  ≈0 quantities decide it — while never weighing the one non-zero cost, a second pass (re-installing the
  toolchain, re-reading context, re-validating, a separate commit + CI run). And an open High alert has
  the same cost you already accept for CodeQL noise: it buries the next real one. So: weigh **both**
  sides with the same rigour, and let the package's publishing profile — not the calendar — set the bar.
  Nothing in bundler/npm enforces this out of the box (pnpm's `minimumReleaseAge` does, for pnpm
  projects) → eyeball the publish date for anything outside a trusted core dep: `npm view <pkg> time`
  (`contracts/`, `subgraph/`), rubygems.org (gems), PyPI release history (ML/in-silico). Every `uses:`
  is SHA-pinned (`06_07 §1a`), so an action patch reaches CI only through a PR — date its diff (`#11`);
  what still floats is the payload (`#15`, `#43`).
5. 🔴 **The age rule cuts BOTH ways — a fresh PR can carry a long-ripe artifact** (2026-08-06). `#499`
  (`library/ruby` digest) opened that morning, i.e. "an hour old" by its title — but the digest itself
  had been pushed **23 days** earlier. Dating the artifact instead of the PR is what surfaced that we
  were three weeks behind on Ruby, and turned a one-line digest bump into a full 4.0.5→4.0.6 recipe.
  So the reflex is not only "don't take the young" but **"find out what's actually IN there"** —
  a PR's age tells you nothing in either direction. For docker tags read `tag_last_pushed` from the
  Hub API, and verify the digest **independently** via the registry manifest (`docker-content-digest`),
  not from the Hub JSON you just read. Sibling check worth one command: compare the tag's digest against
  its `-<suite>` variants (`4.0.6-slim` vs `4.0.6-slim-trixie`) — identical digests prove the base OS did
  NOT shift under you, which is what would silently move `libvips`/glibc floors. 🔴 **And the same
  measurement finds drift BEFORE Dependabot files anything** (2026-08-16): `ruby:4.0.6-slim` had been
  re-pushed 08-07 under an unchanged tag (`b6505477…` → `607bf92f…`, i.e. fresh Debian trixie patches at
  an identical Ruby version), and no docker PR existed in the open set although `docker` is one of the
  five automated ecosystems. The bot is a convenience, not the instrument — **make "read `tag_last_pushed`
  for the pinned base image" a standing step of the sweep**, because a digest bump is pure security patch
  and is invisible in every version-based inventory (`bundle outdated`, `gh api releases`) by construction.
  🔑 **And the release-age quarantine applies WEAKER to a base-image DIGEST bump — that is a
  difference in KIND of artefact, not an indulgence** [OPS.10]. A digest bump of `ruby:X-slim` is a
  REBUILD OF THE SAME TAG of the official image with patched OS packages; it introduces no new
  third-party version, no new maintainer, no new code — which is exactly what the quarantine is for.
  Contrast the same week's `cloud-sql-proxy` v2.25.4 at zero days of soak, which stayed under the
  ratified window because it WAS a new version of someone else's software. **So the question the
  quarantine really asks is not «how old is it» but «is this a new artefact or the same one
  repaired»** — and only the second reading lets a security rebuild land the day it ships, which is
  the whole point of pinning by digest rather than by tag.
  🔴 **A hand-pinned vendored BINARY has no bumper and may have no `.sha256` sidecar** — every
  hand-pinned binary, today medusa, aderyn and actionlint. (a) **Do not assume a sidecar exists**; the
  single reproducible source may be the release object itself. **Verify the verification with a POSITIVE
  CONTROL**: recompute the hash of the version you already trust and check it reproduces the committed
  pin, before trusting the number you computed for the new one. (b) **Dependabot cannot see a URL/`ver=`
  pin at all** — its docker ecosystem watches the base image's tag+digest and nothing else, so such a pin
  moves by hand or never (`#43`).
  🔴 **A green `bundler-audit` says nothing about the runtime you ship** — bumping a Ruby image, read the
  SOFT Trivy image scan (mechanism + instance → `06_07 §1a`).
6. 🔴 **A version perimeter is WIDER than its gate, and half the hits must NOT be edited** (Ruby bump,
  2026-08-06). `git grep 4.0.5` returned **15 files** while `ruby_version_sync.rb` guards **8** mirrors.
  The rest were *historical narrative* — the PR #463 post-mortem quoted inside `ci.yml`/`docs.yml`/the
  guard's own header ("образ 4.0.6 vs Gemfile 4.0.5"), plus two measurement records in the SPDX spec
  ("measured on Ruby 4.0.5 with a negative control"). A blind `sed` would have corrupted the incident
  write-up **and lied about the conditions a measurement was taken under.** Read every hit and ask
  "is this a PIN or a STORY?" — only pins move.
7. 🔴 **An owner-only drift guard watches PROSE; tool config satellites are outside it forever** (solc
  0.8.36, 2026-08-06). The tracker item warned that the 0.8.35 bump had left 9 stale `0.8.28` copies —
  and a stale copy showed up again, in `contracts/aderyn.toml` ("reads foundry.toml for solc 0.8.35").
  `solc_pragma_version_drift` only scans `docs/**`, so any `*.toml`/`*.json` that restates a version in
  a comment is invisible to it **by construction, not by oversight**. Grepping the tool configs is a
  manual step of the recipe, right next to the canon sweep.
8. 🔴 **After ANY generator writes, run the WHOLE lane — it touches files your diff never named**
  (2026-08-06, reddened `main` twice). `rake docs:repin` writes via `YAML.dump`, which serialises DATA
  only — every comment is dropped, and the SPDX header of `lib/canonical_block_pins.yml` **is** a
  comment. `spdx_headers.rb --check` is a separate HARD gate in the `CI · Docs` lane, alongside
  `model_doc_sync`, linter-specs and protocols-ref. Running `check_refs`+`tracker`, getting two honest
  exit-0s and concluding "docs are green" is a perimeter substitution: the measurement was true, it just
  covered a smaller set than I decided it did. (Fixed at the tool — repin now re-inserts the header.)
9. 🔴 **Measure a dependency's risk from the FILE DIFF against YOUR call path, not from the changelog**
  (CMSIS-DSP 1.17.1, 2026-08-06). The release advertises "corrected MVE float-to-Q15/Q31 conversions" —
  i.e. *numbers changing* — and the tracker rightly flagged it as a log-mel parity threat. But a
  changelog describes the whole project: `git diff v1.17.0 v1.17.1 -- Source/ Include/` showed 16 files,
  and **neither `arm_rfft_fast_f32.c` nor `arm_cfft_f32.c`** (our only call) was among them; the MVE
  paths are unreachable on Cortex-M4; and the one shared file changed a single table by adding `f`
  suffixes to literals already narrowed to `float32_t` — a table we never touch (log-mel calls libm
  `logf()`). A submodule hands you an exact diff — use it *before* deciding to be afraid.
10. 🔴 **A «bump needed» verdict on a git-pinned dependency is unverified until `git ls-remote` shows a
  newer ref — a dormant upstream means STUCK, not BEHIND** (LatticeLibrary, HW.33, 2026-09-09). The
  vendored submodule sat in the tracker as pending staleness; `git ls-remote` against the pinned URL
  showed our pin (`81c3c7b`, 4 commits past tag `PicoGK-v1.7.5`) **is** `HEAD main` — no newer tag or commit exists
  upstream (not archived, just dormant since 2025-07-27). Re-filing "needs bump" without this one
  command reports a false direction of drift. 🔑 **The same leg produced the mirror error on a
  NEIGHBOUR:** it had waved off `LEAP71_ShapeKernel` as "fresh 2026-06" on inherited say-so — re-measured
  itself, it is 7 commits behind (`166a459` → `7b90978`, 2026-08-10). A sibling's staleness label is a
  claim, not a fact, until you run the same command on it yourself. Generalises past PicoGK's vendored
  C# libs to any git-pinned dependency this skill routes through tags/commits rather than a registry
  (SKILL.md §Domains, «firmware C» and «.NET CAD» rows).
11. **Age the DIFF, not the PR title: a PR named for one ripe dependency can carry fresh transitives in the same lock-diff** (2026-07-16). A Dependabot PR is named for its *target* dep,
  but bundler re-resolves the target's own dependencies to latest in the same lock-diff — so a
  "ripe" PR smuggles fresh transitives past the gate. Seen: `pagy 43.5.6→43.6.0` (age 7d ✅) carried
  `json 2.20.0→2.21.1` (age **3d**) as a passenger. Read `gh pr diff <n>` and age **every changed
  line**, then weigh against the target's actual value (that pagy release only touched
  searchkick/elasticsearch paginators — `grep` said 0 uses → no-op, so zero cost to let it ripen). ⊕ **A version pair `X → Y` ages on BOTH sides** (2026-09-03): the target is the queue entry, the source is a measurement of whatever environment you happened to read — OPS.22 named PySCF 2.11.0 as «current» while `conda-lock.yml` resolved 2.13.1 (and RDKit differs per platform in the same lock). Point the queue at the lock; never restate the from-version.
12. 🔴 **A PR can be green BECAUSE something MASKS its breaking passenger — and then a green suite is evidence of the mask, not of compatibility** [OPS.22, 2026-09-13]. Dependabot #538/#542/#544 carried `json` 2.21.2 → 3.0.2 (a major, days old) under unrelated titles, all CI-green. Yet `json` 3.0 breaks `ActiveSupport::JSON.decode` on Rails 8.1.3.1 (options passed positionally → `ArgumentError: given 2, expected 1`, reproduced), and no spec can see it: `Oj.mimic_JSON` in an initializer replaces `JSON.parse` in every Rails-booted process. **Reflex for a passenger that is a known-incompatible major: ask WHO serves the API at runtime (`JSON.method(:parse).source_location` → `nil` means a C extension, i.e. the mask) and probe once with the mask ABSENT (a bare `bundle exec ruby` loading only `active_support/json`).** ⚠️ What the mask buys is load ORDER: any parse before that initializer runs, or in a process that never boots Rails, meets the unmasked break in production.
13. **`@dependabot rebase` changes the TARGET, not just the base** (2026-07-29) — so the quarantine
  clock **restarts**, and a PR that was ripe by its title is not. Seen the same session: `#477`
  simplecov 1.0.2 (11d ✅) came back as **1.0.3 (3d ❌)**; `#472` carried rbs 4.0.3 (41d ✅) and came
  back with **rbs 4.1.0 (0d ❌)**. This collides head-on with the row below: rebase is what ADDS a
  newly-required check, yet rebase is also what pulls fresh passengers in. **Always re-read and
  re-date `gh pr diff <n>` AFTER the rebase** — the title, and your earlier dating, are both stale.
14. **A required check added AFTER the PR opened is ABSENT, not red** (2026-07-29) — `gh pr checks`
  shows all-pass and the aggregate count silently comes up short (7/8 vs 8/8). GitHub reports the
  PR `BLOCKED` with nothing visibly failing. Seen: `DCO passed` became required 07-25; six PRs based
  on 07-23 simply had no such check. Diagnose by counting the required aggregates against
  `gh api repos/<o>/<r>/branches/main/protection --jq '.required_status_checks.contexts[]'`, not by
  eyeballing for red. Fix = `@dependabot rebase` (then re-date the diff, per the row above).
15. **A SHA-pinned action does NOT pin its own contents** (2026-07-29 → `00_07` OPS.21). The pin
  freezes the wrapper; a Docker-based action still installs its tool from PyPI/npm **fresh every
  run**. `crytic/slither-action@b52cc1cb` (v0.4.2) broke the required `Solidity passed` gate when
  `slither-analyzer 0.11.6` + `crytic-compile 0.4.2` shipped (both **1 day old**): 0.11.6 raised the
  floor to `crytic-compile>=0.4.2`, whose "disable Foundry dynamic test linking" calls `forge` even
  under `ignore-compile: true` — and `forge` lives on the runner, not inside the action's container
  (`FileNotFoundError: 'forge'`). Fix = pin the tool (`slither-version: 0.11.5`, which transitively
  caps `crytic-compile<0.4.0`). **The release-age quarantine has a structural blind spot here:** it
  guards `Gemfile`/`package.json`/conda, but never sees an action's image contents — a day-old
  package walked straight into the money-path gate. Prefer the shape already used elsewhere in this
  repo: `pip install --require-hashes -r requirements-*.txt` (halmos, medusa) or curl+sha256 (aderyn).
16. 🔴 **Identical failure on N INDEPENDENT PRs ⇒ the root is in the BASE, not in the PRs** (2026-07-30).
  Four Dependabot PRs (aws-sdk-s3, httpx, csv, simplecov) all red on `scan_ruby`; I opened their
  diffs first and that cost the most time of the sweep. The cause was one: `main` carried
  **CVE-2026-66066** (activestorage), so `bundler-audit` failed for everyone. **One unfixed advisory
  blocks the WHOLE Ruby perimeter** — and each PR's red is then somebody else's. Reflex: with ≥2
  identical failures, ask what they SHARE before reading any diff; fix `main` first, then rebase.
  Corollary on the quarantine: a security fix you actually need discharges it — `rails 8.1.3.1` was
  taken at age 1 day, deliberately, and that is the rule working, not bending. Need is not the only
  discharge (`#4`): the quarantine measures how UNEXAMINED a release is,
  so it is discharged by EXAMINATION as well as by need: a publisher profile that removes the
  threat class (trusted publishing, no postinstall, heavily watched) buys the same confidence the
  clock was standing in for. ⛔ Do not restore a COUNT here — an exception-count invites the next
  reader to defend a number instead of measuring the release. ⊕ Never rebase-and-retry per PR — fix
  the base, then re-run the rest.
  🔑 Sibling on the other blocker — a version CAP: reachability needs EVERY holder → `#34`.
17. 🔴 **A change YOU make to the BASE invalidates every open PR's green, and nothing marks them stale** (2026-08-22, OPS.27+OPS.22). Raising the CI Postgres major on `main` meant four Dependabot PRs opened two days earlier still displayed green from a run on the *previous* `ci.yml` — the checks were honestly earned against a CI that no longer exists. Note how this differs from the advisory-DB item (`#24`): there the world moved, here **you** moved it, so the reflex fires at a moment you control and can plan for. Two ways through, and the choice is about who validates: `@dependabot rebase` (the checks re-run on the new base — worth it when you *want* CI's verdict, e.g. to prove the base change is safe on the PR path too), or take the bump **locally** with `bundle update --conservative` and validate yourself (better when the risky part is something CI cannot see for you — here simplecov 1.1.0 rewrites the very coverage machinery our group-floor gate stands on, so the honest proof was `line 99.49 / branch 98.05` plus a fresh `.last_run.json`, i.e. evidence the gate RAN, not that the suite was green). ⚠️ After a base change, `gh pr checks` on an un-rebased PR is a statement about a workflow file you have already replaced.
18. 🔴 **A floor may only name what the CHANNEL can serve — and a resolver's «does not exist» is a claim about the INDEX it loaded, not about the channel** (librosa: rolled back on a false negative 2026-08-24, re-measured 2026-09-13). The `>=1.0` floor was reverted on two grounds, and both fell. **Channel:** conda-forge had served `librosa 1.0.0` since 2026-08-11 (`api.anaconda.org/package/conda-forge/<pkg>` → `files[].upload_time`); the local `mamba` answered from a months-old repodata cache. **Cache:** `setup-micromamba` keys the env cache on `-file-<sha256 of the spec>` with no restore-keys, so ANY floor edit resolves cold — the rollback's own `ML passed` run linked `librosa 1.0.0` fresh, i.e. the lane was never «green on an env built before the change». The floor is `>=1.0` since 2026-09-13. **Reflex: after editing a conda/npm/gem floor, dry-run the resolver against the COMMITTED spec (`mamba create -f … --dry-run`), and before acting on a NEGATIVE from it, ask the channel itself and read the resolve log of the first CI run.** ⚠️ Mirror for the writing: availability on the channel goes IN the spec next to the floor, with the date and the source you asked — a date-less «the channel lacks it» is exactly how the wrong verdict survived three weeks.
19. 🔴 **A «minor» can rework the very mechanism your GATE stands on — and then «suite green» is not the validation** (`simplecov` 1.1.0, 2026-08-22). The version bumped one minor and rewrote the coverage engine underneath it: accumulator instead of pairwise-fold, branch/method data in the resultset, a different `CommandGuesser`. A suite that passes proves the SUITE ran; it says nothing about whether the coverage gate still measured anything — and a gate that silently stopped measuring is the exact false-green this repo keeps paying for. **Validation for any bump of a tool that IMPLEMENTS a gate is evidence the gate EXECUTED: the line/branch numbers it printed, plus a freshly-written `.last_run.json`.** Generalise past simplecov — the same applies to rubocop, the linters, and anything whose output another check consumes. ⊕ **The probe for such a tool is blind until you neutralise the EARLIER check** (simplecov 1.2.0, 2026-09-13): `ExitCodeHandling` reports only the FIRST failing check, and on a subset run that is always the global floor — so per-group lines never print, and «identical output before/after» is green on an empty set. Zero the global floor for the probe (cp-backup, restore byte-for-byte), compare the group lines, and add a negative control: 1.2.0 reads a bare `per: "Services"` as a PER-FILE threshold, and that group's line vanishes.
20. 🔴 **Read a scary changelog line against OUR call, not against its own framing** (`tailwind_merge`, 2026-08-22). The release note led with «deep-freeze DEFAULTS to prevent global-state mutation», which reads as a direct threat to our custom text-scale registry. It is not: we pass `config:` into `TailwindMerge::Merger.new` — the official API — and never mutate the global DEFAULTS, so the hardening cannot reach us. The measurement is one `grep` for how we construct the object; without it the note buys a carve-out it does not deserve. Sibling of the call-site row below: a changelog describes the library's world, and only your own code says whether you live in the part that changed.
21. 🔴 **A changelog line that reads as housekeeping can still change what LEAVES the building — for every major, scan the notes for «default-on» / «removed the flag» before the API diff** (sentry 6→7, measured 2026-09-05; mirror of `#20`, and the more dangerous direction). The entry reads like housekeeping — «Logs are now enabled by default and `enable_logs` is removed», same for metrics. Nothing about our call-sites changes; nothing breaks; the suite would be green. What changes is that a **named third-party processor starts receiving Rails LOGS it did not receive before — and METRICS lose their off-switch** (default-on since 6.3.0 — `self.enable_metrics = true` in `configuration.rb` — inert until something calls `Sentry.metrics`; the 7.0 line «now enabled by default» describes the removed switch, not a new default: read the code, not only the changelog), which is a DPIA / Art.28 question, not a bump question — and it arrives as a *consequence* of the bump rather than as a decision, because the opt-out flag was **removed**, so there is nothing to grep for in our config. 🔑 **Reflex: for every major, scan the release notes for `default` / `enabled by default` / `now sends` / `removed the flag` BEFORE reading the API diff, and for each hit ask «does this move data, money, or permissions?» — those three answer to owners outside the dependency queue.** ⛔ And the honest response is not «skip the bump» but «bump with the new behaviour EXPLICITLY declared», so the next reader sees a decision instead of a default. 🔴 **And the declared-off FORM is read in the NEW version's source before the verdict is executed, never taken from the verdict's wording** (sentry 7.0.0, 2026-09-13): the ratified posture named «a mirror metrics flag», but 7.0 REMOVED `enable_logs`/`enable_metrics` outright — writing them raises NoMethodError at boot — and metrics had been default-on since 6.3.0 anyway. The real switches were `config.rails.structured_logging.enabled = false` plus the `before_send_log`/`before_send_metric` callbacks. A verdict drafted from release notes can be right in intent and unexecutable in form, and literal obedience ships a crashing boot.
22. **The SAME failure on N INDEPENDENT PRs means the root is on `main`, not in any diff** — same rule and incident as `#16`, which holds the body. A Critical-security fix is taken at any age — one of the quarantine's discharges (`#4`, `#16`) — because until it lands the whole perimeter is blocked.
23. 🔴 **«This major touches OUR call-sites» is a claim about a FILE — open it before writing the carve-out** (`#500`, 2026-08-10). A major was routed to the founder on the grounds that the new version forces `file_field` to emit `accept`, i.e. *changes our markup*. Reading the call-site killed it: our form already passes `accept:` as an explicit literal, and the gem's own upgrade note says explicit values are never overridden — so the render does not change at all, and the single inference site in the tree could not fire. **The carve-out had been written against a hypothesis, and it would have spent a founder decision on nothing.** Sibling of `#24`: there a green tick predated the question, here a verdict predated its evidence. Cost is asymmetric and therefore invisible — an unnecessary carve-out never reds, it just waits.
24. 🔴 **A PR's green check has a DATE, and the advisory DB moves independently of it — so an old green
  attests to a world where the CVE did not yet exist** (2026-08-10, same root as `#16` — an advisory in the base). `#501`
  displayed `scan_ruby` SUCCESS dated 08-06; the `json` advisory (CVE-2026-71847) only landed in
  `ruby-advisory-db` on 08-08. The tick was honestly earned — *before the question was asked* — so
  merging on it means trusting a measurement that predates its own subject. Note this is the mirror of
  the identical-failure rule: there the reds were somebody else's, here the **greens** are. Two
  consequences: (a) on any PR older than a day, `gh pr checks` tells you about the base at run time,
  never about today; (b) the honest re-measure is your own full local run over the applied bump
  (`bundle update <gems> --conservative` → full `bin/rspec` + `bin/rubocop` + `bin/bundler-audit`),
  or a rebase that forces CI to run again — never re-reading the tick. ⚠️ And the same asymmetry that
  makes rebase expensive applies: re-running CI restarts the quarantine clock, while the local run
  does not, so prefer the local run when the diff is small enough to apply by hand.
25. 🔴 **Judge the checks on the NEW head by STATE, never by colour — `SKIPPED` wears the same green as `SUCCESS`** (2026-08-28, `#523` buildx; migrated from OPS.22 2026-09-02). After a rebase the honest read of `gh pr checks` is the state histogram: SUCCESS · SKIPPED · NEUTRAL · FAILURE · PENDING, and merge only when FAILURE and PENDING are both ZERO — a path-gated job that did not run is `skipped`, which the summary line renders as a green tick, so «all green» can mean «half of it never ran». The measurement that bought this: the PR's pre-rebase green stood on a base 435 commits behind `main`; after `@dependabot rebase` the head changed, status went `BLOCKED`→`CLEAN`, and the histogram on the NEW head read 30 SUCCESS · 12 SKIPPED · 1 NEUTRAL · 0 FAILURE · 0 PENDING.
26. 🔴 **The RED check has a date too — and a green neighbour does not disprove it** (2026-08-16). `#24`
  says a stale green attests to a world before the CVE; the mirror is that a stale **red** attests
  to a base that has since been fixed, and it is harder to spot because red reads as "this PR is broken".
  Five PRs sat red on `scan_ruby` from 08-10 while `main` already carried the fix. What made the diagnosis
  hard was that the "identical failure ⇒ root in the base" rule looked *refuted*: `#509` sentry-rails was
  **green in the same minute** as `#507` sentry-ruby was red — same bump 6.6.2→6.7.0, same upstream. The
  answer was in the lock diff's COMPOSITION: `#507` touched only sentry, so it left `json 2.21.1`
  (CVE-2026-71847) in place and reddened *honestly*; `#509` happened to drag `json 2.21.2`+erb+rbs+reline+
  zeitwerk along as passengers, and the advisory vanished with them. **So "age the DIFF, not the PR title"
  has a third face: a passenger is sometimes not a risk but an ACCIDENTAL CURE — and then the check's
  colour reports the diff's composition, not the bump's quality.** Diagnose by opening the failing job's
  LOG; a cause inferred from a neighbouring commit is a guess wearing a verdict's clothes (here I blamed
  `brakeman --ensure-latest`, which had genuinely reddened `main` three days earlier, and was wrong).
27. 🔴 **`built_at` on rubygems is DEAD as an age signal — it returns `1980-01-02`** (2026-08-16). Reproducible
  builds normalise the gemspec timestamp, so all ten gems measured that day reported the same 1980 date.
  A quarantine computed from it measures a file-format artefact, not a release. Use `created_at` from
  `https://rubygems.org/api/v1/versions/<gem>.json` (the push time), and treat any age field that looks
  identical across unrelated packages as an instrument failure, not as a finding.
28. 🔴 **A security patch can EXPOSE a latent debt rather than break you — read the failure that way first**
  (2026-07-30). `rails 8.1.3.1` "broke" boot; in truth we had `variant_processor = :vips`, libvips in
  the Dockerfile and `.variant()` in three live places — and **no `ruby-vips` gem**, so variant
  generation in prod had been dead *silently*. Upstream made it loud on purpose. Note the shape that
  hid it: `image_processing` **repackages** any LoadError into `"ImageProcessing::Vips requires the
  ruby-vips gem"`, and `engine.rb` matches `case error.message` on `/libvips/` and `/image_processing/`
  — neither matches (capitalised) → `else raise`, i.e. boot-crash instead of the intended warn.
  Reflex: when a bump fails, ask "what does this prove was already broken?" before reverting.
29. 🔴 **Adding a NATIVE gem can make require ORDER load-bearing** (2026-07-30 → `config/application.rb`).
  glib (via `ruby-vips`) loaded BEFORE `argon2id` ⇒ `__stack_chk_fail` in `initial_hash`, **SIGABRT
  (134)**, macOS-only, CI green. Reverse order is clean — a 3-line repro without Rails settles it.
  Why Rails hit the bad branch although `argon2id` came early in the Gemfile: at the time,
  **`require "rails/all"` ran BEFORE `Bundler.require`**, and `activestorage/engine.rb` mentions
  `ImageAnalyzer::Vips` in the class body → autoload beats Gemfile order. The fix is `require "argon2id"`
  ahead of every railtie in `config/application.rb`, whose header carries the repro. Diagnose order via
  `$LOADED_FEATURES` **indices** — a `Kernel#require` prepend is blind to `Bundler.require` (it calls
  the `Kernel.require` singleton). And measure a native crash from the crash report, not from an
  upstream comment: `.ips` is **JSON**, `usedImages[imageIndex]` names the exact library (here
  `argon2id.bundle` — my libxml2/nokogiri theory, borrowed from the Rails patch's own comment, was
  wrong). Take the crash report BEFORE the theory.
30. **SHA==tag verification has a wrong endpoint that reads as a mismatch** (2026-07-30):
  `git/ref/tags/<tag>` returns the SHA of the **tag OBJECT** for an annotated tag. Use
  `gh api repos/<o>/<r>/commits/<tag> --jq .sha` (or deref `git/tags/<sha>`).
31. 🔴 **The version COMMENT beside a SHA pin is a convention, and Dependabot preserves whichever form it
  finds — so "unifying" it is a silent convention change riding a `build(deps)` subject** (2026-08-16).
  Both forms live here on purpose-by-accident: major (`# v4`, `# v7`, `# v1`) and exact
  (`# v2.21.1`, `# v0.36.0`) — and the bot wrote both, proven by `e2cd58c7`, which bumped
  codeql-action's SHA and left its `# v4` untouched. A major comment does **not lie** when the SHA
  resolves to v4.37.6; it names the same action at coarser granularity, so there is nothing to fix.
  **Rule: update the comment only where its form is already exact; leave a major one as-is.** Otherwise
  a routine bump rewrites the style of lines nobody asked about. Canon states the convention as
  `# vN` (`06_07`, OPS.10 paragraph), and no gate compares the comment against its pin — the same
  blind spot as `#42`.
32. **A gate that did not RUN is not green** (2026-07-29). `Solidity passed` showed green on most PRs
  only because `dorny/paths-filter` skipped the job. The breakage above surfaced solely on the two
  PRs that touched `solidity_audit.yml` — they did not break Slither (`#15`), they **made it run**. Before
  trusting an aggregate, ask whether its jobs actually executed on this diff (same family as `#33`).
33. **A green Dependabot PR can still break `main`** (2026-07-16 → OPS.13, now hard-gated). Ask what
  actually *builds* the changed artifact and on which trigger. The historical hole: the only docker
  build (`mirror-ghcr.yml`) runs on `workflow_run[branches: main]` — not `pull_request` — so a
  `library/ruby` bump touched only the Dockerfile while `Gemfile` held a hard `ruby "X.Y.Z"` pin ⇒
  `bundle install` died *after* merge (PR #463). Since 2026-07-16 two gates hold the line:
  `scripts/ruby_version_sync.rb` (version parity across ALL mirrors — the script's `MIRRORS` is the
  authoritative list; `docs.yml`) + `docker_smoke` in `ci.yml` (full image build on the PR, in the
  required `ci-ok`). **A Ruby bump is still the full every-mirror recipe (SKILL.md §Domains, «Ruby itself» row) +
  `rvm install` + full suite — never a merge button; the gates make the shortcut red, not safe.**
34. **Transitive caps block "latest" — and that's not our drift.** A bump can be held back by a
  depending gem's constraint; document the blocker, don't force it (forcing breaks the holder). **A
  transitive cap is SOMEBODY ELSE'S constraint line — it loosens silently on THEIR release, while we keep
  it recorded as state and never re-measure.** So the rule has two halves: **(1) re-measure a cap the
  moment its HOLDER is bumped; (2) before declaring reachability, INVENTORY every holder — the answer is
  the intersection, not the one line you happened to read** (2026-09-05: `lookbook` 2.3.15 relaxed
  `marcel` to `>= 1.0`, but `activestorage` still pins `~> 1.0` — «the cap fell» was true about the holder
  I had noticed and false about reachability, and nothing reddens on that gap). ⛔ «The cap fell» is not
  «take it» either: taking a major because it became reachable is the «newer = better» this skill
  forbids — read the changelog first. ⛔ Never derive reachability from a changelog: derive it from a
  run — `bundle update <gem> --conservative` on a **backed-up lock** answers in one command (measured
  that evening: six of seven «majors» did not move a single version). ⊕ Cheap holder inventory without a
  full resolve: scan `Gemfile.lock` for every block whose dependency list names the gem — the `~>`/`<`
  bounds are all right there. Detect a cap with `bundle update <g>` «stayed the same» / `pip check`;
  revert an over-bump to the capped version. Live holder inventory → `00_07` OPS.22 WATCH («Мажори
  `bundle outdated`…»); env caps → the `tools/ml/environment.yml` and `requirements-conda-lock.in`
  headers (dulwich: documented blocker + Scorecard dismiss-with-reason, re-check on every conda-lock bump).
35. **GitHub caps `dismissed_comment` at 280 and answers 422 — send dismissals one by one, ≤280 BYTES, or one long reason half-applies the batch.** The two alert APIs take DIFFERENT reason vocabularies:
  `code-scanning/alerts/<n>` → `false positive` · `won't fix` · `used in tests`; `dependabot/alerts/<n>` →
  `not_used` · `tolerable_risk` · `inaccurate` · `no_bandwidth` · `fix_started`. Dismiss: `gh api -X PATCH
  repos/<o>/<r>/<api>/alerts/<n> -f state=dismissed -f dismissed_reason=… -f dismissed_comment="…"`; reopen
  with `-f state=open` when the decision flips from *accept* to *FIX*. Fixed findings auto-close on the
  tool's next scan — you dismiss only what you are deliberately **not** fixing.
  🔴 **The 422 is loud but *late*: in a batch it kills the alerts after the long one, leaving the sweep
  half-applied and looking finished.** Write the reason as a tweet with an ID to follow (`SEC.30 / canon
  04_03 §2.2б`), never as an essay, and length-check **before** sending. 🔴 **І міряй БАЙТИ, не символи — одиницю ми так і не перевірили, а кирилиця важить удвічі** (2026-09-07): чернетковий коментар мав 266 символів при **368 байтах**. Двозначність знімається запасом, а не вірою: тримай ≤280 БАЙТІВ і питання не виникає. ⊕ Причина теж не одна на всіх (Dependabot-словник): `not_used` = адвізорі про API, якого наш споживач НЕ КЛИЧЕ (доказ grep-ом, постійний, `#46`) ⊥ `tolerable_risk` = код присутній і був би живий, просто ми не запускаємо той шлях (це ПОЛІТИКА, не факт про код). Злиття їх в одну причину робить слабшу підставу спільною для всіх. Instances → memory `project_dependabot_sweep`.
36. **Conda `>=` env vs lock: the ML env is a loose `>=` floor spec, while in-silico runs on a real `conda-lock.yml`.** ML env is a `>=` spec (raise floors to tested-current — esp. the
  DSP floor that protects the parity contract; read the current literal in
  `tools/ml/environment.yml`, never from here). 🔴 **And a `>=` floor plus a CACHED,
  path-gated CI job is not the guard it reads as:** the env only re-resolves when the cache
  is cold, so the first run on a new major lands on an unrelated PR, unattended. Before
  moving that floor, verify the new major BY HAND against the contract it guards — the
  bit-level comparison, not just a green suite. in-silico has a real
  `conda-lock.yml` — that's the reproducible pin the DFT ran on; the env.yml floors are loose
  on purpose. A local conda env can drift behind the lock (re-sync with `conda-lock install`).
  📌 **The GENERATOR is pinned too — the `uv==` line in the `requirements-conda-lock.in` header**
  (read the literal there). CI only *consumes* that lock (`pip install --require-hashes`), so the only thing
  touching `uv` is a human at regeneration time, and an unpinned one rewrites row order, comments
  and marker shape across the whole file — turning a one-line bump into an unreadable diff.
  `uv` is not on the machine by default: install it into a throwaway venv at the pinned version,
  never globally. **Verify the recipe, not just the diff: a second compile must produce a
  BYTE-IDENTICAL file** — that single check proves both the pin and that your `.in` edits (comments
  included) did not perturb resolution.
37. **CI actions are SHA-pinned with a `# vN` label — nothing auto-flows; every bump, patch included, arrives as a Dependabot PR and is dated like any other.**
  Verify the SHA (`#30`); keep the comment's form (`#31`).
38. **Firmware/Solidity full validation is CI-gated (ARM build + QEMU; slither) — locally only the host gates run.**
  Push → CI does the rest; judge the run by `gh run view <id> --json conclusion`, never by `gh run watch
  --exit-status` (it lies — `deploy` §Gotchas #6). mruby/CMSIS-FFT bumps risk the ARM↔x86 bit-parity /
  log-mel parity — keep `evm_version`/float flags pinned, lean on the parity gates.
  🔴 **І дзеркальна половина, куплена червоним `main` 2026-09-22: локально ганяється БІЛЬШЕ, ніж ти
  памʼятаєш, і все одно МЕНШЕ, ніж ганяє гейт.** Бамп `forge` пройшов `forge test` (усі інваріанти
  PASS) і `forge fmt --check` — дві осі з трьох, і це читалось як повна валідація. Третьою був
  **gas snapshot check**, а нова мінорна версія рахує газ інакше: на НЕЗМІННОМУ коді снапшот
  розʼїхався від +23% до +178% і поклав required-гейт. 🔑 **Рефлекс перед бампом будь-якого
  інструмента, що стоїть за required-чеком: периметр валідації бери з КРОКІВ його workflow
  (`grep -n "run:" <workflow>`), а не з памʼяті про команду** — «я прогнав інструмент» і «я прогнав
  те, що ганяє гейт» є різними твердженнями, і друге вужче рівно на ті кроки, яких ти не назвав.
  ⊕ Сиблінг того ж проходу, протилежного знаку: та сама версія агрегувала інваріант-сюїту в ОДИН
  прогін, тож лічба тестів упала 242→237 при незмінному покритті — **зміна ОДИНИЦІ лічби виглядає
  як втрата, а зміна ОБЛІКУ газу виглядає як регресія; обидві судяться перелічуванням ЧЛЕНІВ
  (які саме інваріанти PASS, які саме рядки снапшоту), ніколи підсумком.**
39. **Terraform provider majors are big breaking migrations — read the per-major upgrade guide, never blind-bump** (e.g. `google` 5→7 = renamed/removed
  args across Cloud SQL/GCE/VPC/IAM). Read the per-major upgrade guide; bump the `~>` constraint,
  refresh the lock (below), then `terraform plan` against real state — never a blind sweep bump.
  🔴 **BASELINE FIRST, and the guide itself demands it: a plan diff after the major means NOTHING
  without a plan BEFORE it** — pre-existing drift gets attributed to the provider. Measured
  2026-09-06 on google 7→8: three plans against live state (current 7.x → newest 7.x → 8.x), each
  read for deprecation notices, and the verdict taken from `terraform show -json <planfile>` —
  `resource_changes` with every action `no-op` — not from the human summary line.
  ⛔ **NEVER refresh the lock with a plain `terraform init -upgrade`** — the only correct form is
  `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` (why, and why exactly those
  platforms → `06_07 §1a`). Verify by deleting `.terraform/providers` and running a fresh `init` — it
  must reinstall and say "signed by".
40. **Deprecation/future-keyword warnings: resolve them in OUR code; in vendored code they are upstream's — note, don't touch.**
  Examples: solc `error`/`at` → rename (ours); OZ `EnumerableSet.at()` (vendored).
41. **`db/structure.sql` / `Gemfile.lock`: verify the diff is ONLY the intended dep (no drive-by
  churn) before committing.**
42. **Canon docs mirror pinned versions — sweep them too (a bump is not done at the manifest).**
  The SSOT docs pin versions in prose: `06_07 §1a` (supply-chain POLICY — no `@vN` literals, but it
  quotes `uv==` and the provider `~>`: sweep those on a uv/provider bump; the action pin is the SHA, its
  `# vN` is a label — `#31`), `05_03` (solc/pragma + OpenZeppelin), `06_01` (Terraform
  provider `~>`, Ruby, Cloud SQL Postgres), `03_01 §12.4` (submodule tags). Code + docs drift
  apart silently (the solc incident → `#7`). After any bump: grep the canon for the OLD literal and
  reconcile, then `docs:check_refs`. The `solc_pragma_version_drift` guard (`00_06 §3`) holds the solc
  line (owner = `05_03`); there is no such guard for CI-action / provider / PG versions — grep those by hand.

43. 🔴 **Dependabot pins the WRAPPER, never the payload — so every payload pin in this repo is bumper-less BY CONSTRUCTION** [OPS.21]. ⛔ Do not carry a COUNT here: the set grows with each hardening pass and a stale tally reads as an inventory. Enumerate it instead — the blind CLASSES are what stay true: **(1) an action's own `version:`/`*-version:` INPUT** — `github-actions` reads `uses:` and nothing else (`foundry-toolchain`, `terraform_version`, `micromamba-version`, `slither-version`); **(2) service-container `image:` inside `.github/workflows/**`** — the `docker` ecosystem is scoped to the directory you declare, ours is `/` i.e. the `Dockerfile`, so those digests sit frozen; **(3) a toolchain config file the CI merely POINTS AT** (`tools/cad/global.json` via `global-json-file`) — no Dependabot ecosystem is configured for it; **(4) a version or hash inside a `run:` step, or a hash-locked `requirements-*.txt` it installs** (`ACTIONLINT_VERSION`, aderyn/medusa `ver=`, `gem install kamal -v`, `--require-hashes`) — there is no pip ecosystem in `dependabot.yml`; **(5) Kamal `accessories.*.image` in `config/deploy*.yml`**.
44. **Enumerate payload pins from source with one grep, and draw a hardening perimeter by WHO INSTALLS the tool (workflow ⊥ action image ⊥ action input), never by which job it runs in.** Roster: `grep -nE '^\s+[A-Za-z_-]*(version|VERSION):|\bver=|image:|global-json-file:|--require-hashes|gem install [^#]*-v ' .github/workflows/*.yml .github/actions/*/action.yml config/deploy*.yml`. That is why Slither cannot be hash-pinned at all (its installer is the action's image, so `--require-hashes` has no seam to attach to) while its sibling steps can: same job, three different installers, three different verdicts. A perimeter drawn by job would have declared the pass complete with the payload still floating. ⚠️ Every alternative in that pattern is load-bearing and was learned by the recipe failing on its own subject: without `_` `terraform_version:` does not match, and the lower-case-only first draft missed every class (4)/(5) pin — the guard-craft «a form-keyed scan knows only the spellings its author happened to use» applied to a one-line grep. **Every class of `#43` is therefore a MANUAL step of this recipe, not an automated one**, and each pin says so in a comment next to it — a pin whose staleness nobody can see is worse than the floating tag it replaced.
  🔴 **⊥ Updates are `directory:`-scoped; security ALERTS come from the repo-wide dependency graph** [OPS.35], so a new manifest turns the scanner on for a folder `dependabot.yml` never named (`subgraph/package-lock.json`: a batch of alerts, one critical, before any `/subgraph` entry existed). That is a change of VISIBILITY, not of exposure — name the perimeter, don't roll back the gate; a reader who applies the `directory:` rule here concludes «we never declared this folder, so it is not ours» — exactly backwards. Class + instance → `ssot-maintenance` §Guard-craft #106.
45. ⚠️ **The `slither-version` pin and the leaflet version are dated upstream NEGATIVES — re-check each with two HTTP calls before re-deriving either.** The `slither-analyzer` pin stays needed while upstream ships no fix for the `ignore-compile` Foundry path; `leaflet` has nowhere to move while its latest IS the pinned version, with only an alpha beyond. Dates and reopen triggers live in `00_07` OPS.22 WATCH — read them there. A dated negative is worth as much as a finding: it removes suspicion until the next release of either.
46. 🔴 **Ask a transitive advisory whether it names the API our consumer ACTUALLY calls — non-applicability outlives the upstream fix** [OPS.35, 2026-08-30 · 2026-09-07]. Before «is there a patch» and even before «is the package reachable», read which symbol the advisory names and `grep` the consumer for it: it is cheap and gives the most durable answer, because incompatibility disappears with the fix while non-applicability does not. Measured twice, so a class, not a coincidence: GHSA-w5hq-g745-h8pq hits `uuid` `v3`/`v5`/`v6` with a passed `buf`, and `jayson` calls only `v4()` without one; GHSA-528h-pc64-c93x hits `stream-json`'s `pick`/`ignore`/`filter`/`replace` path filters, and `jayson` imports only `StreamValues` and `Verifier`. ⛔ Keep the two grounds apart: «the fix breaks the consumer» means we CARRY the risk while we wait; «the advisory is not about our call» means there is no risk and nothing to wait for. Re-measure = the `require` grep in the consumer + re-reading the named methods — a ground that does not rot with a release. Instances → SKILL.md §Domains, «Subgraph» row; dismissal reason → `not_used` (`#35`).
47. 🔴 **A DEFAULT gem is invisible to BOTH advisory channels until it is pinned in the `Gemfile` — so step 0 must read the ruby-lang security feed by hand** [OPS.22, 2026-09-19]. Dependabot reads `Gemfile.lock` against the GitHub DB, `bundler-audit` reads `Gemfile.lock` against ruby-advisory-db — and a default gem the app never pins (`resolv`, `json`, `erb`, `net-*` …) is simply not in the lock. Measured: ruby-lang posted CVE-2026-80212/80213 for `resolv` 0.4.0–0.7.1 on 2026-08-27, Ruby 4.0.6 ships 0.7.0, and 23 days passed with zero alerts on either ADVISORY channel. 🔴 **But a scanner DID see it — and was silenced:** the SOFT image scan flagged it on 08-30 (Trivy #354/#355), and on 09-05 the alerts were dismissed on an INVERTED ground — «absent from `Gemfile.lock`, so our bundle does not activate it». For a default gem, absence from the lock is exactly why the DEFAULT copy is what gets activated; the ground had been measured for `json` (the lock's 2.21.2 shadows the default) and carried over to `resolv` by analogy — a member's ground applied to the container (`ssot-maintenance` guard-craft #102). An adversarial review of a TRACKER trim found it on 09-19. **So dismissing a default-gem finding needs its OWN ground: is THIS gem shadowed by a lock entry?** Our paths were real (`ssrf_filter` calls `Resolv.getaddresses`, `httpx` encodes DNS messages through it). 🔑 **Fix without waiting for a Ruby release: pin the patched gem (`gem "resolv", "~> 0.7.2"`), with the removal condition in the comment — the next Ruby patch that ships the fixed version.** ⛔ Do not read a green `bundler-audit` + zero Dependabot alerts as «the runtime is clean»: they are a statement about the LOCK. Re-check = `https://www.ruby-lang.org/en/news/` security posts against `ruby -e 'require "X"; puts X::VERSION'` for each default gem our code (or a gem we call) requires. ⊕ **The loop closes by its own condition — and closing it RE-BLINDS the channel** (2026-09-26, `242dfb223`): Ruby 4.0.7 shipped `resolv` 0.7.2, so the pin went in the same commit as the Ruby bump, and from then on the gem is invisible to both ADVISORY channels again — its carriers are step 0 and the SOFT image scan, whose default-gem findings need the per-gem ground above before any dismissal. ⚠️ Probe a NEW Ruby's defaults with a clean gem env (`env -u GEM_HOME -u GEM_PATH <new ruby> -e …`): an inherited `GEM_PATH` loads the old Ruby's native bundles and fails for a reason that is not Ruby's.

48. 🔴 **A DAILY-release gem makes `latest` almost never ripe — and `bundle update --conservative` fetches exactly `latest`** [OPS.22, 2026-09-02]. For a package that publishes ~daily (`aws-partitions`), the release-age quarantine (`#4`) stops being a wait and becomes a permanent block on `latest`: take the newest **RIPE** version and pin the lock BY HAND (`bundle install` validates a hand-pinned lock). ⊕ And Dependabot opens no PR for **lock-only transitives** at all, so that queue is assembled locally and never read off the PR list — a sweep that starts from `gh pr list` is blind to it by construction.

49. 🔴 **Before "update the tool", ask whether the needed version is ALREADY in the tree by another path** [OPS.35, 2026-08-27]. A wall of transitive alerts can come not from a stale tool but from an INTERMEDIATE package pinning its own deps to EXACT versions, so npm cannot dedupe them against already-patched copies sitting beside them in the same `node_modules`. `npm ls <pkg> --all` answers this in a second, and `overrides` on those same versions clears the alerts **without depending on upstream at all**. ⚠️ Two halves without which the rule harms: (a) measure on a copy **outside** the repo (`overrides` rewrite the lock, and the run must be the same build CI does); (b) `npm audit fix --force` proposed a **DOWNGRADE** of the tool by seven minors — npm's "fix" is a claim about the graph, never about fitness.

50. 🔴 **A ZERO from an inventory command is a claim about the INSTRUMENT until a positive control says otherwise** [2026-08-23]. Twice in one sweep: `pip list` inside a conda env returned **0 rows against 207 installed packages** (cure: `python -m pip list` — the form the Domains table already uses), and `git submodule status` described a pin by a FOREIGN tag (`mruby` as «master+14450» while that very SHA **is** tag `4.0.0`) — i.e. "we are behind" was a property of `git describe`, not of the tree. **Before concluding a lag, check the SHA against the tag list; before believing an empty inventory, prove the environment is populated.**

51. ⚠️ **`pip-compile` resolves markers for the platform that COMPILES, and a flag that names a target may bound nothing** [OPS.22]. Compile **INTO** the committed lock and compare the count of version lines: a flag naming the target is not a claim that the resolution was bounded by it, and the difference shows up only against the lock you already had.

52. 🔴 **"How many vulnerabilities do we have" is a choice of INSTRUMENT, not a fact — and severity is the wrong third axis** [OPS.35, 2026-08-27]. `npm audit` and the GitHub Dependabot channel counted **15 vs 44** over the same tree (the latter counts advisory-per-package separately), so report in the units the reader actually sees. ⊕ The axis that costs more than severity is **REACHABILITY**: the single `critical` in that wall was unreachable from our execution path (imported by one command CI never invokes) and two of its three advisories had no fix at all — severity is a statement about a package in a vacuum. Same axis one level down, at the API: `#46`.

53. 🔴 **A dismissal whose alert KEY carries a version is a treadmill — the next bump reopens it under a new number, so fix the SOURCE, not the instance** [OPS.22, 2026-09-26]. GitHub code scanning keys an alert by rule + location, and the location path carries the gem version: four doc-example JWTs in the SSO-OIDC client documentation that ships inside `aws-sdk-core`, created 2026-08-27 and dismissed `false positive` 2026-09-05 (#348–351), closed as «fixed» when the 09-22 scan saw the SDK bump (09-21) and reopened on the very same lines as #361–364. The dismissal was right about the finding and useless about the channel — the founder's ground for dismissing («they keep glowing and barking», `06_07 §1a`) was never met. **Reflex: before dismissing, ask whether the alert's key survives the next bump of its package; if it does not, the durable cure is scanner config at the source** (here `.github/trivy-secret.yaml`, an allow-rule on the registry-gem container whose ground — `bundle install` runs with no secret in its environment — holds for every member, build artifacts included; the first draft's «only bytes from rubygems.org» was false, and the adversary caught it — `ssot-maintenance` guard-craft #102), **proved by the alerts auto-closing on the next CI scan** — not by the absence of a red. ⚠️ Narrowing a security scanner is a founder verdict, not a delegated one: the auto-mode classifier stopped the first commit as «Security Weaken», and it was right to.

54. 🔴 **A scanner's declared filter can be INERT on one output path — read the wrapper action's entrypoint at the pinned SHA, not its input list** [OPS.22, 2026-09-26]. `image_cve_scan.yml` carried `severity: CRITICAL,HIGH` for four weeks (08-28 → 09-26) and canon described the posture with it, but trivy-action's `entrypoint.sh` does `unset TRIVY_SEVERITY` for `format: sarif` unless `limit-severities-for-sarif: true` — so the Security tab received every severity. Two consequences, neither visible to any gate: a local `--severity` run measured a NARROWER set than CI (the «6 locally vs 40 in CI» once blamed on Trivy-DB snapshots — the 40 were 1 CRITICAL · 4 HIGH · 14 MEDIUM · 19 LOW · 2 UNKNOWN, so a working filter would have kept 5), and the lane the scan exists for (the Go module inside `thruster`) was, on its Medium days, visible ONLY because the filter was inert — «fixing» the filter would have silenced it (mutual masking). ⚠️ Its severity is a snapshot, not a property: on 0.1.25 the same lane was HIGH (#340–347). **Reflex: when a count or a severity looks impossible under a flag, open the action's code at the pinned SHA before theorising about the data.**
