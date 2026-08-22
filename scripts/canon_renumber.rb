#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/canon_renumber.rb — інструмент кроку 3 методу `.claude/prompts/module_restructure.md`
# («Cross-ref sweep, anchored»): масовий re-point канон-рефів при перенумерації сторінок.
#
# ЧОМУ ФАЙЛ, А НЕ `-e`/`sed`. Метод вимагає саме скрипт-файл, і вимога не про
# естетику: одноразовий `sed` не має ні presence-check, ні zero-loss referrer-diff,
# ні dry-run — а без них перенумерація доводиться ОКОМ, тобто не доводиться. Три з
# чотирьох класів помилок нижче (колізія ланцюжкової заміни, digit-boundary,
# вкорочення `../../`) на командному рядку не видно взагалі, поки не стане пізно.
#
# ЩО РОБИТЬ:
#   1. Presence-check ЦІЛЬОВИХ номерів — відмовляється працювати, якщо номер, у який
#      їде сторінка, уже має живі цитати (клас «тихого захоплення»: стара згадка
#      розчиненого `00_02` після переїзду починає резолвитись у ЗОВСІМ інший предмет,
#      і кожен гейт при цьому зеленіє).
#   2. Інвентар рефів ДО (файл × форма × токен × номер) — пʼять форм, кожна окремо.
#   3. ОДНОПРОХІДНА ОДНОЧАСНА заміна (одна alternation, ordered specific→generic).
#      Послідовна заміна пара-за-парою дає колізію, коли цільовий номер однієї пари
#      є вихідним іншої (`A→B`, `B→C` ⇒ `A→C`); альтернація цього не вміє за побудовою.
#   4. Перевірка збереження `../`-ГЛИБИНИ (пастка нижче) — окремим виміром, не вірою.
#   5. Zero-loss referrer-diff: кожен зниклий старий реф мусить мати рівно один
#      новий-відповідник у ТІЙ САМІЙ (файл, форма). Друкує таблицю.
#   6. Свіп 3а: самопосилання + зустрічна форма (нова мітка ⊥ старий href) + залишки.
#   7. `git mv` самих файлів — історія зберігається (прецедент d5895ed0).
#
# 🔴 ПАСТКА, ЯКУ ЦЕЙ СКРИПТ ТРИМАЄ ЗА КОНСТРУКЦІЄЮ. Повторювана група `(\.\./)*` у
# Ruby захоплює лише ОСТАННЄ повторення, тож заміна, що тягне її через `$N`, тихо
# вкорочує `../../` до `../`. Тут вона не може статися: заміна МАТЧИТЬ ЛИШЕ САМ
# ТОКЕН імені файлу і ніколи не бере `../` у матч — префікс фізично не проходить
# крізь backreference. Але «не може» без виміру = віра, тож глибина ще й МІРЯЄТЬСЯ
# до/після (`--selftest` доводить, що той вимір дискримінує: він червоніє на
# навмисно наївній заміні й зеленіє на нашій).
#
# ⛔ ОГОЛОШЕНІ СТЕЛІ (гейт без названої стелі перетворює зелене на «не перевірено»):
#   1. Скрипт править ТЕКСТ. Він не рухає ПУНКТИ `00_07` між `## §NN`-секціями
#      (крок 4 методу) і не переписує §-адреси при злитті доків (там потрібен
#      арифметичний зсув, інший інструмент). Обидва — окремі хвилі.
#   2. Заміна не відрізняє «реф» від «історичного запису». Рядок CHANGELOG про
#      подію 2026-07 і живий крос-реф для неї той самий текст. Історія НЕ їде за
#      доками — тому є `--exclude`, і тому touched-історія друкується як advisory.
#   3. Форма класифікується позиційно (fence › href › label › path › code › bare).
#      Хит у markdown-таблиці всередині fenced-блоку читається як `fence` — це
#      навмисно: ілюстрація не є рефом, але й мовчки зникнути з інвентаря не сміє.
#
# Usage:
#   ruby scripts/canon_renumber.rb 04_06_Old_Name:00_05_New_Name [OLD:NEW …]
#   ruby scripts/canon_renumber.rb --apply  04_06_Old:00_05_New
#   ruby scripts/canon_renumber.rb --allow-historical=CHANGELOG.md,lib/docs_linter.rb …
#   ruby scripts/canon_renumber.rb --selftest        # мутаційна проба самих guard-ів
#
require "optparse"
require "set"
require "shellwords"

# Відмова йде в stderr, звіт — у stdout. Без цього рядка буферизований stdout
# віддає їх у РІЗНОМУ порядку під редиректом, і причина відмови лягає в середину
# таблиці — тобто інструмент, чия єдина робота бути прочитаним, ховає свій вердикт.
$stdout.sync = true

ROOT = File.expand_path("..", __dir__)

# ── пара «старий basename → новий basename» ─────────────────────────────────
Pair = Struct.new(:old_base, :new_base) do
  def old_id = old_base[0, 5]
  def new_id = new_base[0, 5]
  def to_s   = "#{old_base} → #{new_base}"
end

# ── опції ───────────────────────────────────────────────────────────────────
opts = { apply: false, historical: [], exclude: [], verbose: false, mv: true, selftest: false }
OptionParser.new do |o|
  o.banner = "usage: ruby scripts/canon_renumber.rb [опції] OLD_BASENAME:NEW_BASENAME [OLD:NEW …]"
  o.on("--apply", "записати (за замовчуванням — dry-run)")                 { opts[:apply] = true }
  o.on("--allow-historical=LIST", "файли, де цитата ЦІЛЬОВОГО номера свідомо історична (кома)") { |v| opts[:historical] += v.split(",").map(&:strip) }
  o.on("--allow-historical-from=PATH", "те саме списком із файлу (по рядку, `#` — коментар)") do |v|
    opts[:historical] += File.readlines(v).map { |l| l.sub(/#.*/, "").strip }.reject(&:empty?)
  end
  o.on("--exclude=RE", "не чіпати файли, чий repo-relative шлях матчить RE (повторюване)") { |v| opts[:exclude] << Regexp.new(v) }
  o.on("--allow-alias", "дозволити запис попри `NN_NN_НевідомеІмʼя` токени")   { opts[:allow_alias] = true }
  o.on("--no-mv", "не робити `git mv` самих файлів (лише контент)")        { opts[:mv] = false }
  o.on("-v", "--verbose", "по-файлова таблиця, а не лише незбалансовані рядки") { opts[:verbose] = true }
  o.on("--selftest", "мутаційна проба вбудованих guard-ів (без репо)")     { opts[:selftest] = true }
end.parse!

# ════════════════════════════════════════════════════════════════════════════
# ТРАНСФОРМ — серце. Одна alternation, ordered specific→generic, ОДИН прохід.
# ════════════════════════════════════════════════════════════════════════════
#
# Три альтернативи на пару, і порядок несучий:
#   FULL  `04_06_Testing_Guide_and_Coverage`  → повний новий basename
#   ALIAS `04_06` + `_Слово` (імʼя НЕ наше)   → лише номер (це вже дангл; не гіршаємо)
#   BARE  `04_06`                              → лише номер
# FULL мусить стояти ПЕРЕД BARE: альтернація Ruby бере ПЕРШУ, що збіглась на
# позиції, не найдовшу, — тож без цього порядку `04_06_Testing_Guide…` перетворився
# б на `00_05_Testing_Guide…` з ІМʼЯМ старої сторінки, і path-форма стала б мертвою.
#
# Digit-boundary: `(?<![0-9])` зліва не дає збігтись усередині `107_01`; `(?![0-9])`
# справа — усередині `07_011`. FULL додатково закривається `(?![A-Za-z0-9_])`, щоб
# не зʼїсти префікс довшого імені (`…_Coverage_Extra`).
def build_transform(pairs)
  full  = pairs.to_h { |p| [ p.old_base, p.new_base ] }
  by_id = pairs.to_h { |p| [ p.old_id,   p.new_id   ] }

  alts = pairs.map { |p| "#{Regexp.escape(p.old_base)}(?![A-Za-z0-9_])" } +
         pairs.map { |p| "#{Regexp.escape(p.old_id)}(?=_[A-Za-z0-9])" } +
         pairs.map { |p| "#{Regexp.escape(p.old_id)}(?![0-9])" }
  re = /(?<![0-9])(?:#{alts.join('|')})/

  # ⚠️ Заміна повертає ЛИШЕ токен. `../`, `docs/`, `.md`, `#anchor` і §-хвіст
  # лишаються поза матчем — саме тому глибина relative-лінка не може вкоротитись,
  # а секційний якір `§N` не може бути зачеплений (вимоги 4 і 8).
  ->(text) { text.gsub(re) { |m| full[m] || by_id[m] } }
end

# ── позиційний класифікатор форм ────────────────────────────────────────────
def span_index(text)
  spans = { fence: [], label: [], href: [], path: [], code: [] }

  off = 0
  in_fence = false
  text.each_line do |line|
    in_fence = !in_fence if line.start_with?("```")
    spans[:fence] << (off...off + line.length) if in_fence || line.start_with?("```")
    off += line.length
  end

  text.scan(/\[([^\]\n]*)\]\(([^)\s]*)\)/) do
    m = Regexp.last_match
    spans[:label] << (m.begin(1)...m.end(1))
    spans[:href]  << (m.begin(2)...m.end(2))
  end
  # `(?:\.\./)+` — форма, приписана методом. Тут вона ЛИШЕ вимірює; жодна заміна
  # цю групу не тягне через backreference, і в цьому вся суть (див. шапку).
  text.scan(%r{(?:\.\./)*docs/\d\d_\d\d_[A-Za-z0-9_]+(?:\.md)?}) { spans[:path] << (Regexp.last_match.begin(0)...Regexp.last_match.end(0)) }
  text.scan(/`[^`\n]+`/) { spans[:code] << (Regexp.last_match.begin(0)...Regexp.last_match.end(0)) }
  spans
end

FORM_ORDER = %i[fence href label path code].freeze
FORM_NAME  = { fence: "fence", href: "link-href", label: "link-label", path: "path", code: "codespan" }.freeze

def form_at(offset, spans)
  FORM_ORDER.each { |f| return FORM_NAME[f] if spans[f].any? { |r| r.cover?(offset) } }
  "bare"
end

# Інвентар: [форма, токен-клас, номер, рядок] на кожен хит одного з `ids`.
# `bases` — відомі повні basename-и (щоб відрізнити токен-клас `full` від `id`).
def inventory(text, ids, bases)
  return [] if ids.empty?

  spans = span_index(text)
  line_of = ->(off) { text[0, off].count("\n") + 1 }
  id_re = /(?<![0-9])(#{ids.map { |i| Regexp.escape(i) }.join('|')})(?![0-9])/
  hits = []
  text.scan(id_re) do
    m = Regexp.last_match
    off = m.begin(0)
    tail = text[off, 120].to_s
    tok =
      if (b = bases.find { |x| tail.start_with?(x) && tail[x.length].to_s !~ /[A-Za-z0-9_]/ }) then "full:#{b[0, 5]}"
      elsif tail =~ /\A\d\d_\d\d_[A-Za-z0-9]/ then "alias"
      else "id"
      end
    hits << [ form_at(off, spans), tok.sub(/:.*/, ""), m[1], line_of.call(off) ]
  end
  hits
end

# ── перевірка глибини relative-лінків (вимога 4, ЯВНО) ──────────────────────
REL_DEPTH_RE = %r{\]\(((?:\.\./)+)((?:docs/)?)(\d\d_\d\d_[A-Za-z0-9_]+)}

def depth_profile(text, rename_map)
  text.scan(REL_DEPTH_RE).map { |ups, docs, base| [ ups, docs, rename_map.fetch(base, base) ] }.tally
end

# ════════════════════════════════════════════════════════════════════════════
# SELFTEST — мутаційна проба. Guard мусить ДИСКРИМІНУВАТИ: червоніти на наївній
# заміні й зеленіти на нашій. Guard, що зелений завжди, — це не guard.
# ════════════════════════════════════════════════════════════════════════════
#
# 🔴 ФІКСТУРИ СИНТЕТИЧНІ (`91_01`/`92_02`), А HREF ЗБИРАЄТЬСЯ КОНКАТЕНАЦІЄЮ — і це не
# педантизм. Перша версія писала їх літералами з реальними id, і `docs:check_refs`
# ЧЕСНО почервонів на `[`00_04 §1`](../../07_01_…)`: його `link label↔href mismatch`
# сканує `scripts/`, а фікстура напівзаміни від справжнього дефекту не відрізняється.
# Лікується не винятком у `docs_linter` (виняток довелося б супроводжувати), а тим,
# щоб літерал не існував: після `](` у ВИХІДНОМУ тексті стоїть `#`, не `../`.
UP2 = "../../"
UP3 = "../../../"
UP4 = "../../../../"
DOCS_SEG = "docs/"

if opts[:selftest]
  pairs = [ Pair.new("91_01_Alpha_Doc", "92_02_Alpha_Doc"),
            Pair.new("93_03_Beta_Guide", "94_04_Beta_Standard") ]
  tf   = build_transform(pairs)
  rmap = pairs.to_h { |p| [ p.old_base, p.new_base ] }
  fail_count = 0
  check = lambda do |name, got, want|
    ok = got == want
    fail_count += 1 unless ok
    puts "  #{ok ? '✓' : '✗'} #{name}"
    puts "      очікувано: #{want.inspect}\n      отримано:  #{got.inspect}" unless ok
  end

  puts "selftest — guard-и трансформа:"
  check.call("digit-boundary справа: `91_011` не чіпається", tf.call("см. 91_011 тут"), "см. 91_011 тут")
  check.call("digit-boundary зліва: `191_01` не чіпається",  tf.call("рядок 191_01."),  "рядок 191_01.")
  check.call("§-якір недоторканий",                          tf.call("`91_01 §6.5`"),   "`92_02 §6.5`")
  check.call("FULL перед BARE (імʼя не лишається старим)",
             tf.call("](#{UP2}93_03_Beta_Guide.md)"),
             "](#{UP2}94_04_Beta_Standard.md)")
  check.call("глибина `../../../..` збережена",
             tf.call("](#{UP4}91_01_Alpha_Doc.md)"),
             "](#{UP4}92_02_Alpha_Doc.md)")
  check.call("alias `93_03_Beta` (імʼя НЕ наше) → лише номер", tf.call('"93_03_Beta"'), '"94_04_Beta"')
  check.call("одночасність: A→B і B→C не каскадують",
             build_transform([ Pair.new("91_01_A", "93_03_A"), Pair.new("93_03_B", "95_05_B") ]).call("91_01_A · 93_03_B"),
             "93_03_A · 95_05_B")

  puts "\nselftest — чи ДИСКРИМІНУЄ вимір глибини (мутація: наївний `(\\.\\./)*` через $1):"
  src   = "](#{UP2}#{DOCS_SEG}91_01_Alpha_Doc.md) та ](#{UP3}91_01_Alpha_Doc.md)"
  naive = src.gsub(%r{\]\((\.\./)*(docs/)?91_01_Alpha_Doc}) { "](#{Regexp.last_match(1)}#{Regexp.last_match(2)}92_02_Alpha_Doc" }
  before = depth_profile(src, rmap)
  check.call("наївна заміна ТИХО вкоротила `../../` → детектор бачить", (depth_profile(naive, rmap) != before), true)
  check.call("наша заміна глибину зберегла → детектор мовчить",         (depth_profile(tf.call(src), rmap) == before), true)
  check.call("(і сама наївна дійсно зіпсувала текст)", naive.include?("](../#{DOCS_SEG}92_02"), true)

  puts "\nselftest — чи ДИСКРИМІНУЄ свіп 3а «мітка ⊥ href» (переюзаний DocsLinter):"
  begin
    require_relative "../lib/docs_linter"
    # Мітка переїхала, href лишився старим — рівно клас, що народжується зі скрипта,
    # який замінює МІТКУ окремо від АДРЕСИ (крок 3а методу).
    check.call("напівзаміна (нова мітка + старий href) ловиться",
               DocsLinter.link_label_target_mismatch("[`92_02 §1`](#{UP2}91_01_Alpha_Doc.md)").size, 1)
    check.call("повна заміна (обидві половини) — мовчання",
               DocsLinter.link_label_target_mismatch("[`92_02 §1`](#{UP2}92_02_Alpha_Doc.md)"), [])
    check.call("bold-prose-обгортка не звинувачується (відомий FP)",
               DocsLinter.link_label_target_mismatch("**[`93_03`-прямий + [`91_01 §4.3`](#{UP2}91_01_Alpha_Doc.md)]** X.15"), [])
  rescue LoadError, NameError => e
    puts "  ⚠ NOT-RUN: #{e.class} — свіп 3а неперевірений"
    fail_count += 1
  end

  puts(fail_count.zero? ? "\n✅ selftest зелений — усі guard-и дискримінують" : "\n❌ selftest ЧЕРВОНИЙ: #{fail_count}")
  exit(fail_count.zero? ? 0 : 1)
end

# ════════════════════════════════════════════════════════════════════════════
# РОЗБІР ПАР
# ════════════════════════════════════════════════════════════════════════════
abort("canon_renumber: потрібна хоча б одна пара OLD_BASENAME:NEW_BASENAME") if ARGV.empty?

pairs = ARGV.map do |arg|
  o, n = arg.split(":", 2)
  abort("canon_renumber: `#{arg}` не є парою OLD:NEW") unless o && n
  [ o, n ].each do |b|
    abort("canon_renumber: `#{b}` не схожий на канон-basename (NN_NN_Name, без .md)") unless b =~ /\A\d\d_\d\d_[A-Za-z0-9_]+\z/
  end
  abort("canon_renumber: docs/#{o}.md не існує") unless File.exist?(File.join(ROOT, "docs", "#{o}.md"))
  abort("canon_renumber: docs/#{n}.md УЖЕ існує — колізія імен") if File.exist?(File.join(ROOT, "docs", "#{n}.md"))
  Pair.new(o, n)
end

%w[old_id new_id].each do |m|
  dup = pairs.map(&m.to_sym).tally.select { |_, c| c > 1 }.keys
  abort("canon_renumber: дубльований #{m}: #{dup.join(', ')}") if dup.any?
end

OLD_IDS   = pairs.map(&:old_id).freeze
NEW_IDS   = pairs.map(&:new_id).freeze
OLD_BASES = pairs.map(&:old_base).freeze
NEW_BASES = pairs.map(&:new_base).freeze
RENAME    = pairs.to_h { |p| [ p.old_base, p.new_base ] }.freeze
transform = build_transform(pairs)

puts "canon_renumber — #{opts[:apply] ? 'APPLY' : 'dry-run'}; пар: #{pairs.size}"
pairs.each { |p| puts "  · #{p}" }
puts

# ════════════════════════════════════════════════════════════════════════════
# КОРПУС — усе, що знає git (пʼять названих корпусів і ширше), мінус бінарники
# ════════════════════════════════════════════════════════════════════════════
tracked = IO.popen([ "git", "-C", ROOT, "ls-files", "-z" ], &:read)
abort("canon_renumber: `git ls-files` провалився — корпус невідомий, працювати наосліп не можна") unless $?.success?

# Само-виключення: приклади в шапці цього файлу (`04_06_Testing_Guide_and_Coverage` →
# …) — ФІКСТУРИ, не рефи. Інструмент, що переписує власну документацію, знищує саме
# те пояснення, заради якого його читають. Прецедент — `code_doc_section_refs.rb`:
# «⛔ scripts/ СВІДОМО лишається поза периметром … скан себе почервонив би на власній
# таблиці винятків». Вимірюється теж: корпус-повнота нижче віднімає цей файл ЯВНО,
# щоб виключення не сховалось у розбіжності лічильників.
SELF_REL = File.join("scripts", File.basename(__FILE__))

files = tracked.split("\0").reject do |rel|
  rel == SELF_REL || opts[:exclude].any? { |re| rel =~ re }
end.select do |rel|
  path = File.join(ROOT, rel)
  File.file?(path) && !File.symlink?(path) && File.size(path) < 4_000_000
end

# 🔴 МЕЖА КОРПУСУ — ПРАВИЛО git, НЕ ВЛАСНЕ. Цільно-файловий тест «є NUL → бінарник»
# СТРОГІШИЙ за git, і різниця не теоретична: `scripts/guard_registry_sync.rb` тримає
# літеральний NUL на байті 16226 (роздільник при сплиті markdown-таблиці), git його
# не бачить (евристика дивиться ПЕРШІ 8000 байт) і чесно грепає файл, а власний тест
# викидав його з корпусу — разом із живим ключем реєстру гейтів `(05_03/07_01)`.
# Тобто свіп мовчки лишав би реф у ГЕЙТ-РЕЄСТРІ. Дзеркалимо git рівно.
GIT_BINARY_WINDOW = 8000
excluded = []
SOURCE = files.each_with_object({}) do |rel, h|
  raw = File.binread(File.join(ROOT, rel))
  if raw[0, GIT_BINARY_WINDOW].to_s.include?("\0")
    excluded << [ rel, "binary (NUL у перших #{GIT_BINARY_WINDOW} байтах — так само бачить git)" ]
    next
  end

  txt = raw.dup.force_encoding("UTF-8")
  if txt.valid_encoding?
    h[rel] = txt
  else
    excluded << [ rel, "не UTF-8" ]
  end
end
puts "корпус: #{SOURCE.size} текстових файлів під git (#{excluded.size} виключено як бінарні/не-UTF-8)"

# ── КОРПУС-ПОВНОТА: НЕЗАЛЕЖНИЙ вимір тієї самої множини ─────────────────────
# Свій же лічильник, звірений сам із собою, доводить лише те, що він детермінований.
# Тому те саме число рахує ІНШИЙ інструмент (`git grep -o`), який має власне уявлення
# і про межу корпусу, і про межу токена. Розбіжність = сліпа зона свіпа, і вона мусить
# бути НАЗВАНА пофайлово, а не розчинена в підсумку.
# NOT-RUN ⊥ PASS: git без PCRE не вміє lookbehind — тоді це «не перевірено», не «чисто».
git_total = nil
probe = IO.popen([ "git", "-C", ROOT, "grep", "-I", "-o", "-P", "(?<!\\d)(#{OLD_IDS.join('|')})(?!\\d)" ], err: File::NULL, &:read)
if $?.exitstatus.between?(0, 1) && !(probe.empty? && $?.exitstatus == 1)
  per_file = probe.each_line.each_with_object(Hash.new(0)) { |l, h| h[l.split(":", 2).first] += 1 }
  self_hits_in_git = per_file.delete(SELF_REL).to_i # оголошене виключення, а не тиха розбіжність
  opts[:exclude].each { |re| per_file.reject! { |f, _| f =~ re } }
  puts "  (само-виключено #{SELF_REL}: #{self_hits_in_git} власних фікстур/прикладів)" if self_hits_in_git.positive?
  git_total = per_file.values.sum
  mine = SOURCE.transform_values { |t| t.scan(/(?<![0-9])(?:#{OLD_IDS.join('|')})(?![0-9])/).size }.reject { |_, v| v.zero? }
  gap = (per_file.keys | mine.keys).filter_map { |f| [ f, mine[f].to_i, per_file[f] ] if mine[f].to_i != per_file[f] }
  if gap.empty?
    puts "  ✓ корпус-повнота: `git grep` бачить ті самі #{git_total} входжень у тих самих #{mine.size} файлах"
  else
    puts "  ✗ КОРПУС-ПОВНОТА: свіп і `git grep` розходяться — свіп СЛІПИЙ до цих файлів:"
    gap.each { |f, m, g| puts format("     %s: свіп=%d git=%d", f, m, g) }
  end
else
  puts "  ⚠ корпус-повнота NOT-RUN: `git grep -P` недоступний (git без PCRE) — це НЕ «чисто»"
end

# ════════════════════════════════════════════════════════════════════════════
# 1. PRESENCE-CHECK ЦІЛЬОВИХ НОМЕРІВ
# ════════════════════════════════════════════════════════════════════════════
# Клас, який це ловить, — не «конфлікт імен» (його зловив би `File.exist?`), а
# ТИХЕ ЗАХОПЛЕННЯ ПРЕДМЕТА: стара цитата розчиненого `00_02` після переїзду
# починає резолвитись у зовсім іншу сторінку. Кожен ref-гейт при цьому ЗЕЛЕНІЄ —
# адреса ж існує. Червоніти має тут, ДО запису.
historical = opts[:historical].to_set
occupied = Hash.new { |h, k| h[k] = [] }
SOURCE.each do |rel, txt|
  inventory(txt, NEW_IDS, NEW_BASES).each { |form, tok, id, line| occupied[id] << [ rel, line, form, tok ] }
end

unless occupied.empty?
  blocking = occupied.transform_values { |v| v.reject { |rel, _, _, _| historical.include?(rel) } }.reject { |_, v| v.empty? }
  puts "\n── presence-check ЦІЛЬОВИХ номерів ──────────────────────────────────"
  occupied.each do |id, hits|
    exempted = hits.count { |rel, _, _, _| historical.include?(rel) }
    puts format("  %s: %d згадок у %d файлах (оголошено історичними: %d)", id, hits.size, hits.map(&:first).uniq.size, exempted)
  end
  if blocking.any?
    puts "\n  ⛔ ЦІЛЬОВИЙ НОМЕР НЕ ВІЛЬНИЙ. Кожна згадка нижче після переїзду почне"
    puts "     резолвитись у НОВИЙ предмет, і жоден ref-гейт цього не побачить."
    puts "     Прочитай КОЖНУ й вирішіи: `--allow-historical=<файл>` (запис про минуле,"
    puts "     адреса є частиною ФАКТУ) або правка перед переїздом (жива навігація)."
    blocking.each do |id, hits|
      hits.first(40).each { |rel, line, form, tok| puts format("     ✗ %-6s %s:%d  [%s/%s]", id, rel, line, form, tok) }
      puts "     … ще #{hits.size - 40}" if hits.size > 40
    end
  else
    puts "  ✓ усі згадки цільових номерів оголошені історичними"
  end
end
BLOCKED = defined?(blocking) && blocking&.any?
abort("\ncanon_renumber: --apply відмовлено — цільовий номер зайнятий (див. вище)") if BLOCKED && opts[:apply]

# ════════════════════════════════════════════════════════════════════════════
# 2. ІНВЕНТАР ДО  ·  3. ТРАНСФОРМ  ·  4. ГЛИБИНА
# ════════════════════════════════════════════════════════════════════════════
before   = {}
after    = {}
result   = {}
depth_bad = []
alias_hits = []

SOURCE.each do |rel, txt|
  b = inventory(txt, OLD_IDS + NEW_IDS, OLD_BASES + NEW_BASES)
  next if b.empty?

  before[rel] = b
  alias_hits.concat(b.select { |_, tok, id, _| tok == "alias" && OLD_IDS.include?(id) }.map { |f, _, id, l| [ rel, l, id, f ] })

  out = transform.call(txt)
  result[rel] = out
  after[rel]  = inventory(out, OLD_IDS + NEW_IDS, OLD_BASES + NEW_BASES)

  dbefore = depth_profile(txt, RENAME)
  dafter  = depth_profile(out, {})
  depth_bad << [ rel, dbefore, dafter ] unless dbefore == dafter
end

puts "\n── `../`-глибина relative-лінків ────────────────────────────────────"
rel_total = before.keys.sum { |rel| SOURCE[rel].scan(REL_DEPTH_RE).size }
if depth_bad.empty?
  puts "  ✓ #{rel_total} relative-лінків: профіль (глибина × префікс × ціль) ідентичний до/після"
else
  depth_bad.each { |rel, b2, a2| puts "  ✗ #{rel}: #{(b2.to_a - a2.to_a).inspect} → #{(a2.to_a - b2.to_a).inspect}" }
end

unless alias_hits.empty?
  puts "\n── ALIAS: `NN_NN_ІмʼяЯкеНеНаше` (перенумеровано лише НОМЕР) ─────────"
  alias_hits.each { |rel, line, id, form| puts format("  ⚠ %-6s %s:%d [%s]", id, rel, line, form) }
  puts "  Це вже дангл-шлях або тест-фікстура — заміна номера його не гіршає, але"
  puts "  прочитай кожен: імʼя лишилось старим свідомо чи це недобитий rename?"
end

# ════════════════════════════════════════════════════════════════════════════
# 5. ZERO-LOSS REFERRER-DIFF
# ════════════════════════════════════════════════════════════════════════════
# Арифметика чесна саме тому, що НЕ припускає порожнечі цільового номера:
#   lost(old)  = before[old] − after[old]        (мусить дорівнювати before[old])
#   gained(new)= after[new]  − before[new]       (base віднімається, а не ігнорується)
# і lost == gained у КОЖНІЙ клітинці (файл × форма × токен-клас).
def cellify(hits)
  hits.each_with_object(Hash.new(0)) { |(form, tok, id, _), h| h[[ form, tok, id ]] += 1 }
end

rows = []
lost_total = gained_total = 0
unbalanced = []
id_of = pairs.to_h { |p| [ p.old_id, p.new_id ] }

before.each_key do |rel|
  cb = cellify(before[rel])
  ca = cellify(after[rel])
  (cb.keys | ca.keys).map { |form, tok, _| [ form, tok ] }.uniq.each do |form, tok|
    OLD_IDS.each do |oid|
      nid  = id_of[oid]
      lost   = cb[[ form, tok, oid ]] - ca[[ form, tok, oid ]]
      gained = ca[[ form, tok, nid ]] - cb[[ form, tok, nid ]]
      next if lost.zero? && gained.zero?

      lost_total += lost
      gained_total += gained
      rows << [ rel, form, tok, oid, nid, lost, gained ]
      unbalanced << rows.last unless lost == gained
    end
  end
end

agg = Hash.new { |h, k| h[k] = [ 0, 0 ] }
rows.each { |_, form, tok, oid, _, lost, gained| a = agg[[ form, tok, oid ]]; a[0] += lost; a[1] += gained }

puts "\n── zero-loss referrer-diff (агрегат: форма × токен × номер) ─────────"
puts format("  %-12s %-6s %-7s %8s %8s", "ФОРМА", "ТОКЕН", "НОМЕР", "ЗНИКЛО", "ЗʼЯВИЛОСЬ")
agg.sort_by { |(f, t, o), _| [ f, t, o ] }.each do |(f, t, o), (l, g)|
  puts format("  %-12s %-6s %-7s %8d %8d %s", f, t, o, l, g, l == g ? "" : "  ✗ РОЗБАЛАНС")
end
puts format("  %-12s %-6s %-7s %8d %8d", "УСЬОГО", "", "", lost_total, gained_total)

if opts[:verbose]
  puts "\n── по-файлова таблиця ──────────────────────────────────────────────"
  rows.sort.each { |rel, f, t, o, n, l, g| puts format("  %-52s %-12s %-6s %s→%s  −%d +%d%s", rel[0, 52], f, t, o, n, l, g, l == g ? "" : "  ✗") }
end

residue = after.flat_map { |rel, hits| hits.select { |_, _, id, _| OLD_IDS.include?(id) }.map { |f, t, id, l| [ rel, l, id, f, t ] } }
zero_loss_ok = unbalanced.empty? && lost_total == gained_total && residue.empty? && depth_bad.empty?

unless unbalanced.empty?
  puts "\n  ✗ РОЗБАЛАНСОВАНІ КЛІТИНКИ (#{unbalanced.size}) — реф зник без відповідника:"
  unbalanced.each { |rel, f, t, o, n, l, g| puts format("     %s  [%s/%s] %s→%s  зникло %d, зʼявилось %d", rel, f, t, o, n, l, g) }
end
unless residue.empty?
  puts "\n  ✗ ЗАЛИШКИ старого номера після заміни (#{residue.size}):"
  residue.first(40).each { |rel, l, id, f, t| puts format("     %-6s %s:%d [%s/%s]", id, rel, l, f, t) }
end
puts(zero_loss_ok ? "\n  ✅ zero-loss доведено: кожен зниклий реф має рівно один новий-відповідник" : "\n  ❌ zero-loss НЕ доведено")

# ════════════════════════════════════════════════════════════════════════════
# 6. СВІП 3а — самопосилання, зустрічна форма, історія
# ════════════════════════════════════════════════════════════════════════════
puts "\n── свіп 3а: самопосилання ──────────────────────────────────────────"
self_hits = []
pairs.each do |p|
  rel_old = "docs/#{p.old_base}.md"
  txt = result[rel_old] || SOURCE[rel_old]
  next unless txt

  txt.each_line.with_index(1) do |line, i|
    self_hits << [ "docs/#{p.new_base}.md", i, "self-link", line.strip[0, 120] ] if line =~ %r{\]\((?:\.\./)*(?:docs/)?#{Regexp.escape(p.new_base)}(?:\.md)?[)#]}
    self_hits << [ "docs/#{p.new_base}.md", i, "self-§ref", line.strip[0, 120] ] if line =~ /(?<![0-9])#{Regexp.escape(p.new_id)}(?![0-9])\s*§/
  end
end
if self_hits.empty?
  puts "  ✓ жодна перенумерована сторінка не цитує саму себе"
else
  puts "  ⚠ #{self_hits.size} самозгадок — гейт їх НЕ побачить (реф резолвиться!), читай очима:"
  self_hits.each { |f, i, kind, txt| puts format("     %-10s %s:%d  %s", kind, f, i, txt) }
end

puts "\n── свіп 3а: зустрічна форма (мітка ⊥ href) ─────────────────────────"
# 🔴 ВЛАСНОЇ РЕАЛІЗАЦІЇ ТУТ НЕ БУДЕ. Наївний `\[([^\]\n]*)\]` бере за мітку все до
# першої `]`, і на `**[`00_07`-прямий + [`07_03 §4.3`](…)]**` звинувачує невинний
# лінк — рівно той хибний позитив, який `DocsLinter` уже закрив walk-back'ом по
# балансу дужок (`balanced_link_label`, spec «bold prose marker»). Другий детектор
# того самого класу = другий дім правила, і розійтись вони встигли б за один коміт.
# Тут переюзається САМ гейт, лише на ширшому периметрі: він живе на `docs/*.md`,
# а перенумерація ламає мітки й у protocols/, .claude/ та коді.
mismatch = []
begin
  require_relative "../lib/docs_linter"
  ours = (OLD_IDS + NEW_IDS)
  result.each do |rel, txt|
    DocsLinter.link_label_target_mismatch(txt).each do |hit|
      next unless ours.any? { |i| hit.include?(i) }

      mismatch << [ rel, hit ]
    end
  end
  if mismatch.empty?
    puts "  ✓ #{result.size} файлів через `DocsLinter.link_label_target_mismatch` — жодної пари «нова мітка ⊥ старий href»"
  else
    mismatch.each { |rel, hit| puts "  ✗ #{rel}: #{hit}" }
  end
rescue LoadError, NameError => e
  puts "  ⚠ NOT-RUN: не вдалось переюзати DocsLinter (#{e.class}) — це НЕ «чисто»"
  mismatch = nil
end

hist_touched = result.keys.select { |rel| rel =~ /CHANGELOG|\bhistory\b/i && before[rel] }
unless hist_touched.empty?
  puts "\n  ⚠ ІСТОРІЯ ЗМІНЕНА: #{hist_touched.join(', ')} — «історія не їде за доками»."
  puts "    Якщо ці рядки описують МИНУЛУ подію, перезапусти з --exclude='#{hist_touched.first}'."
end

# ════════════════════════════════════════════════════════════════════════════
# 7. ЗАПИС + git mv
# ════════════════════════════════════════════════════════════════════════════
changed = result.reject { |rel, out| out == SOURCE[rel] }
puts "\n── запис ───────────────────────────────────────────────────────────"
puts "  файлів зі змінами: #{changed.size}"

unless opts[:allow_alias] || alias_hits.empty? || !opts[:apply]
  abort("canon_renumber: --apply відмовлено — є ALIAS-токени (#{alias_hits.size}); прочитай їх і додай --allow-alias")
end

if opts[:apply]
  # binwrite, не write: у корпусі є файл із літеральним NUL (див. межу корпусу вище) —
  # байт-у-байт запис не дає жодній перекодовці зʼїсти його мовчки.
  changed.each { |rel, out| File.binwrite(File.join(ROOT, rel), out) }
  puts "  ✍ записано #{changed.size} файлів"
  if opts[:mv]
    pairs.each do |p|
      cmd = [ "git", "-C", ROOT, "mv", "docs/#{p.old_base}.md", "docs/#{p.new_base}.md" ]
      ok = system(*cmd, out: File::NULL)
      puts "  #{ok ? '✓' : '✗'} git mv docs/#{p.old_base}.md → docs/#{p.new_base}.md"
      abort("canon_renumber: git mv провалився — дерево в напівстані, розберись руками") unless ok
    end
  else
    puts "  (--no-mv: файли НЕ перейменовано)"
  end
else
  changed.keys.sort.first(200).each { |rel| puts "    ~ #{rel}" }
  puts "    … ще #{changed.size - 200}" if changed.size > 200
  pairs.each { |p| puts "    → git mv docs/#{p.old_base}.md docs/#{p.new_base}.md" }
end

# ════════════════════════════════════════════════════════════════════════════
# ADVISORY: наступна хвиля — константи, ключовані на НОМЕР доку (крок 4 методу)
# ════════════════════════════════════════════════════════════════════════════
# «Звільнений номер інакше передає успадкований імунітет наступному мешканцю».
# Скрипт ці рядки вже переписав ТЕКСТОМ — але текстова заміна не знає, чи номер
# тут ключ мапи, чи фікстура, чи цитата минулого. Кожен рядок нижче — очима.
const_re = /(["'\/])(?:docs\/)?(?:#{NEW_IDS.map { |i| Regexp.escape(i) }.join('|')})/
consts = changed.select { |rel, _| rel =~ %r{\A(lib|scripts|spec|\.github|\.claude/hooks|tools)/} }
                .flat_map { |rel, out| out.each_line.with_index(1).select { |l, _| l =~ const_re }.map { |l, i| [ rel, i, l.strip[0, 130] ] } }
unless consts.empty?
  puts "\n── advisory (крок 4): #{consts.size} рядків, де НОВИЙ номер стоїть у лапках/регексі ─"
  puts "   (owner/exempt-мапи, TRL_NOT_APPLICABLE, curated-таблиці гейтів — звір кожен)"
  consts.first(60).each { |rel, i, l| puts format("   · %s:%d  %s", rel, i, l) }
  puts "   … ще #{consts.size - 60}" if consts.size > 60
end

puts
puts "НАСТУПНЕ: `ruby scripts/docs_band.rb` (УСЯ смуга, не пара check_refs+tracker — крок 5 методу)."
puts "⚠️ ЦЕЙ СКРИПТ НЕ РОБИТЬ: перенесення пунктів 00_07 між `## §NN`-секціями, §-зсув при злитті," if opts[:apply]
puts "   regen ToC, оновлення `00_00`/README/§2-реєстру. Це кроки 4 і 5, окремими руками." if opts[:apply]

exit(zero_loss_ok && !BLOCKED ? 0 : 1)
