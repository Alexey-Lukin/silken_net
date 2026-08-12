#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# spec_claim_audit — ADVISORY, ON-DEMAND. НЕ CI-гейт, НЕ merge-blocking.
# Завжди виходить 0: вердикт живе у ВИВОДІ, не в exit-коді (реєстр — `00_06 §3`).
#
# ЩО ЛОВИТЬ: розходження між НАЗВОЮ прикладу і тим, що він реально тверджує —
# «приклад, який не може впасти» (`04_06 §B.2` #15). Форма-архетип: назва обіцяє
# ефект («filters by severity», «creates firmware»), а всі твердження прикладу —
# лише про HTTP-статус, лише про тип, лише `not_to raise_error` або лише про
# наявність ключа. Такий приклад ходить по коду (покриття росте) і не падає ні
# на чому — тобто це вимкнений детектор, який CI звітує зеленим.
#
# 🔴 ЧОМУ ЦЕ СКРИПТ, А НЕ ГЕЙТ. HARD-гейт тут неможливий за побудовою: самі
# матчери доречні, дефект СЕМАНТИЧНИЙ. А корпусний advisory-звіт був відхилений
# виміром 2026-08-03 — 282 кандидати при точності близько половини читаються
# рівно нуль разів, тобто це вимкнений гейт у костюмі звіту (§Guard-craft #3;
# адресу нормалізовано 2026-08-08 зі схеми «форма N», якої в скілі не існує —
# і вона була невидима навіть власному свіпу, бо ПЕРЕНЕСЕНА через рядок: тег і
# число опинились у різних коментарях, тож line-grep їх не пару́є. Той самий
# клас, що slash-списки ID у `deep_archival.md` Фаза 2).
# Тому дефолт — **діф**: на одному тракті це 0–5 рядків, які справді читають,
# і це механізований вигляд правила «переписуй приклад тоді, коли в тому ж файлі
# шипиться контракт відповіді, а не заради метрики».
#
# 🔴 ЛІЧИЛЬНИК ЗНІМАЙ ЛИШЕ ЗВІДСИ, НЕ ГРЕПОМ. Обсяг цього класу тричі поспіль
# рахували хибно (17 → 10 → 6 → фактично інше число), і щоразу з тієї самої
# причини: греп зараховував КОМЕНТАРІ, що цитують стару форму, як живі сайти.
# Скрипт рахує код і прозу окремо й друкує обидва числа саме тому.
#
# ⚠️ СТЕЛЯ (названа явно — мовчання читалося б як «перевірено все»):
#   1. Парсер рядковий, не AST. `it { is_expected.to … }`, `shared_examples`,
#      `it_behaves_like` та shoulda-матчери (`validate_presence_of`) не бачить.
#   2. Дієслівний фільтр назви — англомовний. Назви українською («шифрує СТАРИМ
#      ключем») у кандидати не потрапляють, хоч клас той самий.
#   3. Він не знає, чи матчер слабкий ПО СУТІ: `be_present` над `parsed["lat"]`
#      слабке, над `Rack::Attack.throttles["x"]` — майже сильне. Читання
#      обовʼязкове; це шортліст, не вердикт.
#   4. Двійникування (два приклади в протилежних контекстах із побайтово
#      однаковим тілом) він не шукає — то окрема вісь, і греп її теж не бачить.
#      ⚠️ Стеля жива: 2026-08-12 такий випадок знайдено руками —
#      `sessions_controller_spec` мав два приклади з побайтово однаковими тілами
#      під «destroys the current session record» і «returns the most recent
#      session», тобто одне слабке тіло за двох обіцянок.
#   5. 🔴 НАЙВАЖЛИВІША, бо міняє читання будь-якого числа звідси: він судить
#      ФОРМУ твердження й СТРУКТУРНО не бачить складу ФІКСТУРИ. Приклад із
#      бездоганним піном на вміст (`ids` include/exclude, `types.uniq == [...]`)
#      так само не здатен упасти, якщо в наборі немає того, що механізм мусить
#      ВІДКИНУТИ. Виміряно на `maintenance_records_controller_spec`: із чотирьох
#      зіпсованих фільтрів цей скрипт бачив ДВА, а `types.uniq == ["inspection"]`
#      тримався й зі знятим фільтром, бо єдиний свій запис і був інспекцією.
#      **Тому будь-яке число звідси — ПІДЛОГА, а не перелік**, і «0 кандидатів у
#      цьому файлі» не означає «фільтри доведені». Канон — `04_06 §B.2` BP 21.
#
# ВЖИТОК:
#   ruby scripts/spec_claim_audit.rb            # діф проти main (дефолт)
#   ruby scripts/spec_claim_audit.rb --all      # увесь корпус (для виміру класу)
#   ruby scripts/spec_claim_audit.rb spec/x_spec.rb spec/y_spec.rb

require "pathname"

ROOT = Pathname.new(__dir__).parent

# Дієслова, що обіцяють ЕФЕКТ. Назва, яка сама називає код або клас статусу,
# свідомо виведена: там твердження лише про статус доречне.
BEHAVIOUR_VERBS = %w[
  renders returns includes shows lists creates updates deletes destroys sends
  broadcasts calculates enqueues blocks throttles rejects allows prevents marks
  sets assigns redirects filters sorts orders validates logs notifies resolves
  mints burns pays records tracks applies denies grants scopes isolates hides
  displays persists stores writes reads counts derives builds generates clears
  drains settles confirms escalates rotates provisions
].freeze

STATUS_NAMED = /\b(\d{3}|ok|created|no content|not found|unauthorized|forbidden|
                  unprocessable|too many|bad request|conflict|see other|redirect)\b/xi

# ⚠️ ЛИШЕ HTTP-статус. Ранній анкер включав `status)` і тому зараховував
# `expect(tx.status).to eq("confirmed")` — статус МОДЕЛІ, тобто цілком змістовне
# твердження про AASM. Один токен у двох доменах дав 7 хибних кандидатів.
MATCHERS = {
  no_raise: /(not_to|to_not)\s+raise_error/,
  status: /have_http_status|response\.status|response\.code/,
  type: /be_a\(|be_an\(|be_an_instance_of|be_kind_of|be_instance_of/,
  have_key: /have_key\(/,
  presence: /be_present|be_truthy|be_falsey|be_blank|be_nil|\bbe\(true\)|\bbe\(false\)/
}.freeze

BARE_RECEIVED = /have_received\(/
ARG_MATCHER   = /\bwith\(|hash_including|array_including|a_string_matching|a_hash_including/

# Негативне твердження під негативною назвою доводить «не сталось» — це сильно.
NEGATIVE_NAME = /\b(no|not|never|without|skips?|ignores?|refuses?|nil|empty|blank|
                  missing|absent|does not|doesn't|won't|unchanged|idempoten)\b/xi

Finding = Struct.new(:path, :line, :name, :kind, :asserts, keyword_init: true)

def examples_in(path)
  lines = File.readlines(path, chomp: false)
  found = []

  lines.each_with_index do |line, idx|
    next unless line =~ /^(\s*)(it|specify)\s*[("]/

    indent = Regexp.last_match(1).length
    name = line[/(?:it|specify)\s*\(?\s*["']([^"']+)["']/, 1]
    next if name.nil?

    asserts = []
    prose = 0
    cursor = idx + 1
    while cursor < lines.length
      current = lines[cursor]
      break if current =~ /^\s{#{indent}}end\b/

      stripped = current.lstrip
      if stripped.start_with?("#")
        prose += 1
      elsif current =~ /\bexpect\s*[({]/ || current =~ /^\s*\.(to|not_to|to_not)\b/
        asserts << stripped.chomp
      end
      cursor += 1
    end

    found << [ name, idx + 1, asserts, prose ]
  end

  found
end

# Твердження, розбите на два рядки (`expect(x)\n  .to eq(y)`), — одне твердження.
def stitch(asserts)
  asserts.each_with_object([]) do |text, acc|
    if text =~ /^\.(to|not_to|to_not)\b/ && !acc.empty?
      acc[-1] = "#{acc[-1]} #{text}"
    else
      acc << text
    end
  end
end

def kind_of(text)
  MATCHERS.each { |kind, re| return kind if text =~ re }
  return :bare_received if text =~ BARE_RECEIVED && text !~ ARG_MATCHER

  :substantive
end

def weak_kind(asserts)
  return nil if asserts.empty?

  kinds = stitch(asserts).map { |t| kind_of(t) }
  return nil if kinds.include?(:substantive)

  kinds.uniq.one? ? kinds.first : :weak_mix
end

def candidate?(name, asserts)
  return false if name =~ STATUS_NAMED
  return false unless BEHAVIOUR_VERBS.any? { |v| name.downcase.include?(v) }
  # Негативна назва + суцільно негативні твердження = чесний доказ відсутності.
  return false if name =~ NEGATIVE_NAME &&
                  asserts.all? { |t| t =~ /(not_to|to_not)\s/ || t =~ /be_nil|be_falsey|\bbe\(false\)/ }

  true
end

# ── вибір скоупу ─────────────────────────────────────────────────────────────
args = ARGV.dup
mode_all = args.delete("--all")

files =
  if !args.empty?
    args
  elsif mode_all
    Dir[ROOT.join("spec/**/*_spec.rb")].sort
  else
    head = `git -C #{ROOT} rev-parse HEAD 2>/dev/null`.strip
    base = `git -C #{ROOT} merge-base HEAD main 2>/dev/null`.strip
    # ⚠️ На самому `main` (а тут працюють саме так) `merge-base HEAD main` = HEAD,
    # тобто діапазон порожній, і дефолтний режим мовчав би про щойно закомічене —
    # детектор без носія. Фолбек `HEAD~1` мусить ловити САМЕ цей випадок, а не
    # лише порожній вивід: на існуючому `main` команда не фейлиться ніколи.
    range = (base.empty? || base == head) ? "HEAD~1" : base
    changed = `git -C #{ROOT} diff --name-only #{range} 2>/dev/null`.split("\n")
    staged  = `git -C #{ROOT} diff --name-only --cached 2>/dev/null`.split("\n")
    working = `git -C #{ROOT} diff --name-only 2>/dev/null`.split("\n")
    (changed + staged + working).uniq.grep(/spec\/.*_spec\.rb\z/).map { |f| ROOT.join(f).to_s }
  end

files = files.select { |f| File.exist?(f) }

if files.empty?
  puts "spec_claim_audit: у скоупі немає spec-файлів (діф порожній) — нічого міряти."
  puts "Повний корпус: ruby scripts/spec_claim_audit.rb --all"
  exit 0
end

findings = []
prose_lines = 0
example_count = 0

files.each do |path|
  examples_in(path).each do |name, line, asserts, prose|
    example_count += 1
    prose_lines += prose
    kind = weak_kind(asserts)
    next if kind.nil?
    next unless candidate?(name, asserts)

    findings << Finding.new(
      path: path.sub("#{ROOT}/", ""), line: line, name: name, kind: kind, asserts: stitch(asserts)
    )
  end
end

puts "spec_claim_audit (advisory · exit 0 завжди · вердикт у виводі)"
puts "скоуп: #{files.size} файлів · #{example_count} прикладів · #{prose_lines} рядків-коментарів усередині прикладів"
puts

if findings.empty?
  puts "✓ кандидатів немає: у кожного прикладу з дієсловом у назві є хоч одне змістовне твердження."
  exit 0
end

findings.group_by(&:kind).sort_by { |k, _| k.to_s }.each do |kind, group|
  puts "── #{kind} (#{group.size})"
  group.each do |f|
    puts "   #{f.path}:#{f.line}  «#{f.name}»"
    puts "       тверджує лише: #{f.asserts.join(' ; ')[0, 160]}"
  end
  puts
end

puts "КАНДИДАТІВ: #{findings.size} — це ШОРТЛИСТ, не вердикт (див. стелю в шапці)."
puts "Правило-лік: один точний статус + `media_type` + ВМІСТ; коли два коди дає"
puts "два різні МЕХАНІЗМИ — розрізняй їх ціллю, тілом або флешем (`04_06 §B.2` #15/#17)."
exit 0
