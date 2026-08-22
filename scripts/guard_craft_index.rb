#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/guard_craft_index.rb — індекс §Guard-craft ГЕНЕРУЄТЬСЯ, не пишеться.
#
# ЧОМУ. `ssot-maintenance/SKILL.md` авто-інвокується майже щосесії, і більша
# його частина — пункти «як гейт не бачить власної поверхні». Вони потрібні при
# роботі з гейтом, а вантажаться завжди. Тіло переїхало в `guard-craft.md`
# (читається на вимогу); тут лишається ОДИН рядок на пункт — і цей рядок є
# НОСІЄМ: він мусить спинити читача в момент, коли той збирається порушити.
#
# 🔴 ЧОМУ ГЕНЕРАЦІЯ, А НЕ РУКА. Рукописний індекс — це другий дім тих самих
# цих правил, тобто ще один дзеркальний шар у корпусі, який уже виміряв, чим це
# коштує. Клас документує сам файл, пункт #31: «validates each RECORD and never
# asks whether two records AGREE». Генератор робить розбіжність структурно
# неможливою, а `--check` ставить на це гейт.
#
# ФОРМА РЯДКА — `лід — Reflex`, і це не оздоба. Ліди РАННЬОЇ когорти писались
# як ЯРЛИКИ, не як імперативи (#1 = «Decorative» — найцитованіший пункт
# корпусу; #3 = «A noisy advisory»), тож самого ліда для них не досить.
# `Reflex:`-клаузу несуть не всі пункти. ⚠️ Тут стояла пара «N із M», і обидві
# її редакції протухли РІЗНО, що й робить цей рядок повчальним: перша хибила
# НЕОГОЛОШЕНОЮ ОДИНИЦЕЮ (`grep -c` рахував жирні СПАНИ, а число доповідалось як
# ПУНКТИ — пункт із кількома рефлексами, як #28 із шістьма, роздуває лічильник),
# друга була одиницею чесна й просто відстала від росту корпусу. Тобто число тут
# гниє двома незалежними способами, стоячи в тулі, збудованому лікувати рівно цей
# клас, — тож знято: множину дає прогін. Решта мусять мати лід, що стріляє сам —
# і за цим стежить WORD_FLOOR: терсий рядок валить гейт, а полагодити його
# можна ЛИШЕ в `guard-craft.md`, тобто тиск іде в джерело, не в дзеркало.
#
# ── КОЛИ РОЗКОЛЮВАТИ, І ЩО ЦЕ КУПУЄ (виміряно на пʼятьох, 2026-08-22) ────────
# Критерій — НЕ розмір: секція мусить (1) займати понад половину файлу і
# (2) стріляти в ПІД-РЕЖИМІ, а не щосесії. Файл на 30 kB без домінантної
# секції розколу не потребує; файл на 18 kB, де 87% — одна гоча-стрічка,
# потребує. «Не потрібен» — валідний і частий вердикт.
#
# ЦІНА Й ВИГОДА. Індекс коштує 5–13% від тіла, яке заміняє — стиснення ≈10:1.
# Пʼять розколів зняли авто-шар із 1 039 663 B до 364 982 B (−65%), нуль втрати.
# Індекс усе одно РОСТЕ з кожним пунктом: механізм обмежує ТЕМП, не розмір.
#
# ОБОВʼЯЗКИ, кожен куплений кровʼю на одному з пʼяти:
#  1. Нуль-втрата ДОВОДИТЬСЯ: тіла порівняти дослівно проти `git show HEAD:`,
#     не проти поточного дерева — власна правка контамінує прилад.
#  2. Мутація: прибери пункт → `floor` мусить почервоніти; постав назад → зелено.
#     Випадок, що проходить в обидва боки, не тестує нічого.
#  3. Ліди. Рання когорта майже завжди писалась ЯРЛИКАМИ («Dynamic Tax»),
#     а індексний рядок є НОСІЄМ — тобто розширення лідів і Є робота, не
#     перенесення. Міра: web3 дав 14 ярликів із 23, backend 13 із 80.
#     Розширюй у ДЖЕРЕЛІ, звіряючи з тілом; ніколи в дзеркалі.
#  4. Порядок. Двічі з пʼяти пункти стояли фізично не за номером (17 між 14 і
#     15; 22 перед 21). Сортуй, але НЕ перенумеровуй — номер це адреса.
#  5. Свіп по тому, ХТО ОПИСУЄ ФОРМУ, а не хто на файл шле. Форму описують
#     чотири різні речі, і кожна гниє окремо: `description` у frontmatter
#     (його читає РОУТЕР — саме він мовчав тричі), `reference_*`-стаб у
#     памʼяті, що перелічує поверхні, плейбук, що цитує секцію по імені, і
#     пер-рефні винятки гейтів (`scripts/code_doc_section_refs.rb`) — виняток
#     мусить іти за своїм ПРЕДМЕТОМ, інакше благословляє наступний фантом.
#  6. Шапка companion оголошує ТРИГЕР («відкрий це, коли …») і, якщо є,
#     внутрішнє літерування (`13a` не є пунктом переліку).
#  7. ⛔ Гроші окремо: перш ніж різати money-скіл, доведи, що інваріанти,
#     потрібні БЕЗ відкривання чогось, стоять у `CLAUDE.md` — і ніколи не
#     фінансуй розкол пониженням одного з них униз.
#
# ⛔ ЧОГО РУШІЙ НЕ ВІЗЬМЕ, і це не баг: файл із ДВОМА незалежними
# послідовностями `1..N`. Розділювач ключує пункт номером, тож дві шкали
# в одному aux дають `duplicate item numbers`, і `--write` відмовляє.
# Виміряно на `04_06` 2026-08-22: Частина A йде 1..31, §B.2 веде власну
# 1..27 → 27 колізій. Обійти можна ЛИШЕ двома рядками TARGETS (по одному
# на шкалу) — перенумерація заборонена обовʼязком (4): номер це адреса,
# і на BP того доку стоїть 81 зовнішня цитата.
#
# Usage:
#   ruby scripts/guard_craft_index.rb --check   # exit 1, якщо індекс розійшовся
#   ruby scripts/guard_craft_index.rb --write   # перегенерувати блок у SKILL.md

ROOT = File.expand_path("..", __dir__)

# 🔴 ONE engine, a TABLE of targets — not a copy per skill. The repo's own
# doctrine argues it (#13 «Closed for one caller is not closed for the CLASS»),
# and a second copy would be exactly the second-home defect this generator
# exists to make impossible. Adding a split = adding a row here.
#   floor: the item count on split day. It is a bulk-loss backstop, never a
#   per-number pin — see the ITEM_FLOOR note below.
TARGETS = [
  { name:  "ssot-maintenance",
    skill: File.join(ROOT, ".claude/skills/ssot-maintenance/SKILL.md"),
    aux:   File.join(ROOT, ".claude/skills/ssot-maintenance/guard-craft.md"),
    floor: 42,
    open:  "<!-- GUARD-CRAFT-INDEX:AUTO — generated from guard-craft.md by " \
           "`ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->",
    close: "<!-- /GUARD-CRAFT-INDEX -->" },
  # Split 2026-08-22 (the second application of this engine). 80 items, 96% of
  # the pre-split file, loaded on EVERY backend session; 26 of the numbers carry
  # inbound citations from 13 files, `CLAUDE.md` among them — hence append-only.
  { name:  "backend",
    skill: File.join(ROOT, ".claude/skills/backend/SKILL.md"),
    aux:   File.join(ROOT, ".claude/skills/backend/gotchas.md"),
    floor: 80,
    open:  "<!-- BACKEND-GOTCHAS-INDEX:AUTO — generated from gotchas.md by " \
           "`ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->",
    close: "<!-- /BACKEND-GOTCHAS-INDEX -->" },
  # Third target, same day. 47 items but the heaviest file in the practice
  # (237 kB pre-split, 96% of it this one section). ⚠️ Unlike backend it carries
  # TWELVE unnumbered load-bearing paragraphs: the splitter appends each to the
  # PRECEDING item's chunk, so their bold spans join that item's lead/reflex
  # pool — every generated line for an item followed by one was eyeballed.
  { name:  "frontend",
    skill: File.join(ROOT, ".claude/skills/frontend/SKILL.md"),
    aux:   File.join(ROOT, ".claude/skills/frontend/gotchas.md"),
    floor: 47,
    open:  "<!-- FRONTEND-GOTCHAS-INDEX:AUTO — generated from gotchas.md by " \
           "`ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->",
    close: "<!-- /FRONTEND-GOTCHAS-INDEX -->" },
  # Fourth target, and the one that indicts the engine's own author: this skill is the
  # CURATOR of the memory corpus, and it declared «Keep this skill a thin pointer» on its
  # last line while 62% of its 65 kB was this one section — auto-invoked on every memory
  # session. Kurtz-form: both halves flawless, the contradiction only in their relation, so
  # no check of a single claim can see it. 17 items, cited as «пастка (N)» — a form carrying
  # no `#`, hence invisible to `skill_item_check`: here the floor is the ONLY guard.
  { name:  "memory-maintenance",
    skill: File.join(ROOT, ".claude/skills/memory-maintenance/SKILL.md"),
    aux:   File.join(ROOT, ".claude/skills/memory-maintenance/traps.md"),
    floor: 17,
    open:  "<!-- MEMORY-TRAPS-INDEX:AUTO — generated from traps.md by " \
           "`ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->",
    close: "<!-- /MEMORY-TRAPS-INDEX -->" },
  # Fifth target. 44 163 B of gotchas = 88% of a 50 kB skill, loaded on every web3
  # session. The MONEY path, so this split carries one obligation the others did not:
  # the invariants a reader must have WITHOUT opening anything (unit/direction,
  # minting guard-clauses, SLASH-1 positive-A) live inline in CLAUDE.md §5-§6 and were
  # verified there BEFORE the move — never fund a split by demoting one of those.
  # 14 of 23 leads were LABELS, a far higher share than the earlier splits: the early
  # cohort here was written as captions, so widening WAS the work, not the moving.
  { name:  "web3-pipeline",
    skill: File.join(ROOT, ".claude/skills/web3-pipeline/SKILL.md"),
    aux:   File.join(ROOT, ".claude/skills/web3-pipeline/gotchas.md"),
    floor: 23,
    open:  "<!-- WEB3-GOTCHAS-INDEX:AUTO — generated from gotchas.md by " \
           "`ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->",
    close: "<!-- /WEB3-GOTCHAS-INDEX -->" }
].freeze

# Curated constants — бамп кожної є ВИДИМОЮ правкою в git, як і решта порогів
# цього репо. ITEM_FLOOR тримає нумерацію append-only: зниклий номер валить
# гейт, бо на пункти вказують 65 цитат у 33 файлах, а `skill_item_check` ловить
# лише out-of-range, ніколи «номер існує й означає інше».
# (ITEM_FLOOR тепер живе в TARGETS[:floor] — по одному на скіл.)
# Нижче цього рядок індексу не може бути носієм — він стає ярликом. Міряємо
# СЛОВАМИ, не байтами: корпус двомовний, а кирилиця коштує 2 B/символ, тож
# байтовий поріг мовчки вимагав би від українських рядків бути коротшими.
WORD_FLOOR = 8


def items(text)
  # Пункт = від маркера номера до наступного маркера номера (або кінця).
  text.split(/^(?=\d+[a-z]?[.)] )/).filter_map do |chunk|
    num = chunk[/\A(\d+[a-z]?)[.)] /, 1] or next nil
    # 🔴 Mask `**` INSIDE inline code spans before pairing (found 2026-08-22 while
    # reverse-engineering this file for a second split). A glob like `.claude/**`
    # is legal prose here, and its literal `**` was pairing as a bold delimiter —
    # shifting every subsequent pair in the chunk. Live cost, with --check GREEN:
    # item #1's true first reflex was invisible and its index line rendered as the
    # stump «— **, sharpened: …**». Masking (not stripping) keeps lead text intact.
    scan_src = chunk.gsub(/`[^`\n]*`/) { |m| m.gsub("**", "\u0000") }
    bolds = scan_src.scan(/\*\*(.+?)\*\*/m).flatten
                    .map { |s| s.gsub("\u0000", "**").gsub(/\s+/, " ").strip }
    lead = bolds.first.to_s.sub(/[.,;:]\z/, "")
    # 🔴 ПЕРШИЙ рефлекс — і це ВИМІРЯНО, а не вибрано за замовчуванням.
    # Проміжна редакція брала `.last`, боячись, що перший може бути ВІДКЛИКАНИЙ
    # (#36 справді прописує grep на заборонену форму й наприкінці сам себе
    # розвертає: та сама форма коректна на `status`-скані, тож такий гейт зламав
    # би money-recovery). Захист від НЕВИМІРЯНОЇ небезпеки поламав чотири
    # пункти: у цьому файлі пізніші рефлекси — не аменди, а ПІД-ФОРМИ іншого
    # раунду, тож #5/#23/#28/#29 діставали пару про щось інше, тобто індекс
    # виготовляв би «borrowed evidence» (#26) механічно, на етапі збірки.
    # Прямий вимір усіх пʼятьох мульти-рефлексних пунктів: `.first` збігається
    # з лідом у всіх, а #36 має рефлекс ОДИН — його відкликана порада живе в
    # прозі `(a)`, не в жирному `Reflex:`, тож селектор її не бачить у принципі.
    refs = bolds.select { |b| b =~ /\A(Reflex|Рефлекс)\b/ }
    # `Reflex, sharpened:` / `Рефлекс (звужено):` are live forms — a bare `:?` strip
    # left the connective behind, so the index carried «, sharpened: …» as its lead-in.
    # 🔴 The colon is MANDATORY, and that is a regression fixed the same day it
    # shipped. With `:?` optional the strip ate a fixed 24 chars whenever the
    # connective ran long — mid-word — and `frontend #1`, the most-cited item of
    # that skill, rendered as the stump «— **URABLE bucket in any of our…**».
    # Requiring the colon means a long form is left INTACT rather than truncated:
    # a lead-in that reads oddly is cheap, a mangled sentence is not.
    reflex = refs.first&.sub(/\A(Reflex|Рефлекс)\b[^:]{0,24}:\s*/, "")&.sub(/[.]\z/, "")
    { num:, lead:, reflex:, nrefs: refs.size }
  end
end

def render(list, t)
  lines = list.map do |it|
    body = it[:reflex] ? "#{it[:lead]} — **#{it[:reflex]}**" : it[:lead]
    "#{it[:num]}. #{body}"
  end
  [ t[:open], "", *lines, "", t[:close] ].join("\n")
end

ok = true
TARGETS.each do |t|
  unless File.exist?(t[:aux])
    warn "guard_craft_index ✗ — #{t[:name]}: aux file missing (#{t[:aux]}) — the index has no source"
    ok = false; next
  end
  list  = items(File.read(t[:aux]))
  block = render(list, t)

  # ── guards ────────────────────────────────────────────────────────────────
  errs = []
  errs << "item count #{list.size} < floor #{t[:floor]} — a vanished number orphans its citations" if list.size < t[:floor]
  dupes = list.map { _1[:num] }.tally.select { |_, v| v > 1 }
  errs << "duplicate item numbers: #{dupes.keys.join(', ')}" if dupes.any?
  list.each do |it|
    next if it[:lead].to_s.split.size + it[:reflex].to_s.split.size >= WORD_FLOOR
    errs << "item #{it[:num]} renders as a LABEL, not a carrier: «#{it[:lead]}» " \
            "(< #{WORD_FLOOR} words) — widen the bolded lead in #{File.basename(t[:aux])}, not here"
  end

  # ⚠️ ПІДЛОГА ЛОВИТЬ КОРОТКІСТЬ, НЕ АБСТРАКТНІСТЬ, і це названо, а не сховано:
  # пункт може мати 20 слів чистої логіки й однаково не спинити нікого (#22, #24
  # — кандидати саме такі). Механічної перевірки на «чи цей рядок стріляє» не
  # існує; підлога необхідна, але не достатня, і другий контур тут — читання.
  multi = list.select { it[:nrefs].to_i > 1 }
  unless multi.empty?
    warn "  ℹ️ #{t[:name]}: multi-Reflex items (index carries the FIRST — the one paired with the lead): " +
         multi.map { "##{_1[:num]}×#{_1[:nrefs]}" }.join(" ")
    warn "     Verify by reading whenever a NEW reflex is added to one of these: if a later"
    warn "     one ever SUPERSEDES the first rather than adding a sub-shape, the index would"
    warn "     keep carrying the withdrawn advice — measured today as not the case for any."
  end

  src = File.read(t[:skill])
  i = src.index(t[:open])
  j = src.index(t[:close])

  if ARGV.include?("--write")
    if errs.any?
      warn "guard_craft_index ✗ — refusing to write #{t[:name]}:\n  #{errs.join("\n  ")}"
      ok = false; next
    end
    unless i && j
      warn "guard_craft_index ✗ — #{t[:name]}: markers not found in #{File.basename(t[:skill])} — place them first"
      ok = false; next
    end
    File.write(t[:skill], src[0...i] + block + src[(j + t[:close].length)..])
    puts "wrote #{list.size} index lines (#{block.bytesize} B) into #{t[:name]}/#{File.basename(t[:skill])}"
    next
  end

  # --check (default)
  if errs.any?
    warn "guard_craft_index ✗ — #{t[:name]}: #{errs.size} problem(s):"
    errs.each { |e| warn "  · #{e}" }
    ok = false; next
  end
  unless i && j
    warn "guard_craft_index ✗ — #{t[:name]}: #{File.basename(t[:skill])} carries no index block (markers absent)"
    ok = false; next
  end
  if src[i..(j + t[:close].length - 1)] == block
    puts "guard_craft_index ✓ — #{t[:name]}: index matches #{File.basename(t[:aux])} (#{list.size} items, floor #{t[:floor]})"
  else
    warn "guard_craft_index ✗ — #{t[:name]}: index has DRIFTED from #{File.basename(t[:aux])}"
    warn "  Regenerate: ruby scripts/guard_craft_index.rb --write"
    warn "  (if you edited the index by hand, move the edit into #{File.basename(t[:aux])} — it is the source)"
    ok = false
  end
end
exit(ok ? 0 : 1)
