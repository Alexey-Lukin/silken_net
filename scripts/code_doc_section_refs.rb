#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# [SSOT anti-drift] code→doc §-ref RESOLUTION audit — HARD CI gate (docs.yml) since 2026-07-25.
#
# Code comments reference canon sections by `NN_NN §X` (e.g. "05_05 §3" in a service
# comment). The doc gates (`docs:check_refs`) scan only `docs/**` — they NEVER look at
# code comments. So when a canon section is renumbered or collapsed, code-comment §-refs
# rot SILENTLY. Real case (2026-06-16 deep-audit): slashing policy moved 00_01 §6 → 05_05
# (2026-05-30); the docs were swept, but ~18 `00_01 §6.x` refs in app/ + spec/ comments
# sat stale for weeks — invisible to every gate (the external-doc-path linter only flags
# `docs/NN_NN_Name` PATHS, not bare `§`-refs in comments).
#
# This script reuses the proven boundary/parent-aware resolver
# (`Tracker::Dashboard.file_section_dangling_refs`) over the source trees and reports any
# `NN_NN §X` that no longer resolves to a real heading in its target doc.
#
# 🟢 PROMOTED to a HARD gate 2026-07-25 [DOC-T.48], on the condition this header itself
# set: "promote only if the false-positive rate proves to be zero across the codebase" —
# 0 violations across the full 926-file scan, sustained. The FP class the report-only era
# feared ("informal / historical / illustrative refs") is largely structurally dead: the
# resolver (`DOC_SECTION_REF`) matches a `§` only when it carries a `NN_NN` doc-id AND the
# token is a SECTION LABEL (digit-led, or one letter + `.` + digit), so illustrative
# `§X` / `§NN` / `§SomeName` placeholders never match, and a `.x` tail is skipped as a
# wildcard. What CAN still false-positive is a deliberately HISTORICAL ref ("this used to
# live in `00_01 §6`") — if one ever legitimately needs to stay, add it to EXEMPT with a
# reason, do NOT weaken the resolver.
#
# ⚠️ [DOC-T.60, 2026-08-04] The digit-led half of that ceiling is GONE, because its reach
# ran far past its intent. Taken to skip illustrative `§`, it silently exempted every doc
# whose sections are letter-led — and 04_06 is entirely `§A.x`/`§B.x`, so the whole testing
# canon went unchecked here and in `.claude/**`; a wrong `04_06 §A.10а` lived in a skill
# long enough for an agent to quote it back as canonical. Mutation-proved both ways: the
# old regex captured NOTHING on a planted `04_06 §A.999` (EXIT 0), the new one flags it.
# The replacement discriminator is the LABEL SHAPE, not the `NN_NN` prefix — the prefix was
# always required and does NOT separate the genres, since prose-shorthand named refs
# (`05_02 §Модель`, `05_04 §Merkle`), placeholders (`03_04 §X.Y`, `00_07 §NN`) and
# non-section IDs (`07_01 §B-02`, `03_05 §FW.2`) all carry one. Those 74 refs stay on the
# weaker `section_label_drift` ADVISORY by design (00_06 §3). Measured before the flip
# across all four corpora sharing this resolver: 46 refs newly in scope, 3 dead.
#
# ⚠️ Live ceiling: 04_06 addresses its 30 best practices as `§A.16` too (BP number, not a
# section) — the same token space as its `§A.1`..`§A.10` sections. Cross-doc, only the
# SECTION reading resolves; cite the section and name the BP in prose (`04_06 §A.4`, BP
# 16–17). 04_06's own same-doc `§A.16` carries no `NN_NN`, so it is out of scope here.
#
# Pure Ruby, no Rails. Run from repo root: `ruby scripts/code_doc_section_refs.rb`.
require_relative "../lib/tracker/dashboard"

ROOT  = File.expand_path("..", __dir__)
TREES = %w[app spec lib].freeze
# .claude/** (skills + prompts) is the ROUTING layer — it references canon by `NN_NN §X`
# too, and a canon renumber rots those refs just as silently (DOC-T.44 TREES-extension).
# Scanned as *.md alongside the Ruby trees; report-only all the same.
CLAUDE_TREE = ".claude"

# The §-resolution engine + its unit tests legitimately cite stale-LOOKING example refs
# (fixtures that exercise the resolver) — exempt them, same idea as protocols_ref_check
# skipping the subtree's own filename-link convention. The ssot-maintenance SKILL is exempt
# for the same reason: its "worked example" cites `05_03 §749` / `07_01 §6.5` as deliberate
# renumber-drift teaching cases (a doc renumber MOVED those sections — that IS the lesson).
# `lib/tasks/docs.rake` joins them for the same reason once `.rake` came into
# scope: it is the gate's own rake body, and it cites `05_03 §749` twice while
# EXPLAINING the blind spot that let a line-number-as-§ rot. Citing the drift is
# the documentation; flagging it would make the gate red at its own author.
# 🔴 БЛАНКЕТ ЗНЯТО З ДВОХ ФАЙЛІВ І ЗАМІНЕНО НА ПЕР-РЕФНИЙ (2026-08-08).
# Шлях-виняток вимикає гейт для ВСЬОГО файлу, хоча підстава стосується трьох-
# пʼятьох рядків. Ціна була невидима, поки §Guard-craft не поїхала в допоміжний
# файл: тоді виявилось, що бланкет тримав неперевіреними ~104 kB живих канон-
# рефів (`04_04 §8.1`, `00_06 §3`, `01_02 §2.4`, `06_07 §2`…) заради двох
# навчальних цитат. Виміряно перед зміною: зняття бланкета підняло рівно ПʼЯТЬ
# відомих навчальних реф-ів і ЖОДНОГО невідомого — тобто решта секції вже була
# коректна й тепер уперше стереже́ться. Це рівно тест, який приписує пункт #7
# цього ж скіла: «для кожного винятку спитай, що зламається, якщо цей рядок
# видалити» — відповідь була «нічого, крім двох речень».
EXEMPT = %r{\A(?:lib/docs_linter\.rb|lib/docs_graph\.rb|lib/tracker/dashboard\.rb|spec/lib/)}

# Пер-рефні винятки: файл СКАНУЄТЬСЯ, але ці конкретні реф-и — навмисні
# цитати дрейфу, і саме цитата є документацією («доc-renumber ПЕРЕСУНУВ ці
# секції — це і є урок»; `§A.999` узагалі підсаджений як доказ мутації).
# Прапорець на них червонив би гейт на його ж авторові.
EXEMPT_REFS = {
  # `08_01 §2` — той самий жанр, лише на осі ІСНУВАННЯ доку: форма #29 цитує його як
  # доказ, що redirect-стаб небезпечний («реф не резолвиться проти тонкого стаба»).
  # Побачив його аж фліп fail-OPEN→fail-CLOSED [DOC-T.68 фаза 0]: доти реф на мертвий
  # doc-id резолвер мовчки пропускав, тож цитата була невидима, а не дозволена.
  # ⊕ `05_03 §749` / `07_01 §6.5` joined this row 2026-08-22: they moved here with
  # the worked example that cites them (that prose left the auto-loaded half).
  # An exemption follows its SUBJECT — it does not stay where the subject used to
  # be, or it stops guarding and starts blessing the next phantom at that address.
  ".claude/skills/ssot-maintenance/guard-craft.md" => [ "04_06 §A.10а", "04_06 §A.999", "07_03 §7", "08_01 §2", "05_03 §749", "07_01 §6.5" ],
  "lib/tasks/docs.rake"                            => [ "05_03 §749" ],
  # Trap (14) цитує компаунд-реф БЕЗ пробілу як приклад того, що детектор
  # хибно емітував із нього ще й голий числовий якір. Цитата і є доказом:
  # перенаведення адреси знищило б приклад, а не полагодило б його. Док
  # розчинено [DOC-T.68 фаза 1], тож реф мертвий назавжди — і саме тому
  # придатний як фікстура.
  # ⊕ Moved SKILL.md → traps.md 2026-08-22 with trap (14), which cites it. Second time
  # in two days a section split orphaned an exemption, so the rule is now stated where it
  # is executed: AN EXEMPTION FOLLOWS ITS SUBJECT. The stale-exempt lantern below caught
  # both — and its advice ("delete it") was wrong both times, which is why it now names
  # the second cause too.
  ".claude/skills/memory-maintenance/traps.md"     => [ "00_05 §2.7" ]
}.freeze

# `.rake` was the remaining half of this gate's declared ceiling [DOC-T.60]: the
# scan took `*.rb` only, while five rake files carry canon `NN_NN §X` refs — and
# rake bodies are exactly where doc-gate prose lives, so a canon renumber rots
# them as silently as any comment. Measured on the flip: 1 dead ref, and it was
# the teaching citation now exempted above.
# 🔴 ПЕРИМЕТР РОЗШИРЕНО НА `firmware/` + `tools/` (2026-08-22), і підстава — переміряна
# СТЕЛЯ, а не нова ідея. Виключення цих дерев стояло на вартості: «vendored trees are
# 96% of the glob — scanning them took the gate from 4s to 34s». Це правда про ПОВНИЙ
# глоб, і хибно про звужений: `/extern/` дає 2385 файлів із 2595, тож після його зняття
# додаток коштує 210 файлів і +23% часу. Улов на день зняття — ЧОТИРИ мертві реф-и в
# 318 живих (`05_02 §554` = номер РЯДКА як §; `07_03 §1.1B` = вигаданий суфікс;
# `02_02 §1.4` і `03_03 §1.4` = неіснуючі секції), жоден із яких не бачив ЖОДЕН гейт.
# ⛔ `scripts/` СВІДОМО лишається поза периметром і це не недогляд: там 44 реф-и, з
# них не резолвляться сім — і всі сім у ЦЬОМУ файлі, це його ж декларовані фікстури
# мертвих адрес. Скан себе почервонив би на власній таблиці винятків.
files = (TREES.flat_map { |t| Dir[File.join(ROOT, t, "**", "*.{rb,rake}")] } +
         Dir[File.join(ROOT, "firmware", "**", "*.{c,h}")].reject { |f| f.include?("/extern/") } +
         Dir[File.join(ROOT, "tools", "**", "*.py")] +
         Dir[File.join(ROOT, CLAUDE_TREE, "**", "*.md")])
        .map { |f| f.sub("#{ROOT}/", "") }
        .reject { |rel| rel =~ EXEMPT }
        .sort

violations = files.flat_map do |rel|
  allowed = EXEMPT_REFS.fetch(rel, [])
  Tracker::Dashboard.file_section_dangling_refs(File.read(File.join(ROOT, rel)))
                    .reject { |h| allowed.any? { |r| h.include?(r) } }
                    .map { |h| "#{rel}: #{h}" }
end

# Ліхтар на самі винятки: пер-рефний виняток «на всяк випадок» — це бланкет у
# костюмі точності. Якщо реф перестав бути мертвим (секцію повернули), виняток
# мовчки прикриває вже НІЩО, і наступний, хто його читає, вірить, що там досі
# є що прикривати. Той самий тест, що приписує пункт #7: спитай, що зламається,
# якщо цей рядок видалити.
stale_exempts = EXEMPT_REFS.flat_map do |rel, refs|
  next [] unless File.exist?(File.join(ROOT, rel))
  live = Tracker::Dashboard.file_section_dangling_refs(File.read(File.join(ROOT, rel)))
  refs.reject { |r| live.any? { |h| h.include?(r) } }.map { |r| "#{rel}: `#{r}`" }
end
unless stale_exempts.empty?
  warn "code_doc_section_refs ✗ — #{stale_exempts.size} EXEMPT_REFS entr(y/ies) guard nothing:"
  # 🔴 TWO causes, and only one of them licenses deletion. Either the ref came back to
  # life (delete), or its SUBJECT moved to another file and the exemption stayed behind
  # (re-point it — deleting would un-guard a live citation). Naming one cause made this
  # gate prescribe the destructive fix twice in two days, both times while correctly
  # detecting that the entry had stopped guarding anything.
  stale_exempts.each { |s| warn "  · #{s} — either the ref resolves now (delete), or its subject MOVED (re-point); CHECK which" }
  exit 1
end

if violations.empty?
  puts "code_doc_section_refs — #{files.size} source + .claude routing files scanned; every `NN_NN §X` ref resolves ✓"
else
  puts "code_doc_section_refs — #{violations.size} stale code→doc §-refs:"
  violations.uniq.sort.each { |v| puts "  ✗ #{v}" }
  abort("code_doc_section_refs FAILED — a canon §-ref in code/routing no longer resolves")
end
