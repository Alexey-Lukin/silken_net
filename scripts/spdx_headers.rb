#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [UNI.3] SPDX per-file licence headers — idempotent rollout engine.
#
# WHY THIS EXISTS. The repository carries four licences (AGPL-3.0-or-later for code,
# MIT for contracts/, CERN-OHL-S-2.0 for hardware design, CC-BY-SA-4.0 for docs) but
# states them only in root LICENSE files. Automated licence scanners (SPDX/SBOM tools,
# GitHub's detector, an enterprise buyer's SCA pass) read per-file identifiers; without
# them ~1400 tracked source files read as *unlicensed*, which is the opposite of what a
# defensive-publication, copyleft-enforcement posture needs. Posture → docs/00_01 §8;
# scope + named ceilings → THIS HEADER (it cannot drift from the code); state → 00_07 UNI.3.
#
# ENUMERATION IS `git ls-files`, NEVER `find` / `grep -r`. This is the single most
# important guardrail from the audit. A raw filesystem walk sees ~1440 files already
# carrying SPDX tags, but essentially all of them live inside git submodules
# (firmware/extern/*, tools/cad/extern/*) or gitignored build output
# (contracts/node_modules, contracts/out, medusa corpora). Writing there means editing
# another project's checkout, or writing into files the next `forge build` / `npm ci`
# overwrites. Through `git ls-files` a submodule is a single gitlink entry, so its
# contents are structurally invisible and cannot be reached by accident.
#
# 🔴 THE FINDING THAT REVERSED THE WRITTEN PLAN. The retired rollout audit prescribed
# inserting the tag *after* Ruby magic comments ("НІКОЛИ перед ними"), on the theory
# that a line above `# frozen_string_literal: true` silently disables it. Measured on
# Ruby 4.0.5 with a negative control, that theory is false: the magic comment is honoured
# anywhere in the leading comment block, with or without a shebang above it. The
# prescription was not merely unnecessary — it was actively harmful, because a comment
# placed directly after the magic comment trips RuboCop's
# Layout/EmptyLineAfterMagicComment, which would have turned ~999 Ruby files red in one
# commit. Hence the rule implemented here: **line 1, or line 2 when a shebang owns line
# 1 — never after the magic comment.** Verified clean for all four Ruby shapes present in
# this repo (magic-first, shebang+magic, plain-comment-first, code-first).
#
# NAMED CEILINGS (deliberate exclusions, not oversights):
#   · *.erb — an ERB comment emits a blank line into RENDERED output;
#     app/views/pwa/manifest.json.erb serves JSON and layouts/application.html.erb would
#     gain whitespace before <!DOCTYPE>. A `<%# ... -%>` trim form exists and was rejected
#     as clever-over-boring (CLAUDE.md §4). Founder call, 2026-07-26.
#   · schema dumps — db/structure.sql (pg_dump on every migration: the header is wiped and
#     shows up as a phantom minus-line in every future dump review) and
#     db/{cable,cache}_structure.sql (the same pg_dump output for the Solid Cable / Solid
#     Cache databases — `schema_format = :sql` makes Rails derive THESE names, and they are
#     regenerated from the gems' schema on the next solid-* upgrade; the installers'
#     `*_schema.rb` twins were removed 2026-09-02 because the SQL format never read them).
#     A tag here is not durable, and a tag that silently disappears later is worse than no
#     tag: it makes the gate lie.
#   · GENERATED headers are NOT excluded — their generators were TAUGHT to emit the tag
#     (emit_c.py `_banner`, gen_bytecode.sh heredoc, export/__init__.py). They are our own
#     output and must carry the licence; excluding them would leave them unlicensed for
#     good. `--check` gates then see the tag as part of the expected bytes. NB
#     firmware/bio_contracts/bio_contract.rb is hand-written source and IS tagged — but
#     gen_bytecode.sh stamps its sha256 into lorenz_bytecode.h, so tagging it REQUIRES
#     regenerating that header in the same commit.
#   · config/locales/** (136 files) — the CI step "Check locale YAML files are normalized"
#     compares each file BYTE-FOR-BYTE against a freshly rendered dump
#     (i18n-tasks file_formats.rb#normalized?), and that dump is produced by
#     Hash#to_yaml from a YAML.safe_load parse, which never captured a comment in the
#     first place. No position in the file survives — and the remedy the CI itself
#     suggests, `i18n-tasks normalize`, would silently DELETE the header on its next run
#     rather than fail loudly. Ceiling, with an upgrade path: locale-data licensing
#     belongs in an out-of-band declaration (REUSE `.reuse/dep5` or a directory LICENSE),
#     not an in-file comment. Everything else under config/ (45 files) is unaffected —
#     i18n-tasks reads only `config/locales/**`.
#   · *.json — strict JSON has no comment syntax; a header would break the file.
#   · binary assets we SHIP (images, fonts, compiled blobs) — the same reason as JSON but
#     absolute: a PNG has no comment syntax at all, so a tag is structurally impossible
#     rather than merely awkward. They are governed by the zone map in /NOTICE, and `plan`
#     keeps a `\0` tripwire for anything that slips the extension allow-list. 🔴 The
#     question such a file actually raises is PROVENANCE ("ours, stock, or generated?"),
#     not licence — and that is a GIT question, never a question of the author's memory:
#     `git log --follow -- <path>` plus the body of the commit that introduced it answers
#     it in one command, because the reason a shipped asset exists is argued at the moment
#     it lands. Measured 2026-08-30 on app/assets/images/carbon-weave.png, where a tracker
#     leg had parked exactly that question on a human for two days as "the machine is
#     powerless here by construction". It was not. This class is named HERE because
#     /NOTICE calls this header the authoritative list of untagged classes, and until now
#     it did not name the one class that can never be tagged at all.
#   · third-party notices — a file carrying somebody else's copyright is reported and
#     NEVER stamped (FOREIGN_NOTICE_RE); two vendor-derived firmware headers are in that
#     state today. Founder call 2026-07-26: no tag at all rather than an inexact one.
#   · encrypted / key material (*.enc, *.key) — not text, corrupting it is unrecoverable.
#   · tools/in_silico/conda-lock.yml — a third-party tool's output; conda-lock cannot be
#     taught to emit the tag, and it rewrites the file wholesale.
#
#   ⚠️ The "a YAML round-trip drops the header" class above has a SECOND carrier, and it is
#   IN scope rather than excluded: `lib/canonical_block_pins.yml` is rewritten by our OWN
#   `rake docs:repin` via `YAML.dump`, which cost a red `CI · Docs` on 2026-08-06. Where the
#   generator is ours the cure is the opposite of an exclusion — teach it to re-insert the
#   header (done, docs.rake) — because the file must stay licensed. So when adding any new
#   generator that writes a tagged YAML/TOML file, ask which side of that line it falls on;
#   an exclusion is only right when the writer is a third party we cannot change.
#   · docs/**, .github/.claude/.kamal, public/, vendor/, *.tfvars.example (templates a
#     user copies into their own private config), *.toml manifests (tool config, the same
#     class as Gemfile), and the generated bin/ binstubs — of which exactly three are
#     hand-written and therefore IN scope, enumerated in BIN_OWNED because no regex can
#     tell authored-by-us from generated-for-us.
#
# BUILD LOGIC IS IN SCOPE, and that reverses an earlier call of mine. CMakeLists.txt, the
# cmake toolchain file, both linker scripts and the host-test Makefile were first excluded
# as "plumbing" — but they carry our own [FW.46]/[FW.55] tracker tags and the .ld files are
# written in Ukrainian prose and encode the real STM32WLE5JC memory map. That exclusion had
# borrowed the rationale for generated binstubs and misapplied it to hand-authored build
# logic; excluding a 367-line test harness while tagging Terraform was not defensible.
#
# 🔴 THE LESSON THIS CAMPAIGN ACTUALLY TAUGHT, kept here because the audit document that
# preceded it has been retired and this header is now the home of its reasoning. The
# written audit was thorough about OUR language and blind to everyone else's: all three of
# the expensive findings came from running the OTHER gates, not from reading the plan.
# i18n-tasks re-renders 136 locale files byte-for-byte (a tag there does not merely fail
# CI — `normalize` deletes it later, silently). Four generator drift-gates compare their
# output byte-for-byte, so the fix was to teach the generator, never to exclude its
# output. Two firmware headers carry a third party's copyright, where our tag would have
# been a false licence claim. None of the three is a Ruby problem, and none was visible
# from inside the tree being changed. Before the next repo-wide sweep: enumerate EVERY
# gate in the project, take a green baseline of all of them BEFORE the first write (you
# cannot tell "I broke it" from "it was already red" without one), and rehearse the whole
# thing on a throwaway clone.
#
# SELF-BLINDNESS, named because it is real: detection scans the first 15 lines for the
# literal `SPDX-License-Identifier`, so a source file that merely *discusses* the string
# near its top would be skipped as already-tagged. Exactly two files in this repo do
# that — this script and its spec — and both carry a genuine tag, so the skip is correct.
# Any future file of that shape must be tagged by hand.
#
# Pure Ruby, no Rails, no bundle. Read-only unless `--write` is passed.
#
#   ruby scripts/spdx_headers.rb                  # dry-run, whole repo
#   ruby scripts/spdx_headers.rb app lib          # dry-run, scoped to trees
#   ruby scripts/spdx_headers.rb app --write      # insert
#   ruby scripts/spdx_headers.rb --check          # exit 1 if anything is untagged (CI shape)
#   ruby scripts/spdx_headers.rb --verbose        # + resulting head of each file

require "English"

module SpdxHeaders
  AGPL = "AGPL-3.0-or-later"
  MIT  = "MIT"

  # How many leading lines are searched for an existing tag. Generous on purpose: the
  # CubeMX insertion point sits inside the USER CODE Header block, a few lines down.
  SCAN_LINES = 15

  # Wider window for the foreign-notice scan — a vendor block can sit below an ASCII logo.
  NOTICE_SCAN_LINES = 40

  TAG_RE = /SPDX-License-Identifier:\s*(\S+)/

  # 🔴 A file carrying somebody else's copyright notice must never be stamped with ours.
  # Two vendor-derived firmware headers in this repo do exactly that — an ST HAL config
  # template and a Semtech/ST secure-element identity header — and neither contains the
  # literal `SPDX-License-Identifier`, so TAG_RE is blind to them. Writing a bare
  # `AGPL-3.0-or-later` above a Semtech BSD notice is a false licence claim on third-party
  # code, which in a defensive-publication posture is the single most expensive mistake
  # available. Matched on ATTRIBUTION (a copyright mark near a year, a rights reservation,
  # or a Doxygen \copyright tag), not on the mere word — `scripts/dco_check.rb` discusses
  # "copyright-origin certification" in prose and must not trip.
  # ⛔ ДВА бекслеші в останній гілці НЕ є зайвим екрануванням: doxygen-тег Semtech
  # пишеться літеральним бекслешем перед словом, тож регекс мусить шукати сам бекслеш.
  # Виміряно 2026-08-28: `bin/rubocop -a` зрізав пару до одинарної, а `\c` у Ruby-регексі
  # є CONTROL-CHAR escape — детектор чужого копірайту тихо перестав ловити цілий
  # вендорський діалект, лишившись синтаксично валідним. Спіймала спека
  # `foreign_notice catches the real vendor notices`, не ревʼю й не лінтер.
  # 🔑 Тому автофікс на цьому файлі запускай лише разом із тією спекою.
  FOREIGN_NOTICE_RE = /(?:copyright|\(c\)|©)\W{0,20}\d{4}|all\s+rights\s+reserved|\\copyright\b/i
  #
  # 🔒 CEILING, названа після ⚖️ 2026-08-28 (UNI.3): цей детектор ключується на
  # копірайт-РЯДКУ, тож файл, скопійований дослівно й позбавлений копірайту, він
  # не побачить — і той отримає наш тег. Клас перевірено на найімовірнішому
  # кандидаті: `firmware/queen/lorawan_glue/` тримає 13 наших-тегованих файлів,
  # чиї коментарі згадують вендорські шаблони ST/Semtech. ⚖️ ПРИСУД — тег
  # ПРАВИЛЬНИЙ, і він стоїть на чотирьох незалежних осях: (1) жоден із 13 не несе
  # чужого копірайту, тобто детектор не помилився, а спрацював; (2) include-guard
  # у кожному — наш неймспейс (`SILKEN_*`); (3) vendor-згадки в них є НАШИМИ
  # українськими нотами про походження КОНТРАКТУ ([ARCH.34]), а не успадкованим
  # вендорським текстом — `timer.h` каже «контракт … поверх owned» дослівно;
  # (4) жоден не є КОПІЄЮ вендорського шаблону — обсяг і структура не сумірні
  # (⛔ діапазон рядків тут НЕ називаємо: він волатильний, і попередня редакція
  # мовчки викидала найбільший файл — саме той, чия шапка визнає роботу поверх
  # vendored LoRaMac-node, тобто найгіршого кандидата для цієї осі). Заповнення
  # конфіг-контракту значеннями є реалізацією ІНТЕРФЕЙСУ, і саме тому два сусіди
  # з ВИДИМИМ копірайтом (`firmware/hal_glue/stm32wlxx_hal_conf.h`,
  # `firmware/queen/lorawan_glue/se-identity.h`) лишаються без тега — асиметрії
  # між рішеннями НЕМАЄ, є один механізм на різних входах.
  # ⛔ Не «посилювати» детектор словом `template`: воно стоїть у НАШИХ нотах про
  # походження, тож ловило б рівно ті файли, які присуд визнав своїми.

  # …but OUR OWN copyright notice is not foreign. Without this, the day a SilkenNet
  # copyright header lands in a file, that file drops out of the rollout AND out of the
  # gate at the same time — silently, and in the same motion.
  OURS_RE = /SilkenNet|Silken\s+Net|GaiaNexus|Oleksii\s+Lukin/i

  # An extensionless file counts as source only when a shebang names an interpreter
  # whose comment character is `#` (lib/daemons/coap_listener is the sole case today).
  SHEBANG_HASH_LANG = /\A#!.*\b(?:ruby|python[\d.]*|bash|sh|zsh|perl)\b/

  LINE_COMMENT = {
    ".rb" => "#", ".rake" => "#", ".py" => "#", ".sh" => "#", ".tf" => "#",
    ".yml" => "#", ".yaml" => "#", ".cmake" => "#", ".graphql" => "#",
    ".c" => "//", ".h" => "//", ".cs" => "//", ".ts" => "//", ".js" => "//", ".sol" => "//",
    # Block-comment-only languages: CSS has no line comment at all, and a GNU ld linker
    # script accepts `/* */` exclusively — a `//` there is a syntax error, not a comment.
    ".css" => "/*", ".ld" => "/*"
  }.freeze

  BLOCK_CLOSE = { ".css" => " */", ".ld" => " */" }.freeze

  # Build files identified by NAME, because extension cannot identify them: a Makefile has
  # none, and CMakeLists.txt's `.txt` would otherwise admit every text file in the tree.
  # Both take `#` comments. ⚠️ Listed as plain strings, NOT via %w[] — inside %w a literal
  # `""` is a two-character string, not the empty string, which is exactly how the
  # extensionless rule silently matched nothing until a live dry-run exposed it.
  NAMED_BUILD_FILES = [ "Makefile", "CMakeLists.txt" ].freeze

  # `bin/` is majority Rails/Bundler-generated, so membership is ENUMERATED rather than
  # patterned: these three carry our own tracker tags or Ukrainian prose, the rest are
  # `bundle binstubs` / `rails new` output and are not our original work. A new
  # hand-written bin/ script needs a line here — deliberately, because no regex can tell
  # authored-by-us from generated-for-us.
  BIN_OWNED = %w[bin/coap_load bin/coap_smoke bin/forest_simulator].freeze

  # Checked FIRST — a deny hit wins over any allow rule below.
  DENY = [
    %r{(?:\A|/)extern/},                       # git submodules: another repository's code
    %r{\Adocs/},                               # CC-BY-SA via LICENSE-DOCS; no per-file tag by convention
    %r{\A\.github/}, %r{\A\.claude/}, %r{\A\.kamal/},
    %r{\Apublic/}, %r{\Avendor/},
    %r{\Adb/(?:structure|c(?:able|ache)_structure)\.sql\z}, # schema dumps: regenerated, tag not durable
    %r{\Aconfig/locales/},                     # i18n-tasks re-renders these — see below
    %r{\Atools/in_silico/conda-lock\.yml\z},   # third-party lock output; cannot teach conda-lock
    # Vendor-derived headers, adjudicated 2026-07-26: no tag rather than an inexact one.
    # They sit in DENY rather than relying on FOREIGN_NOTICE_RE because a decided case must
    # not keep the gate red forever — a permanently failing gate stops being read. The
    # guard stays armed for what it is actually for: a NEW vendored file nobody has judged.
    %r{\Afirmware/hal_glue/stm32wlxx_hal_conf\.h\z},        # © 2020 STMicroelectronics
    %r{\Afirmware/queen/lorawan_glue/se-identity\.h\z},     # Semtech Revised BSD + ST portions
    %r{\.erb\z},                               # emits into rendered output — named ceiling
    %r{\.enc\z}, %r{\.key\z},                  # encrypted blobs: never touched
    %r{\Acontracts/(?:node_modules|out|cache|crytic-export|medusa-corpus)},
    %r{\A\.[^/]+\z}                            # root dotfiles (.rubocop.yml, .rspec…) — tool config, Gemfile class
  ].freeze

  # Allow-list: a file is touched ONLY if some rule names its tree AND its extension.
  # Anything unlisted is left alone by construction — the safe default for a sweep of
  # this size. `""` admits extensionless files, still gated on the shebang test above.
  ALLOW = [
    [ "contracts/", %w[.sol],                        MIT ],
    [ "app/",       %w[.rb .rake .js .css],          AGPL ],
    [ "lib/",       [ ".rb", ".rake", ".yml", "" ],      AGPL ],
    [ "spec/",      %w[.rb],                         AGPL ],
    [ "scripts/",   %w[.rb],                         AGPL ],
    [ "db/",        %w[.rb .yml],                    AGPL ],
    [ "config/",    %w[.rb .yml .yaml],              AGPL ],
    [ "firmware/",  [ ".c", ".h", ".rb", ".py", ".sh", ".cmake", ".ld" ], AGPL ],
    [ "tools/",     %w[.py .rb .sh .cs .yml],        AGPL ],
    [ "terraform/", %w[.tf .sh],                     AGPL ],
    [ "subgraph/",  %w[.ts .sh .yaml .graphql],      AGPL ],
    [ "deploy/",    %w[.rb .sh .yaml],               AGPL ],
    [ "bin/",       %w[.sh],                         AGPL ]
  ].freeze

  module_function

  # Repo-relative paths of tracked files, optionally narrowed to `paths`.
  # `--` separates the pathspec, so a stray `-x` argument cannot be read by git as an
  # option. The exit-code check is not ceremony: outside a repo (a container without .git,
  # a `dubious ownership` refusal) git prints to stderr and returns nothing, and without
  # this the gate would report "everything is tagged" over an empty file list.
  def tracked_files(root, paths = [])
    out = IO.popen([ "git", "-C", root, "ls-files", "-z", "--", *paths ], &:read)
    raise "git ls-files failed in #{root} (status #{$CHILD_STATUS.exitstatus})" unless $CHILD_STATUS.success?

    out.split("\0").reject(&:empty?)
  end

  # The licence a path is due, or nil when it is out of scope.
  def licence_for(path)
    return nil if DENY.any? { |re| re.match?(path) }
    return AGPL if BIN_OWNED.include?(path)
    if NAMED_BUILD_FILES.include?(File.basename(path)) && ALLOW.any? { |prefix, _, _| path.start_with?(prefix) }
      return AGPL
    end

    ext = File.extname(path)
    rule = ALLOW.find { |prefix, exts, _| path.start_with?(prefix) && exts.include?(ext) }
    rule&.last
  end

  # --- package-manifest licence ⟷ zone map [OPS.36, 2026-08-27] ---
  # A manifest's `license` field makes the SAME claim the per-file tags make, one level up —
  # and it is the level an automated licence scanner reads FIRST. Nothing paired the two:
  # `contracts/package.json` declared `AGPL-3.0-or-later` while all fourteen `contracts/*.sol`
  # and the `NOTICE` zone map said **MIT** (ratified DOC-T.47, with a reason — on-chain
  # composability / OpenZeppelin-consistency), and every gate stayed green because each side
  # was internally consistent. That is §Guard-craft #31 exactly: a registry validates each
  # RECORD and never asks whether two records AGREE. The cost here is not tidiness — a repo
  # is public, and a licence field is a legal statement about someone else's rights to use it.
  #
  # 🔒 CEILING, three parts:
  #  · only manifests that DECLARE a licence are judged. No `license` field = out of scope,
  #    NOT a violation — three `.csproj` and one `pyproject.toml` sit there deliberately.
  #  · the comparison is to the ZONE MAP (`ALLOW`), never to NOTICE's prose: the map is the
  #    machine-readable half, NOTICE is its narrative, and pairing prose would be a second home.
  #  · a manifest in a tree NO rule covers is REPORTED, never guessed — same stance as
  #    `unclassified`: the gate refuses to invent a licence for a tree nobody has decided.
  MANIFEST_LICENCE_RE = { "package.json" => /"license"\s*:\s*"([^"]+)"/ }.freeze

  def manifest_licences(root, paths = [])
    tracked_files(root, paths).filter_map do |rel|
      re = MANIFEST_LICENCE_RE[File.basename(rel)]
      next unless re

      declared = File.read(File.join(root, rel))[re, 1]
      next unless declared # no `license` field — out of scope by the declared ceiling

      expected = ALLOW.find { |prefix, _, _| rel.start_with?(prefix) }&.last
      next if expected == declared

      { path: rel, found: declared, licence: expected }
    end
  end

  # The comment prefix to use, or nil when the file has no usable comment syntax.
  def comment_prefix(path, first_line)
    # By name first: CMakeLists.txt's `.txt` must not fall through to the extension map.
    return "#" if NAMED_BUILD_FILES.include?(File.basename(path))

    ext = File.extname(path)
    return LINE_COMMENT[ext] if LINE_COMMENT.key?(ext)
    return "#" if ext.empty? && SHEBANG_HASH_LANG.match?(first_line.to_s)

    nil
  end

  # The complete line to insert, closing the comment for block-only languages.
  def tag_line(path, licence, prefix)
    "#{prefix} SPDX-License-Identifier: #{licence}#{BLOCK_CLOSE[File.extname(path)]}"
  end

  # Index at which the tag line is inserted. Three shapes, and each exists in this repo:
  #   · CubeMX C — INSIDE the USER CODE Header block, so a regen cannot silently drop it
  #   · YAML     — after a leading `---` / `%YAML` directive (the majority case here)
  #   · anything else — line 0, or line 1 when a shebang owns line 0
  def insertion_index(path, lines)
    # A BOM sits BEFORE the shebang / document-start bytes and would make every
    # start_with? test below answer "no" — inserting above a shebang that then stops being
    # line 1, and stranding the BOM mid-file. Strip it for the tests only.
    first = lines[0].to_s.delete_prefix("﻿")

    case File.extname(path)
    when ".c", ".h"
      # Bounded one short of SCAN_LINES so the resulting tag always lands inside the window
      # existing_tag scans — otherwise a second run would not see it and would insert again.
      i = lines.first(SCAN_LINES - 1).index { |l| l.include?("USER CODE BEGIN Header") }
      i ? i + 1 : 0
    when ".yml", ".yaml"
      first.start_with?("---", "%YAML") ? 1 : 0
    else
      first.start_with?("#!") ? 1 : 0
    end
  end

  def existing_tag(lines)
    lines.first(SCAN_LINES).each do |line|
      m = TAG_RE.match(line)
      return m[1] if m
    end
    nil
  end

  # Scans deeper than SCAN_LINES: a vendor notice often sits below an ASCII-art logo or a
  # local preamble (se-identity.h carries ours first and Semtech's at line ~15).
  def foreign_notice(lines)
    lines.first(NOTICE_SCAN_LINES)
         .find { |line| FOREIGN_NOTICE_RE.match?(line) && !OURS_RE.match?(line) }&.strip
  end

  # One planned action per in-scope file. Never writes.
  #   :insert        — needs the tag
  #   :ok            — already carries the expected tag
  #   :mismatch      — carries a DIFFERENT tag; reported, never rewritten
  #   :unsupported   — in scope by tree but no comment syntax / unreadable
  def plan(root: Dir.pwd, paths: [])
    tracked_files(root, paths).filter_map do |rel|
      licence = licence_for(rel)
      next if licence.nil?

      abs = File.join(root, rel)
      next unless File.file?(abs)

      body = File.binread(abs)
      next if body.empty?
      next if body.include?("\0") # binary that slipped the extension allow-list

      # `force_encoding` relabels without validating, so the first regex over an invalid
      # byte raises and takes the whole run down. `scrub` is applied to the SCANNING copy
      # only — apply! re-reads the file, so the bytes written back are never scrubbed.
      lines = body.force_encoding(Encoding::UTF_8).scrub.lines
      prefix = comment_prefix(rel, lines[0])
      next { path: rel, status: :unsupported, licence: } if prefix.nil?

      found  = existing_tag(lines)
      notice = found.nil? ? foreign_notice(lines) : nil
      status = if notice then :foreign_notice
      elsif found.nil? then :insert
      elsif found == licence then :ok
      else :mismatch
      end

      { path: rel, status:, licence:, found:, notice:, prefix:,
        index: insertion_index(rel, lines),
        eol: lines[0].end_with?("\r\n") ? "\r\n" : "\n" }
    end
  end

  # 🔴 The allow-list's blind spot, converted into a tripwire. `licence_for` answers nil
  # for a path no ALLOW prefix covers — so a source file dropped into a BRAND-NEW top-level
  # directory is not flagged, not counted, not mentioned: the gate is silent about a tree
  # it has never heard of. That is the honest boundary of "we watch new files" and it was
  # found by probing the gate rather than by reading it. Instead of documenting the hole,
  # this reports it: a file whose extension IS a language we know, that no rule admits and
  # no rule denies, means somebody added a tree nobody has licensed yet. Decide it, then
  # record the decision in ALLOW or DENY — the gate refuses to guess.
  def unclassified(root, paths = [])
    tracked_files(root, paths).select do |rel|
      next false if DENY.any? { |re| re.match?(rel) }
      next false unless LINE_COMMENT.key?(File.extname(rel)) || NAMED_BUILD_FILES.include?(File.basename(rel))

      licence_for(rel).nil?
    end
  end

  # Applies one :insert action; any other status is a no-op. Returns the resulting leading
  # lines, or nil when nothing was written. The status guard lives HERE and not only in the
  # caller: applied to an :ok record this doubles the tag, and to a :mismatch or
  # :foreign_notice record it writes our licence directly above somebody else's.
  def apply!(root, action)
    return nil unless action[:status] == :insert

    abs = File.join(root, action[:path])
    lines = File.readlines(abs)
    # Inserting after a final line that has no terminator would glue the two together —
    # silently destroying a shebang when the insertion point is the end of the file.
    prev = action[:index] - 1
    lines[prev] += action[:eol] if prev >= 0 && lines[prev] && !lines[prev].end_with?("\n")

    lines.insert(action[:index], tag_line(action[:path], action[:licence], action[:prefix]) + action[:eol])
    File.write(abs, lines.join)
    lines.first(4)
  end
end

if __FILE__ == $PROGRAM_NAME
  root    = File.expand_path("..", __dir__)
  write   = ARGV.delete("--write")
  check   = ARGV.delete("--check")
  verbose = ARGV.delete("--verbose")
  paths   = ARGV.reject { |a| a.start_with?("--") }

  actions   = SpdxHeaders.plan(root:, paths:)
  inserts   = actions.select { |a| a[:status] == :insert }
  mismatch  = actions.select { |a| a[:status] == :mismatch }
  foreign   = actions.select { |a| a[:status] == :foreign_notice }
  unsupported = actions.select { |a| a[:status] == :unsupported }
  ok        = actions.count { |a| a[:status] == :ok }

  unless mismatch.empty?
    warn "spdx_headers — #{mismatch.size} file(s) carry a DIFFERENT identifier than the scope map expects."
    warn "These are never rewritten automatically; resolve by hand or fix the map (00_01 §8):"
    mismatch.each { |a| warn "  ⚠ #{a[:path]} — found #{a[:found]}, map says #{a[:licence]}" }
    warn ""
  end

  unless foreign.empty?
    warn "spdx_headers — 🔴 #{foreign.size} in-scope file(s) carry a THIRD-PARTY copyright notice."
    warn "Never stamped automatically: writing our identifier above someone else's notice is a"
    warn "false licence claim. Resolve by hand (exclude, or a qualified dual notice):"
    foreign.each { |a| warn "  🔴 #{a[:path]} — #{a[:notice]}" }
    warn ""
  end

  unless unsupported.empty?
    warn "spdx_headers — #{unsupported.size} in-scope file(s) have no usable comment syntax (skipped):"
    unsupported.each { |a| warn "  · #{a[:path]}" }
    warn ""
  end

  if check
    # An empty scope is a configuration failure, not a pass: a typo'd path argument makes
    # `git ls-files` return nothing with exit 0, which would otherwise read as "all clean".
    abort "spdx_headers ✗ — no in-scope files found (wrong path argument?)" if actions.empty?

    stray = SpdxHeaders.unclassified(root, paths)
    unless stray.empty?
      warn "spdx_headers ✗ — #{stray.size} source file(s) in a tree no rule covers (neither ALLOW nor DENY):"
      stray.each { |p| warn "  ? #{p}" }
      warn "Decide the licence, then record it in ALLOW or DENY — the gate will not guess.\n\n"
    end

    manifests = SpdxHeaders.manifest_licences(root, paths)
    unless manifests.empty?
      warn "spdx_headers ✗ — #{manifests.size} package manifest(s) declare a licence the zone map contradicts."
      warn "A manifest field is what a licence SCANNER reads first, so this is the loudest of the two claims:"
      manifests.each do |m|
        warn "  ⚠ #{m[:path]} — declares #{m[:found]}, zone map says #{m[:licence] || 'nothing (tree not in ALLOW — decide it)'}"
      end
      warn ""
    end

    if inserts.empty?
      held = foreign.size + unsupported.size + mismatch.size + stray.size + manifests.size
      puts "spdx_headers #{held.zero? ? '✓' : '✗'} — #{ok} in-scope file(s) tagged, #{held} held back."
      # foreign / unsupported / mismatch are ALL failures here. Leaving them out of the exit
      # code was a live silent lie: the warnings go to stderr, which CI folds away, while the
      # verdict line and the exit code both read green over untagged files.
      exit held.zero? ? 0 : 1
    end
    warn "spdx_headers ✗ — #{inserts.size} in-scope file(s) missing an SPDX identifier (00_07 UNI.3):"
    inserts.first(40).each { |a| warn "  ✗ #{a[:path]}" }
    warn "  … and #{inserts.size - 40} more" if inserts.size > 40
    exit 1
  end

  by_tree = inserts.group_by { |a| a[:path][%r{\A[^/]+}] }

  if inserts.empty?
    puts "spdx_headers — nothing to do (#{ok} file(s) already tagged in this scope)."
  elsif write
    inserts.each do |a|
      head = SpdxHeaders.apply!(root, a)
      puts "  + #{a[:path]}"
      head&.each { |l| puts "      #{l.chomp}" } if verbose
    end
    puts "\nspdx_headers — WROTE #{inserts.size} header(s); #{ok} already tagged."
    by_tree.sort.each { |tree, list| puts "  #{tree}/ — #{list.size}" }
    puts "\nNow run the tree's gate (CLAUDE.md §3) before committing."
  else
    inserts.each do |a|
      puts "  [DRY-RUN] #{a[:path]}:#{a[:index] + 1} ← #{SpdxHeaders.tag_line(a[:path], a[:licence], a[:prefix])}"
    end
    puts "\nspdx_headers — DRY-RUN: would insert #{inserts.size} header(s); #{ok} already tagged."
    by_tree.sort.each { |tree, list| puts "  #{tree}/ — #{list.size}" }
    puts "\nRe-run with --write to apply. Nothing was modified."
  end
end
