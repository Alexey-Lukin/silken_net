#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/apparatus_census.rb — чи апарат окупається: перепис СПРАЦЮВАНЬ.
#
# ПИТАННЯ, НА ЯКЕ ЗАРАЗ НЕ ВІДПОВІДАЄ НІЩО. Практика тримає ~750 kB шару «як
# робиться робота» в git (15 скілів + промти + хуки + CLAUDE.md) і 1.6 MB
# корпусу памʼяті — і має РІВНО ОДИН вимір того, чи це працює: одноразовий
# ручний прохід, що дав ~212 спрацювань носія проти ~29 рецидивів за 32 доби
# (пункт DOC-T.62). ⚠️ Виміряно 2026-08-22: архівний рядок того пункту цих
# чисел БІЛЬШЕ НЕ НЕСЕ — їх зрізали разом із тілом, і цей коментар три тижні
# спирався на адресу, де предмета вже нема. Підстава дістається деривацією:
#   git log --all -E --grep='DOC-T\.62([^0-9]|$)' -- docs/00_07_Action_Plan_Tracker.md
# Саме те число спростовує «просто заріж мета-шар», і саме
# воно ніколи не переміряється. Цей скрипт робить його відтворюваним.
#
# 🔴 ЩО ЦЕ НЕ Є, І ЦЕ НАЙВАЖЛИВІШЕ РЯДКОМ. Це НЕ «частка успіху правил».
# Знаменник недосяжний за побудовою: речення «приписана форма вистояла» не
# написане НІ РАЗУ на 16 893 асистентських блоках — форма, що спрацювала,
# виконується мовчки, прозу генерують лише падіння. Тому будь-яка заява
# «N із N правил витримали» має стелю 100% незалежно від світу.
#
# ⚠️ ПЕРША РЕДАКЦІЯ ЦЬОГО ЗАГОЛОВКА ОБІЦЯЛА БІЛЬШЕ, НІЖ ФАЙЛ УМІЄ, і це
# виправлено тим самим прогоном, що це виявив. Вона казала: «рахуємо, скільки
# разів носій ПІЙМАВ, проти скільки разів писане правило ВПАЛО — дві події,
# обидві лишають слід». Друга половина хибна: слід лишає лише перша. Носиться
# ОДНА величина — **скільки апарат ловить**, тренд у часі, не оцінка якості.
#
# АСИМЕТРІЯ, названа, а не схована. Спрацювання = машинно емітований рядок
# (`[bash-guard]`, `code_tracker_id_check ✗`) → має ФОРМУ, рахується точно.
# Рецидив = проза → форми не має → не рахується взагалі (доведено обома
# кінцями: широка родина 1066 шуму, вузька 0). Той самий розкол
# «структура ⟷ зміст», що вбив тут пʼять приладів за день — і цей був шостим,
# доки межу не визнали замість того, щоб її обходити.
#
# ⚠️ РЕЄСТР НОСІЇВ ВИВОДИТЬСЯ З РЕПО, не хардкодиться: новий гейт входить у
# перепис сам. Список-за-прикладом гниє з кожним доданим гейтом — це записано
# в скілі `ssot-maintenance` і коштувало окремого проходу.
#
# Не може жити в CI за побудовою: транскрипти лежать поза репо.
# Usage: ruby scripts/apparatus_census.rb [--days N] [--samples N]

require "json"
require "set"

ROOT   = File.expand_path("..", __dir__)
TRANS  = File.expand_path("~/.claude/projects/-Users-oleksiilukin-silken-net")
DAYS   = (i = ARGV.index("--days"))    ? ARGV[i + 1].to_i : 30
NSAMP  = (i = ARGV.index("--samples")) ? ARGV[i + 1].to_i : 8

# ── реєстр носіїв, ВИВЕДЕНИЙ з дерева ────────────────────────────────────────
# 🔴 Наївний витяг «усе в квадратних дужках» ловить РЕГЕКС-КЛАСИ й фікстури
# селфтесту (`[A-Z]`, `[a-z_]`, `[Ghost]`, `[nowhere_at_all]`) і роздуває
# реєстр учетверо — перевірено, зламавшись об це з першого прогону. Тег носія
# розпізнається формою: дефіс, який НЕ є діапазоном (`memory-gate`), або весь
# капс (`SSOT`). Це той самий урок, що вбив тут пʼять приладів за день —
# нормалізація зрізає дискримінатор, і видно це лише в топ-хітах, не в тоталі.
RANGE = /\A[A-Za-z0-9]-[A-Za-z0-9]/
hook_tags = Dir["#{ROOT}/.claude/hooks/*.sh"]
            .flat_map { |f| File.read(f).scan(/\[([A-Za-z][\w-]{2,18})\]/) }.flatten.uniq
            .select { |t| (t.include?("-") && !t.match?(RANGE)) || t.match?(/\A[A-Z]{3,}\z/) }
            .map { |t| "[#{t}]" }
gate_names = Dir["#{ROOT}/scripts/*.rb"].flat_map { |f| File.read(f).scan(/"([a-z][a-z0-9_:]{3,32})\s+[✓✗]/) }
                                        .flatten.uniq
# Гейти, що йдуть через rake: голе імʼя рахувало б ЗГАДКИ (2673 на прогоні, з
# них майже всі — власна проза про гейт). Беремо лише вердиктний рядок.
rake_gates = [ "tracker:check FAILED", "docs:check_refs FAILED", "docs:toc FAILED" ].freeze

carriers = {}
hook_tags.each  { |t| carriers[t] = Regexp.new(Regexp.escape(t)) }
gate_names.each { |g| carriers["#{g} ✗"] = /#{Regexp.escape(g)}\s+✗/ }
rake_gates.each { |g| carriers[g] = /#{Regexp.escape(g)}/ }
carriers["--selftest FAIL"] = /selftest:\s+\d+\s+passed,\s+[1-9]/
carriers["mutation red"]    = /mutant exit=1|FAIL\s+.*expected to/

# 🔴 ЦЯ ПОЛОВИНА НЕ НОСИТЬСЯ, і перший прогін це довів: широка родина дала
# 1066 «рецидивів» проти ~29 ручного виміру — бо ловила кожну ЗГАДКУ слова,
# а корпус пише про рецидиви більше, ніж їх має. Розрізнити «сталося» від
# «пишу про це» — питання ЗМІСТУ, і форми в нього немає. Тому: лише
# перфомативні форми першої особи, і результат називається КАНДИДАТАМИ, які
# читають руками. Дизайн визнає межу, а не вдає, що її нема.
RELAPSE = /я[^.]{0,20}(?:вступив|наступив) у|walked into (?:my|its|the) own|
           спіймав мене|caught me (?:again|on)|вдруге за сесію|втретє за сесію|
           і це на мені|on the author|мій же (?:прилад|хук|гейт) спіймав/xi

files = Dir["#{TRANS}/*.jsonl"].sort
abort "no transcripts at #{TRANS}" if files.empty?

cutoff = Time.now - (DAYS * 86_400)
counts = Hash.new { |h, k| h[k] = { all: 0, win: 0, last: nil } }
relapse = { all: 0, win: 0, samples: [] }
blocks = 0
first_ts = nil
last_ts  = nil

files.each do |path|
  # `File.foreach`, не `IO.foreach`: другий трактує шлях, що починається з `|`,
  # як команду для запуску (CodeQL `rb/non-constant-kernel-open`). Тут шлях
  # приходить із `Dir.glob`, тож експлуатувати нічим — але sink лишається
  # sink'ом, а різниця у виклику нульова.
  File.foreach(path) do |line|
    next if line.length < 40
    ts = line[/"timestamp":"(20\d\d-\d\d-\d\d)T/, 1]
    if ts
      first_ts = ts if first_ts.nil? || ts < first_ts
      last_ts  = ts if last_ts.nil?  || ts > last_ts
    end
    in_window = !ts.nil? && ts >= cutoff.strftime("%Y-%m-%d")
    blocks += 1

    # 🔴 ПРИЛАД БАЧИТЬ ВЛАСНИЙ ВИВІД, і це не теорія — спіймано на другому
    # прогоні: перший надрукував рядок «DORMANT … sbom_conda_lock ✗ ·
    # sbom_submodules ✗», транскрипт це зберіг, і наступний перепис зарахував
    # обом по спрацюванню, а тоді радісно оголосив «no dormant carriers».
    # Тобто ЄДИНИЙ decision-grade вихід цього скрипта самознищувався за один
    # прогін. Спостерігач, що пише в те, що спостерігає, — той самий клас, що
    # `--weight` (ярлик ширший за скоуп) і що фікстури селфтесту в реєстрі.
    next if line.include?("apparatus census ·") ||
            line.include?("DORMANT — declared in the tree") ||
            line.include?("roster DERIVED from the tree")

    carriers.each do |name, re|
      next unless line.match?(re)
      c = counts[name]
      c[:all] += 1
      c[:win] += 1 if in_window
      c[:last] = ts if ts && (c[:last].nil? || ts > c[:last])
    end

    next unless line.match?(RELAPSE)
    relapse[:all] += 1
    relapse[:win] += 1 if in_window
    relapse[:samples] << [ ts, line[/"text":"(.{0,220})/, 1].to_s.gsub('\n', ' ') ] if relapse[:samples].size < NSAMP * 3
  end
end

fired, dormant = carriers.keys.partition { |k| counts[k][:all].positive? }

puts "== apparatus census · #{files.size} transcripts · #{first_ts}…#{last_ts} · #{blocks} lines scanned =="
puts "   roster DERIVED from the tree: #{hook_tags.size} hook tags + #{gate_names.size} gate verdicts + #{rake_gates.size} rake gates"
puts
puts format("%-34s %7s %7s   %s", "CARRIER", "all", "#{DAYS}d", "last fired")
fired.sort_by { |k| -counts[k][:all] }.each do |k|
  c = counts[k]
  puts format("%-34s %7d %7d   %s", k, c[:all], c[:win], c[:last] || "—")
end

puts
if dormant.any?
  puts "SILENT — never printed a ✗ in the whole corpus (#{dormant.size}): #{dormant.sort.join(' · ')}"
end
puts <<~HONEST

  🔴 WHAT THIS CANNOT TELL YOU, and the first draft of this script claimed it could.
     Silence is AMBIGUOUS BY CONSTRUCTION. A gate that never went red may be
     guarding nothing — or deterring perfectly, which is the entire point of a
     gate. Nothing in a failure count separates those, and it is the same
     unobtainable denominator as «a rule held», one storey down. The draft called
     the silent list "the ONLY decision-grade output"; that was false, and the two
     entries it flagged proved it — both are SBOM *generators*, where ✗ means the
     script BROKE, so silence there is health, not dormancy. So: **do not retire a
     carrier because it appears here.** Read what it guards first.

  🔴 THE RELAPSE HALF IS NOT MEASURABLE HERE, and that is a finding, not a gap.
     Measured twice: a broad prose family returns ~1066 (it counts every MENTION,
     and this corpus writes about relapses far more often than it has them); a
     narrow performative family returns 0. Separating «it happened» from «I am
     writing about it happening» is a question of MEANING, and meaning has no form
     for a machine to grip — the same wall that stopped four other instruments
     built over this corpus in one day. The carrier side counts exactly because a
     firing is a machine-emitted STRING. Keep the halves apart; a ratio across them
     would be a verdict dressed as a measurement.
HONEST
