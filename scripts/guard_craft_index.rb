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
# Usage:
#   ruby scripts/guard_craft_index.rb --check   # exit 1, якщо індекс розійшовся
#   ruby scripts/guard_craft_index.rb --write   # перегенерувати блок у SKILL.md

ROOT  = File.expand_path("..", __dir__)
SKILL = File.join(ROOT, ".claude/skills/ssot-maintenance/SKILL.md")
AUX   = File.join(ROOT, ".claude/skills/ssot-maintenance/guard-craft.md")

OPEN  = "<!-- GUARD-CRAFT-INDEX:AUTO — generated from guard-craft.md by " \
        "`ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->"
CLOSE = "<!-- /GUARD-CRAFT-INDEX -->"

# Curated constants — бамп кожної є ВИДИМОЮ правкою в git, як і решта порогів
# цього репо. ITEM_FLOOR тримає нумерацію append-only: зниклий номер валить
# гейт, бо на пункти вказують 65 цитат у 33 файлах, а `skill_item_check` ловить
# лише out-of-range, ніколи «номер існує й означає інше».
ITEM_FLOOR = 42
# Нижче цього рядок індексу не може бути носієм — він стає ярликом. Міряємо
# СЛОВАМИ, не байтами: корпус двомовний, а кирилиця коштує 2 B/символ, тож
# байтовий поріг мовчки вимагав би від українських рядків бути коротшими.
WORD_FLOOR = 8

abort "guard-craft.md missing — the index has no source" unless File.exist?(AUX)

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
    reflex = refs.first&.sub(/\A(Reflex|Рефлекс)[^:]{0,24}:?\s*/, "")&.sub(/[.]\z/, "")
    { num:, lead:, reflex:, nrefs: refs.size }
  end
end

def render(list)
  lines = list.map do |it|
    body = it[:reflex] ? "#{it[:lead]} — **#{it[:reflex]}**" : it[:lead]
    "#{it[:num]}. #{body}"
  end
  [ OPEN, "", *lines, "", CLOSE ].join("\n")
end

list = items(File.read(AUX))
block = render(list)

# ── guards ──────────────────────────────────────────────────────────────────
errs = []
errs << "item count #{list.size} < floor #{ITEM_FLOOR} — a vanished number orphans its citations" if list.size < ITEM_FLOOR
dupes = list.map { _1[:num] }.tally.select { |_, v| v > 1 }
errs << "duplicate item numbers: #{dupes.keys.join(', ')}" if dupes.any?
list.each do |it|
  next if it[:lead].to_s.split.size + it[:reflex].to_s.split.size >= WORD_FLOOR
  errs << "item #{it[:num]} renders as a LABEL, not a carrier: «#{it[:lead]}» " \
          "(< #{WORD_FLOOR} words) — widen the bolded lead in guard-craft.md, not here"
end

# ⚠️ ПІДЛОГА ЛОВИТЬ КОРОТКІСТЬ, НЕ АБСТРАКТНІСТЬ, і це названо, а не сховано:
# пункт може мати 20 слів чистої логіки й однаково не спинити нікого (#22, #24
# — кандидати саме такі). Механічної перевірки на «чи цей рядок стріляє» не
# існує; підлога необхідна, але не достатня, і другий контур тут — читання.
multi = list.select { it[:nrefs].to_i > 1 }
unless multi.empty?
  warn "  ℹ️ multi-Reflex items (index carries the FIRST — the one paired with the lead): " +
       multi.map { "##{_1[:num]}×#{_1[:nrefs]}" }.join(" ")
  warn "     Verify by reading whenever a NEW reflex is added to one of these: if a later"
  warn "     one ever SUPERSEDES the first rather than adding a sub-shape, the index would"
  warn "     keep carrying the withdrawn advice — measured today as not the case for any."
end

if ARGV.include?("--write")
  abort "refusing to write:\n  #{errs.join("\n  ")}" if errs.any?
  src = File.read(SKILL)
  i = src.index(OPEN)
  j = src.index(CLOSE)
  abort "markers not found in SKILL.md — place #{OPEN} … #{CLOSE} first" unless i && j
  File.write(SKILL, src[0...i] + block + src[(j + CLOSE.length)..])
  puts "wrote #{list.size} index lines (#{block.bytesize} B) into SKILL.md"
  exit 0
end

# --check (default)
unless errs.empty?
  warn "guard_craft_index ✗ — #{errs.size} problem(s):"
  errs.each { |e| warn "  · #{e}" }
  exit 1
end

src = File.read(SKILL)
i = src.index(OPEN)
j = src.index(CLOSE)
unless i && j
  warn "guard_craft_index ✗ — SKILL.md carries no index block (markers absent)"
  exit 1
end
current = src[i..(j + CLOSE.length - 1)]
if current == block
  puts "guard_craft_index ✓ — index matches guard-craft.md (#{list.size} items, floor #{ITEM_FLOOR})"
  exit 0
end
warn "guard_craft_index ✗ — SKILL.md index has DRIFTED from guard-craft.md"
warn "  Regenerate: ruby scripts/guard_craft_index.rb --write"
warn "  (if you edited the index by hand, move the edit into guard-craft.md — it is the source)"
exit 1
