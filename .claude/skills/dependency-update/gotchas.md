# Dependency update — hard-won gotchas (the bodies)

> **Companion file of the `dependency-update` skill. Open it before you merge, bump, pin or quarantine
> a dependency — any domain.** The one-line index in `SKILL.md` §Hard-won gotchas is the CARRIER; this
> file is the mechanism, the incident that bought it, and its bounds. Edit rules HERE — the index is
> generated (`ruby scripts/guard_craft_index.rb --write`).
>
> **Numbered on 2026-09-19, append-only from then on.** Before the split these were unnumbered
> bullets, so older citations name the section and never a number; the numbers follow the pre-split
> order. Cite `dependency-update #N`.

1. 🔴 **A vendored front-end package has its version in TWO places, and the tool sees only one** [TEST.7, 2026-08-03]. `leaflet` is pinned locally: JS in `vendor/javascript/leaflet.js` (visible to `bin/importmap outdated`) **plus** CSS and 5 PNGs in `vendor/assets/stylesheets/leaflet/` — ordinary files no inventory command knows about. So a bump must be **paired**, or the halves drift silently: a mismatched CSS raises nothing, it just breaks the map's layout. Three traps around it. (a) Re-pin with the **default jspm provider** — `--from unpkg` serves UMD with no ESM exports, so `import L from "leaflet"` dies. (b) The CSS ships **relative** `url(images/*.png)`, and Propshaft rewrites those to digested paths only while the images sit next to it — keep the `images/` subdir. (c) After ANY new pin, run `RAILS_ENV=test bin/rails assets:precompile` locally: a stale `public/assets/.manifest.json` keeps Propshaft on the **Static** resolver, and then every browser example fails **at login** (asset missing → the layout stub blanks the tags → page without JS). That symptom reads as broken authentication and costs an hour.
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
4. **Release-age quarantine (supply-chain). A version published in the last ~7 days is the prime
  window for a hijacked-maintainer / malicious-postinstall compromise** — these get caught and yanked
  within days, so a short wait kills most of the class for free. Default: **don't auto-take a version
  younger than ~7 days; let it age** — a security fix you actually need is the exception (take it now).
  🔴 **But the clock is a PROXY: what the quarantine actually measures is how UNEXAMINED the release is**
  (2026-08-06, founder push). `cryptography 50.0.0` was taken deliberately at **age 6 days**, and that is
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
  (`contracts/`), rubygems.org (gems), PyPI release history (ML/in-silico). A `@vN`-pinned CI action
  also floats to fresh patches that run in CI with secrets — SHA-pin the high-blast-radius ones
  (cf. tj-actions/changed-files, 2025).
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
  🔴 **A hand-pinned vendored BINARY has neither channel, and two lessons from ours outlived the binary
  itself — kept here because their home died with it** (`cloud-sql-proxy` was removed from the runtime by
  OPS.37 on 2026-08-29, taking the `Dockerfile` comment that carried them). (a) **Do not assume a
  `.sha256` sidecar exists.** Ours had none — 404 on every version tried, the GitHub release carried zero
  assets, and the hash table inside the release BODY was present only for some versions; the single
  reproducible source was the bucket object itself. **Verify the verification with a POSITIVE CONTROL**:
  recompute the hash of the version you already trust and check it reproduces the committed pin, before
  trusting the number you computed for the new one. (b) **Dependabot cannot see an `ADD --checksum` URL at
  all** — its docker ecosystem watches the base image's tag+digest and nothing else, so such a pin moves
  by hand or never. Both apply to any future vendored binary; neither is specific to the one that is gone.
  🔴 **And the mirror of that invisibility bites on the VERDICT side: a green `bundler-audit` says nothing
  about the runtime you ship.** Both advisory channels read a LOCK — `bundler-audit` parses `Gemfile.lock`,
  Dependabot reads repo manifests — so gems built into Ruby itself (`specifications/default/*.gemspec`)
  are outside both **by construction**. Measured 2026-08-28: the first `image_cve_scan` run surfaced a
  **critical** in the image's default `json` while `bin/bundler-audit` correctly reported "No
  vulnerabilities found", because the lock carries a newer copy of that same gem. Two true verdicts about
  two different surfaces, and nothing reddens on the gap. **Reflex when bumping a Ruby image: do not read
  a green gem-audit as runtime coverage** — the only instrument on that axis is the Trivy image scan, and
  it is SOFT by design. Home of the rule (do not restate the mechanism here) → `06_07 §1a`.
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
  showed our pin (`81c3c7b`, tag `PicoGK-v1.7.5`) **is** `HEAD main` — no newer tag or commit exists
  upstream (not archived, just dormant since 2025-07-27). Re-filing "needs bump" without this one
  command reports a false direction of drift. 🔑 **The same leg produced the mirror error on a
  NEIGHBOUR:** it had waved off `LEAP71_ShapeKernel` as "fresh 2026-06" on inherited say-so — re-measured
  itself, it is 7 commits behind (`166a459` → `7b90978`, 2026-08-10). A sibling's staleness label is a
  claim, not a fact, until you run the same command on it yourself. Generalises past PicoGK's vendored
  C# libs to any git-pinned dependency this skill routes through tags/commits rather than a registry
  (the firmware-C row above).
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
  taken at age 1 day, deliberately, and that is the rule working, not bending. 🔴 **This line read
  «exactly ONE exception» until 2026-09-07, and it contradicted the clock-is-a-PROXY paragraph
  above it in the same file** (`cryptography 50.0.0` at age 6 days — «neither the exception nor a
  bend»). Both are right; the count was wrong. The quarantine measures how UNEXAMINED a release is,
  so it is discharged by EXAMINATION as well as by need: a publisher profile that removes the
  threat class (trusted publishing, no postinstall, heavily watched) buys the same confidence the
  clock was standing in for. ⛔ Do not restore a COUNT here — an exception-count invites the next
  reader to defend a number instead of measuring the release.
  🔑 **Sibling on the OTHER blocker — a version CAP: ask not «did THIS holder relax it» but «is it
  the LAST holder»** (migrated out of the tracker 2026-09-07, [OPS.22]). Measured by getting it
  wrong: «a cap is somebody else's deadline» was applied to ONE holder with no inventory, so the
  verdict «the cap fell» was true about `lookbook` and false about REACHABILITY. Command: pull
  every declarer of the gem out of `Gemfile.lock`; only an EMPTY intersection of their
  constraints makes the version reachable.
17. 🔴 **The same date-rule has a SECOND cause, and this one is YOUR OWN doing: a change to the BASE invalidates every open PR's green, and nothing marks them stale** (2026-08-22, OPS.27+OPS.22). Raising the CI Postgres major on `main` meant four Dependabot PRs opened two days earlier still displayed green from a run on the *previous* `ci.yml` — the checks were honestly earned against a CI that no longer exists. Note how this differs from the advisory-DB row below: there the world moved, here **you** moved it, so the reflex fires at a moment you control and can plan for. Two ways through, and the choice is about who validates: `@dependabot rebase` (the checks re-run on the new base — worth it when you *want* CI's verdict, e.g. to prove the base change is safe on the PR path too), or take the bump **locally** with `bundle update --conservative` and validate yourself (better when the risky part is something CI cannot see for you — here simplecov 1.1.0 rewrites the very coverage machinery our group-floor gate stands on, so the honest proof was `line 99.49 / branch 98.05` plus a fresh `.last_run.json`, i.e. evidence the gate RAN, not that the suite was green). ⚠️ After a base change, `gh pr checks` on an un-rebased PR is a statement about a workflow file you have already replaced.
18. 🔴 **A floor may only name what the CHANNEL can serve — and a resolver's «does not exist» is a claim about the INDEX it loaded, not about the channel** (librosa: rolled back on a false negative 2026-08-24, re-measured 2026-09-13). The `>=1.0` floor was reverted on two grounds, and both fell. **Channel:** conda-forge had served `librosa 1.0.0` since 2026-08-11 (`api.anaconda.org/package/conda-forge/<pkg>` → `files[].upload_time`); the local `mamba` answered from a months-old repodata cache. **Cache:** `setup-micromamba` keys the env cache on `-file-<sha256 of the spec>` with no restore-keys, so ANY floor edit resolves cold — the rollback's own `ML passed` run linked `librosa 1.0.0` fresh, i.e. the lane was never «green on an env built before the change». The floor is `>=1.0` since 2026-09-13. **Reflex: after editing a conda/npm/gem floor, dry-run the resolver against the COMMITTED spec (`mamba create -f … --dry-run`), and before acting on a NEGATIVE from it, ask the channel itself and read the resolve log of the first CI run.** ⚠️ Mirror for the writing: availability on the channel goes IN the spec next to the floor, with the date and the source you asked — a date-less «the channel lacks it» is exactly how the wrong verdict survived three weeks.
19. 🔴 **A «minor» can rework the very mechanism your GATE stands on — and then «suite green» is not the validation** (`simplecov` 1.1.0, 2026-08-22). The version bumped one minor and rewrote the coverage engine underneath it: accumulator instead of pairwise-fold, branch/method data in the resultset, a different `CommandGuesser`. A suite that passes proves the SUITE ran; it says nothing about whether the coverage gate still measured anything — and a gate that silently stopped measuring is the exact false-green this repo keeps paying for. **Validation for any bump of a tool that IMPLEMENTS a gate is evidence the gate EXECUTED: the line/branch numbers it printed, plus a freshly-written `.last_run.json`.** Generalise past simplecov — the same applies to rubocop, the linters, and anything whose output another check consumes. ⊕ **The probe for such a tool is blind until you neutralise the EARLIER check** (simplecov 1.2.0, 2026-09-13): `ExitCodeHandling` reports only the FIRST failing check, and on a subset run that is always the global floor — so per-group lines never print, and «identical output before/after» is green on an empty set. Zero the global floor for the probe (cp-backup, restore byte-for-byte), compare the group lines, and add a negative control: 1.2.0 reads a bare `per: "Services"` as a PER-FILE threshold, and that group's line vanishes.
20. 🔴 **Read a scary changelog line against OUR call, not against its own framing** (`tailwind_merge`, 2026-08-22). The release note led with «deep-freeze DEFAULTS to prevent global-state mutation», which reads as a direct threat to our custom text-scale registry. It is not: we pass `config:` into `TailwindMerge::Merger.new` — the official API — and never mutate the global DEFAULTS, so the hardening cannot reach us. The measurement is one `grep` for how we construct the object; without it the note buys a carve-out it does not deserve. Sibling of the call-site row below: a changelog describes the library's world, and only your own code says whether you live in the part that changed.
21. 🔴 **The MIRROR of that row, and it is the more dangerous direction: a changelog line that does NOT read as scary can still change what LEAVES the building — and «default-on» is the tell** (sentry 6→7, measured 2026-09-05). The entry reads like housekeeping — «Logs are now enabled by default and `enable_logs` is removed», same for metrics. Nothing about our call-sites changes; nothing breaks; the suite would be green. What changes is that a **named third-party processor starts receiving two data categories it did not receive before**, which is a DPIA / Art.28 question, not a bump question — and it arrives as a *consequence* of the bump rather than as a decision, because the opt-out flag was **removed**, so there is nothing to grep for in our config. 🔑 **Reflex: for every major, scan the release notes for `default` / `enabled by default` / `now sends` / `removed the flag` BEFORE reading the API diff, and for each hit ask «does this move data, money, or permissions?» — those three answer to owners outside the dependency queue.** ⛔ And the honest response is not «skip the bump» but «bump with the new behaviour EXPLICITLY declared», so the next reader sees a decision instead of a default. 🔴 **And the declared-off FORM is read in the NEW version's source before the verdict is executed, never taken from the verdict's wording** (sentry 7.0.0, 2026-09-13): the ratified posture named «a mirror metrics flag», but 7.0 REMOVED `enable_logs`/`enable_metrics` outright — writing them raises NoMethodError at boot — and metrics had been default-on since 6.3.0 anyway. The real switches were `config.rails.structured_logging.enabled = false` plus the `before_send_log`/`before_send_metric` callbacks. A verdict drafted from release notes can be right in intent and unexecutable in form, and literal obedience ships a crashing boot.
22. 🔴 **The SAME failure on N INDEPENDENT PRs means the root is on `main`, not in any diff** (rails 8.1.3.1 / CVE-2026-66066, 2026-07-30). While an advisory sits unfixed in the committed lock, `bundler-audit` reds `CI passed` on *every* Ruby PR — so a queue of unrelated bumps all go red at once and each looks individually broken. Diagnosing them one by one is the wasted pass. **Reflex before triaging a queue: ask whether the failures are the SAME, and if they are, fix the base first and re-run the rest — never rebase-and-retry per PR.** This is also the quarantine's one standing exception: a Critical-security fix is taken at any age, because until it lands the whole perimeter is blocked.
23. 🔴 **«This major touches OUR call-sites» is a claim about a FILE — open it before writing the carve-out** (`#500`, 2026-08-10). A major was routed to the founder on the grounds that the new version forces `file_field` to emit `accept`, i.e. *changes our markup*. Reading the call-site killed it: our form already passes `accept:` as an explicit literal, and the gem's own upgrade note says explicit values are never overridden — so the render does not change at all, and the single inference site in the tree could not fire. **The carve-out had been written against a hypothesis, and it would have spent a founder decision on nothing.** Sibling of the row above: there a green tick predated the question, here a verdict predated its evidence. Cost is asymmetric and therefore invisible — an unnecessary carve-out never reds, it just waits.
24. 🔴 **A PR's green check has a DATE, and the advisory DB moves independently of it — so an old green
  attests to a world where the CVE did not yet exist** (2026-08-10, same root as the row above). `#501`
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
26. 🔴 **The RED check has a date too — and a green neighbour does not disprove it** (2026-08-16). The row
  above says a stale green attests to a world before the CVE; the mirror is that a stale **red** attests
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
  Why Rails hit the bad branch although `argon2id` is Gemfile line 8: **`require "rails/all"` (line 4
  of `application.rb`) runs BEFORE `Bundler.require` (line 8)**, and `activestorage/engine.rb`
  mentions `ImageAnalyzer::Vips` in the class body → autoload beats Gemfile order. Diagnose order via
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
  Both forms live here on purpose-by-accident: major (`# v4`, 56×`# v7`, 15×`# v1`) and exact
  (`# v2.20.0`, `# v0.36.0`) — and the bot wrote both, proven by `e2cd58c7`, which bumped
  codeql-action's SHA and left its `# v4` untouched. A major comment does **not lie** when the SHA
  resolves to v4.37.6; it names the same action at coarser granularity, so there is nothing to fix.
  **Rule: update the comment only where its form is already exact; leave a major one as-is.** Otherwise
  a routine bump rewrites the style of 11 lines nobody asked about. Canon states the convention as
  `# vN` (`06_07`, OPS.10 paragraph), and no gate compares the comment against its pin — the same
  blind spot as the `@vN`-in-prose sweep at the bottom of this file.
32. **A gate that did not RUN is not green** (2026-07-29). `Solidity passed` showed green on most PRs
  only because `dorny/paths-filter` skipped the job. The breakage above surfaced solely on the two
  PRs that touched `solidity_audit.yml` — they did not break Slither, they **made it run**. Before
  trusting an aggregate, ask whether its jobs actually executed on this diff (same family as the
  OPS.13 "ask what builds the artifact, and on which trigger" row below).
33. **A green Dependabot PR can still break `main`** (2026-07-16 → OPS.13, now hard-gated). Ask what
  actually *builds* the changed artifact and on which trigger. The historical hole: the only docker
  build (`mirror-ghcr.yml`) runs on `workflow_run[branches: main]` — not `pull_request` — so a
  `library/ruby` bump touched only the Dockerfile while `Gemfile` held a hard `ruby "X.Y.Z"` pin ⇒
  `bundle install` died *after* merge (PR #463). Since 2026-07-16 two gates hold the line:
  `scripts/ruby_version_sync.rb` (version parity across ALL mirrors — the script's `MIRRORS` is the
  authoritative list; `docs.yml`) + `docker_smoke` in `ci.yml` (full image build on the PR, in the
  required `ci-ok`). **A Ruby bump is still the full every-mirror recipe (row 2 of the table) +
  `rvm install` + full suite — never a merge button; the gates make the shortcut red, not safe.**
34. **Transitive caps block "latest" — and that's not our drift.** A bump can be held back by a
  depending gem's constraint; document the blocker, don't force it (forcing breaks the holder):
  seen this session — `eth` caps openssl `~>3.3` + bigdecimal `~>3.1`; `rbsecp256k1` caps
  rubyzip `~>2.3`; ~~`lookbook` caps rouge `<5.0` + htmlentities `~>4.3.4`~~ — 🔴 **RELAXED BY THE HOLDER'S OWN 2.3.15 RELEASE (2026-09-05): `rouge (<6.0)`, `htmlentities (~> 4.3)`, `marcel (>= 1.0)`.** The lesson outlives this row: **a transitive cap is SOMEBODY ELSE'S constraint line — it loosens silently on THEIR release, while we keep it recorded as state and never re-measure.** So re-check every cap the moment its HOLDER is bumped, not when you happen to remember. ⛔ And «the cap fell» is not «take it»: taking a major because it became reachable is the «newer = better» this skill forbids — read the changelog first (`rouge` 5.1.0 was then taken deliberately: dev-only via lookbook, zero call-sites of ours; `marcel` was not, see below).
  🔴 **AND THE SAME SESSION PRODUCED THE MIRROR ERROR, which is the more valuable half: «the cap fell» is a claim about ONE holder, and reachability needs ALL of them** (2026-09-05, measured the same evening). The line above originally concluded «one routine patch quietly unblocked **two** majors» — false. `lookbook` did relax `marcel (~> 1.0)` → `(>= 1.0)`, but a second holder was never re-measured: **`activestorage` pins `marcel (~> 1.0)`, i.e. Rails itself caps it.** The verdict «the cap fell» was true about the holder I had noticed; the conclusion «therefore reachable» was false, and nothing reddens on that gap. **So the rule has two halves, and only the first was written: (1) re-measure a cap when its holder is bumped; (2) before declaring reachability, INVENTORY every holder — the answer is the intersection, not the one line you happened to read.** ⛔ Never derive reachability from a changelog: derive it from a run. `bundle update <gem> --conservative` on a **backed-up lock** answers in one command and is the only honest instrument (measured that evening across seven «majors»: six did not move a single version — `bigdecimal` held by `eth` **and** `ttfunk`, `diff-lcs` by rspec's two, `marcel` by activestorage, `openssl` by `eth`, `redis` by `kredis`, `retriable` by `google-apis-core`; only `rouge` moved). ⊕ Cheap holder inventory without a full resolve: scan `Gemfile.lock` for every block whose dependency list names the gem — the `~>`/`<` bounds are all right there.
  `rspec` caps `rspec` caps
  diff-lcs `<2.0`; **TF** caps h5py `<3.15`; `conda-lock` caps dulwich `<0.25` while the
  PYSEC-2026-2462..66 fix lives only in 1.2.5 (documented blocker in requirements-conda-lock.in;
  Scorecard alert → owner dismiss-with-reason — re-check on every conda-lock bump). Detect with
  `bundle update <g>` "stayed the same" / `pip check`. Revert the over-bump to the capped version.
35. **Dismissing an alert via `gh api`, and the 280-char wall that eats a batch.** List:
  `gh api repos/<owner>/<repo>/code-scanning/alerts?state=open`. Dismiss: `-X PATCH -f
  state=dismissed -f dismissed_reason="won't fix" -f dismissed_comment="…"`; reopen with
  `-f state=open` when the decision flips from *accept* to *FIX*. Fixed findings auto-close on
  the tool's next scan — you dismiss only what you are deliberately **not** fixing.
  🔴 **GitHub caps `dismissed_comment` at 280 characters and answers 422 — it does not truncate
  silently.** So the failure is loud but *late*: in a batch it kills the alerts after the long
  one, leaving the sweep half-applied and looking finished. Write the reason as a tweet with an
  ID to follow (`SEC.30 / canon 04_03 §2.2б`), never as an essay, and length-check **before**
  sending. 🔴 **І міряй БАЙТИ, не символи — одиницю ми так і не перевірили, а кирилиця важить удвічі** (2026-09-07): чернетковий коментар мав 266 символів при **368 байтах**, тобто був би за капом, якби той виявився байтовим. Двозначність знімається запасом, а не вірою: тримай ≤280 БАЙТІВ і питання не виникає. ⊕ І шли ПООДИНЦІ з перевіркою кожної відповіді — саме батч перетворює одну 422 на напівзастосований свіп, що має вигляд закінченого. ⊕ `dismissed_reason` теж не один на всіх: `not_used` = адвізорі про API, якого наш споживач НЕ КЛИЧЕ (доказ grep-ом, постійний) ⊥ `tolerable_risk` = код присутній і був би живий, просто ми не запускаємо той шлях (це ПОЛІТИКА, не факт про код). Злиття їх в одну причину робить слабшу підставу спільною для всіх. Instances → memory `project_dependabot_sweep_2026_07`.
36. **Conda `>=` env vs lock: the ML env is a loose `>=` floor spec, while in-silico runs on a real `conda-lock.yml`.** ML env is a `>=` spec (raise floors to tested-current — esp. the
  DSP floor that protects the parity contract; read the current literal in
  `tools/ml/environment.yml`, never from here). 🔴 **And a `>=` floor plus a CACHED,
  path-gated CI job is not the guard it reads as:** the env only re-resolves when the cache
  is cold, so the first run on a new major lands on an unrelated PR, unattended. Before
  moving that floor, verify the new major BY HAND against the contract it guards — the
  bit-level comparison, not just a green suite. in-silico has a real
  `conda-lock.yml` — that's the reproducible pin the DFT ran on; the env.yml floors are loose
  on purpose. A local conda env can drift behind the lock (re-sync with `conda-lock install`).
  📌 **The GENERATOR is pinned too — `uv==0.12.3`, in the `requirements-conda-lock.in` header**
  (2026-08-16). CI only *consumes* that lock (`pip install --require-hashes`), so the only thing
  touching `uv` is a human at regeneration time, and an unpinned one rewrites row order, comments
  and marker shape across the whole 84 KB file — turning a one-line bump into an unreadable diff.
  `uv` is not on the machine by default: install it into a throwaway venv at the pinned version,
  never globally. **Verify the recipe, not just the diff: a second compile must produce a
  BYTE-IDENTICAL file** — that single check proves both the pin and that your `.in` edits (comments
  included) did not perturb resolution.
37. **CI actions: we major-pin `@vN` → latest patch auto-flows; only a *new major* needs a bump.**
  Most stay current; check each with `gh api`. SHA-pinned actions update differently (Dependabot).
38. **Firmware/Solidity full validation is CI-gated (ARM build + QEMU; slither) — locally only the host gates run.** The host gates
  (forge test, host CMSIS-parity ctest, `make -C firmware/test`) run locally; push → CI does the
  rest; `gh run watch <id> --exit-status` confirms. mruby/CMSIS-FFT bumps risk the ARM↔x86
  bit-parity / log-mel parity — keep `evm_version`/float flags pinned, lean on the parity gates.
39. **Terraform provider majors are big breaking migrations — read the per-major upgrade guide, never blind-bump** (e.g. `google` 5→7 = renamed/removed
  args across Cloud SQL/GCE/VPC/IAM). Read the per-major upgrade guide; bump the `~>` constraint,
  refresh the lock (below), then `terraform plan` against real state — never a blind sweep bump.
  🔴 **BASELINE FIRST, and the guide itself demands it: a plan diff after the major means NOTHING
  without a plan BEFORE it** — pre-existing drift gets attributed to the provider. Measured
  2026-09-06 on google 7→8: three plans against live state (current 7.x → newest 7.x → 8.x), each
  read for deprecation notices, and the verdict taken from `terraform show -json <planfile>` —
  `resource_changes` with every action `no-op` — not from the human summary line.
  ⛔ **NEVER refresh the lock with a plain `terraform init -upgrade`.** It writes hashes only for
  the platform it ran on, and `terraform init` runs on **linux_amd64** in TWO CI places (`ci.yml`
  validation + `terraform_drift.yml`), so a lock made on the founder's darwin_arm64 reds both.
  The only correct form: `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`
  (the platform list = those that actually run `init`, never "just in case" — each one you add
  enlarges the lock and none of the extras is ever verified). Verify by deleting
  `.terraform/providers` and running a fresh `init` — it must reinstall and say "signed by".
  ⊕ `.terraform.lock.hcl` is **committed since 2026-09-06**; before that the `~>` constraint was
  the only pin and every `init` took any matching minor with NO checksum verification.
40. **Deprecation/future-keyword warnings: resolve them in OUR code; in vendored code they are upstream's — note, don't touch.**
  Examples: solc `error`/`at` → rename (ours); OZ `EnumerableSet.at()` (vendored).
41. **`db/structure.sql` / `Gemfile.lock`: verify the diff is ONLY the intended dep (no drive-by
  churn) before committing.**
42. **Canon docs mirror pinned versions — sweep them too (a bump is not done at the manifest).**
  The SSOT docs pin versions in prose: `06_07 §1a` (⚠️ it holds the SHA-pinning POLICY, not the version literals — do not sweep it looking for `@vN`; the live pin is the `# vN` comment beside each SHA in `.github/workflows/**` + the foundry
  config), `05_03` (solc/pragma + OpenZeppelin), `05_04` (anchor pragma), `06_01` (Terraform
  provider `~>`, Ruby, Cloud SQL Postgres), `03_01 §12.4` (submodule tags). Code + docs drift
  apart silently — this repo's solc `0.8.28 → 0.8.35` left **9 stale doc copies** until a follow-up
  swept them. After any bump: grep the canon for the OLD literal and reconcile, then `docs:check_refs`.
  The `solc_pragma_version_drift` guard (`00_06 §3`) now holds the solc line (owner = `05_03`);
  there is no such guard for CI-action / provider / PG versions yet — grep those by hand.

43. 🔴 **Dependabot pins the WRAPPER, never the payload — so every payload pin in this repo is bumper-less BY CONSTRUCTION** [OPS.21]. ⛔ Do not carry a COUNT here: the set grows with each hardening pass and a stale tally reads as an inventory. Enumerate it instead — the three blind CLASSES are what stay true: **(1) an action's own `version:`/`*-version:` INPUT** — `github-actions` reads `uses:` and nothing else (`foundry-toolchain`, `terraform_version`, `micromamba-version`, `slither-version`); **(2) service-container `image:` inside `.github/workflows/**`** — the `docker` ecosystem is scoped to the directory you declare, ours is `/` i.e. the `Dockerfile`, so those digests sit frozen; **(3) a toolchain config file the CI merely POINTS AT** (`tools/cad/global.json` via `global-json-file`) — no ecosystem reads it at all.
44. Roster from source, never from memory: `grep -nE '^\s+[a-z_-]*version:|image:|global-json-file:' .github/workflows/*.yml`. 🔑 **And the reflex that decides the PERIMETER, migrated out of the tracker 2026-09-07 because it lived nowhere else: measure a hardening pass by WHO INSTALLS the tool — workflow ⊥ the action's own Docker IMAGE ⊥ the action's INPUT — never by which job it runs in.** That is why Slither cannot be hash-pinned at all (its installer is the action's image, so `--require-hashes` has no seam to attach to) while its sibling steps can: same job, three different installers, three different verdicts. A perimeter drawn by job would have declared the pass complete with the payload still floating. ⚠️ The `_` in that character class is load-bearing and was learned by the recipe failing on its own subject: without it `terraform_version:` does not match, so the first draft silently omitted four of the pins it was written to enumerate — the guard-craft «a form-keyed scan knows only the spellings its author happened to use» applied to a one-line grep. **Both are therefore a MANUAL step of this recipe, not an automated one**, and both say so in a comment next to the pin — a pin whose staleness nobody can see is worse than the floating tag it replaced. ⚠️ Same shape as the SHA-pin lesson one level up: `crytic/slither-action` was SHA-pinned while its image installed `slither-analyzer` fresh on every run, and an upstream release blocked money-path merges for three days. **Measure a perimeter by WHO INSTALLS the tool (workflow ⊥ action image ⊥ action input), never by which job it runs in.**
  🔴 **⊥ І ця ж клауза вчить ПРОТИЛЕЖНОМУ, якщо перенести її на АЛЕРТИ — межа названа 2026-08-27 [OPS.35].** «Екосистема скоупиться текою, яку ти оголосив» правдиве для **оновлень**: `dependabot.yml` справді відкриває PRʼи лише по оголошених `directory:`. **Для security-алертів це хибно** — вони йдуть із репо-широкого графа залежностей і жодного `directory:`-скоупу не знають. Виміряний інстанс: `subgraph/package-lock.json` зʼявився разом із CI-компілятором субграфа [OPS.34], у `dependabot.yml` запису `/subgraph` на той момент **не було**, і Dependabot однаково відкрив по ньому цілий пакет алертів, серед них один critical. ⚠️ Запис додано ПІЗНІШЕ, тим самим [OPS.35] — але як канал ОНОВЛЕНЬ, тобто вже після того, як алерти прийшли: вимір від цього не слабшає, а формулювання «немає й досі», що стояло тут до 2026-08-29, робило його хибним твердженням про сьогодні. 🔑 **Отже завести гейт — це ще й УВІМКНУТИ СКАНЕР на теку, якої той доти не бачив**: змінилась ВИДИМІСТЬ, не експозиція (ті самі вразливості вже були б у дереві при локальному білді), і правильний присуд — не відкотити гейт, а назвати периметр. ⚠️ Читач, що застосує сюди правило про `directory:`, виведе «ми цю теку не оголошували, отже нас це не стосується» — рівно навпаки. Дім класу — `ssot-maintenance` §Guard-craft #106.
45. ⚠️ **Two upstream facts worth re-checking rather than re-deriving** (re-verified 2026-08-24 and both reproduced unchanged, cheap to re-verify — two HTTP calls each): the `slither-analyzer` pin is still needed (upstream has shipped no fix for the `ignore-compile` Foundry path, and `crytic-compile` is unchanged since the incident); and `leaflet` has nowhere to move — its latest IS the pinned version, with only an alpha beyond. A dated negative is worth as much as a finding here: it removes suspicion until the next release of either.
