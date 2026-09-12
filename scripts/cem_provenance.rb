#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Де кожне число в `tools/cad/cem/*.json` взялося — HARD-гейт [HW.48], wired у `docs.yml`.
#
# ⚖️ Ратифіковано founder 2026-09-12 («я за Сковороду: потрібне зробив неважким, а важке — непотрібним»):
# повну вимого-керовану інверсію CEM ВІДХИЛЕНО; береться носій ПІДСТАВИ поруч зі значенням. Цей скрипт —
# перша його половина: він вимагає, щоб КОЖНЕ число несло оголошену підставу, і червоніє на тому, що не несе (⚠️ рядок доти казав «міряє, скільки… і називає ті, що не мають» — опис advisory-ери, що пережив фліп у HARD на чотири рядки нижче).
#
# 🔴 Чому це не косметика, і ціна виміряна: за один день 2026-09-12 той самий клас коштував тричі —
#   · `L_FREE_UNSUP = 36` розкладала себе в коментарі так, що читалась деривованою, і не була (HW.34);
#   · `gyroid_wall_param` пережив фліп топології, де токен означає інше, і мовчки дав 50 % замість 65 % (HW.33);
#   · `rf_clearance_min_mm = 12` роками дзеркалив ДИЗАЙН-ТОЧКУ як підлогу, і перевірка ловила АДРЕСУ
#     канон-рядка, ніколи його КЛАУЗУ.
# Спільна форма: параметр не носить власної підстави, тож його розходження з нею не має де почервоніти.
#
# Класи (вони і є предметом виміру):
#   requirement — вимога ззовні, яку ми не обирали (CODIT-рана, DIN/ISO-таблиця, підлога вендора)
#   derived     — виведене розрахунком; `from:` мусить назвати, ЧИМ саме
#   design      — дизайн-точка / робочий приклад, що затвердів у число; законно, але мусить бути названо
#   placeholder — ще не рішення; чекає стенду, RFQ або присуду
#   superseded  — присуд зняв цю гілку, застосування не приїхало; число стоїть і не є чинним рішенням
#
# ⊕ `canon_ground: false` — ОРТОГОНАЛЬНИЙ до класу прапорець, доданий 2026-09-12 разом із повнотою:
#   клас каже, ЯКОГО РОДУ число, а цей прапорець — що підстави в дереві НЕМА взагалі. Виміряно на
#   радомі й фланці: кількість вушок байонета · радіус вушка (обидва — В ОБОХ деталях, дзеркальна
#   пара, і доти прапорець стояв лише на радомній половині, тобто гейт кричав про число, якого цех
#   не побачить, і мовчав про те, яке побачить) · зазор сокета · висота порожнини · допуск Ø купона
#   (у семи `ti_coin`-варіантах). Канон їх не називає ніде або цитує НАЗАД із CEM (коловий реф).
#   ⛔ Числа тут немає свідомо: його дає прогін, і воно вже двічі було хибним у прозі. ⛔ Записані просто як `design`, вони
#   читаються чинними рішеннями, і гейт зеленіє над числами, що ДРУКУЮТЬСЯ на заводському DXF.
#   Тому відсутність оголошується булевим, а не прозою, і несе обовʼязок: `from:` мусить назвати
#   пункт трекера, що володіє закриттям. Дефолт за відсутності ключа — TRUE.
#   ⛔ **І ця форма СЛАБКА — названо вголос після адверсарного ревʼю 2026-09-12, бо доти тут стояло
#   «мовчазний пропуск не купує звільнення», а механізм робить рівно протилежне:** обовʼязок несе
#   лише ЯВНИЙ `false`, тож непозначене число без підстави проходить зеленим і в жодному переліку не
#   зʼявляється. Сувора форма існує (`!= true` з обовʼязковим явним `true`) і не взята свідомо: вона
#   зробила б червоними всі поля до ручного проходу по кожному, тобто постійно червоний гейт.
#
# ⚖️ ADVISORY → HARD 2026-09-12: настала передумова, яку цей файл сам і записав — класифікація ПОВНА.
#    ⛔ Числа полів тут НЕ наводиться, і це куплено того ж дня: у першій редакції стояло «172 поля»,
#    виміряних ВЛАСНИМ периметром гейта, який тоді не бачив масивів — справжніх було 186. Тобто
#    лічильник-передумова HARD-фліпу був неправдивий, і жоден пін його не тримав. Число дає прогін.
#    Доти exit 1 був би постійно червоним над невиміряною множиною, а
#    постійно червоний гейт учить читача гортати єдиний рядок, що має лишатись гучним (00_05 §5).
# ⛔ Оголошена стеля, і вона гейтом НЕ закривається за побудовою: судиться НАЯВНІСТЬ підстави — клас,
#    непорожній `from:`, резолв канон-адреси, власник для `canon_ground: false`. ПРАВДИВІСТЬ підстави
#    не судиться нічим: `from: «канон 01_01 §5.2»` зеленіє однаково, чи там те число, чи інше.
#
#   ruby scripts/cem_provenance.rb            # гейт: exit 0/1, повний звіт у виводі
#   ruby scripts/cem_provenance.rb --missing  # worklist некласифікованих по файлах, exit 0 ЗАВЖДИ

require "json"

ROOT = File.expand_path("..", __dir__)
CEM_DIR = File.join(ROOT, "tools", "cad", "cem")
PROV_FILE = File.join(CEM_DIR, "_provenance.json")
# ⛔ П'ятий клас доданий 2026-09-12 і він НЕ про походження, а про те, що для читача маніфесту
#    дорожче за походження: значення, чию гілку присуд УЖЕ ЗНЯВ, а застосування не приїхало.
#    Живий взірець — `o_ring_groove_depth_mm` у фланці й радомі: ⚖️ 2026-09-10 поставив ОДИН паз
#    1.344 проти ПЛАСКОЇ кромки, а відвантажена пара зустрічних 0.9 дає стиск −1.1 %, тобто не
#    ущільнює. Без цього класу таке число читається як «design» — тобто як чинне рішення.
CLASSES = %w[requirement derived design placeholder superseded].freeze
SKIP_KEYS = %w[kind name].freeze

# 🔴 ARRAYS RECURSE TOO, and the omission was this gate's own worst blindness — found by
#    adversarial review 2026-09-12, hours after the gate was flipped to HARD. The first version
#    handled `Hash` and `Numeric` and dropped `Array` in SILENCE, so `tolerances.features[…]`
#    in the seven `ti_coin` manifests was invisible: **14 numeric values, and they are per-feature
#    `plus_mm`/`minus_mm` that `Drawing.cs` renders into the PMI block.** So the one class of number
#    the gate's own justification calls untouchable — «prints on the factory drawing» — was exactly
#    the class it could not see, and «classification is COMPLETE» had been measured with the gate's
#    OWN perimeter. That is the self-answering perimeter `00_06 §3` warns about, committed inside
#    the instrument built against it. ⛔ Index the element by `[i]` so a record addresses one
#    feature, not the array.
def numeric_fields(obj, prefix = "")
  obj.each_with_object({}) do |(k, v), acc|
    next if k.start_with?("_") || SKIP_KEYS.include?(k)

    path = "#{prefix}#{k}"
    case v
    when Hash then acc.merge!(numeric_fields(v, "#{path}."))
    when Array
      v.each_with_index do |el, i|
        case el
        when Hash then acc.merge!(numeric_fields(el, "#{path}[#{i}]."))
        when Numeric then acc["#{path}[#{i}]"] = el
        end
      end
    when Numeric then acc[path] = v
    end
  end
end

# Вкладені маніфести (assembly / axial_stack) несуть ЧУЖУ деталь під власним ключем, тож підстава
# живе у kind тієї деталі, не в їхньому. ⛔ Без цього вони читаються «некласифікованими» там, де
# класифіковано рівно те саме число — хибна порожнеча, яка б роздувала борг звіту.
NESTED_KIND = {
  "zone1" => "anchor_zone1",
  "zone2" => "zone2_sleeve",
  "flange" => "cathode_flange",
  "radome" => "radome",
  "capsule" => "anchor_assembly"
}.freeze

def nested_entry(rules, field)
  parts = field.split(".")
  return nil if parts.size < 2

  leaf = parts.last
  owner = parts[0..-2].reverse.find { |seg| NESTED_KIND.key?(seg) }
  return nil unless owner

  rules.dig(NESTED_KIND[owner], leaf)
end

prov = File.exist?(PROV_FILE) ? JSON.parse(File.read(PROV_FILE)) : {}
rules = prov["fields"] || {}

rows = []
Dir.glob(File.join(CEM_DIR, "*.json")).sort.each do |path|
  next if File.basename(path).start_with?("_")

  doc = JSON.parse(File.read(path))
  kind = doc["kind"]
  name = doc["name"]
  # ⛔ A sibling in cem/ that declares no `kind` is NOT a manifest — the regression baselines
  #    (`*.golden.json`, Golden.cs) live here on purpose, beside the CEM they pin. Скіпати їх треба
  #    по ВІДСУТНОСТІ kind, а не по імені: наступний сусід може зватись інакше. 🔴 Виміряно на собі
  #    2026-09-12 — без цього рядка звіт рахував 27 «маніфестів» замість 20 і ПАДАВ на sort (nil
  #    у ключі), тобто новий артефакт мовчки вбив сусідній прилад.
  next if kind.nil? || kind.empty?
  numeric_fields(doc).each do |field, value|
    # 🔴 The `name` tier is FIRST, and the inventory is what forced it (2026-09-12, HW.48): one `kind`
    #    can cover two DIFFERENT PARTS whose numbers have different provenance, and a kind-level record
    #    cannot say so. Live case — `mechanical_lock`: the Zone-1 shank Ø11 is a FROZEN founder dim
    #    (HW.33) while the Zone-3 shank Ø9 is an HW.8 PLACEHOLDER, and its bore is 0 (a sentinel for
    #    «solid, the bus IS the core») against Zone-3's real Ø1.35 channel. Recording one class for both
    #    would have promoted a placeholder to a decision or demoted a freeze to a guess — in a manifest
    #    that PRINTS on the factory DXF. ⛔ So: `name` overrides `kind`, `kind` overrides `*`, and a
    #    kind-level record stays the right home wherever the two parts genuinely share a ground.
    entry = rules.dig(name, field) || rules.dig(kind, field) || rules.dig("*", field) ||
            nested_entry(rules, field)
    rows << { file: File.basename(path), kind: kind, name: name, field: field, value: value, entry: entry }
  end
end

missing = rows.reject { |r| r[:entry] }
bad_class = rows.select { |r| r[:entry] && !CLASSES.include?(r[:entry]["class"]) }
# ⛔ `from` is required for EVERY class, not only `derived`. The original check asked it of `derived`
#    alone, on the reading that only a computed number owes an input — but a `design` or `requirement`
#    without a ground is a bare assertion, and this file exists precisely because bare assertions
#    travel (`rf_clearance_min_mm` was a «design» nobody could trace). Measured before flipping the
#    gate: zero entries lacked `from`, so widening it costs nothing today and refuses the next one.
no_from = rows.select { |r| r[:entry] && r[:entry]["from"].to_s.strip.empty? }
# A `from` that names a canon doc must name one that EXISTS. ⛔ Declared ceiling, and it is the same
# one the header states: this resolves the ADDRESS, never the CLAUSE — the `rf_clearance_min_mm` defect
# cited a real section whose normative row said something else, and no regex can see that. What it does
# catch is the address dying under a doc split or renumber, which has happened to this repo.
DOC_ID = /\b(\d\d_\d\d)\b/
def doc_exists?(id) = !Dir.glob(File.join(ROOT, "docs", "#{id}_*.md")).empty?
dead_ref = rows.select { |r| r[:entry] }
               .flat_map { |r| r[:entry]["from"].to_s.scan(DOC_ID).flatten.uniq.map { |id| [ r, id ] } }
               .reject { |_, id| doc_exists?(id) }
# 🔴 THE AXIS THIS GATE WOULD HAVE BEEN BLIND TO, and it is the whole reason the inventory was worth
#    doing: a number can be classified and still have NO GROUND ANYWHERE. Measured on the radome
#    2026-09-12 — four of eleven fields (lug COUNT, lug radius, socket clearance, cavity height) have
#    no canon clause at all; canon either never states them or quotes them BACK from the CEM. Recorded
#    as `design` they read as legitimate decisions and the gate goes green over four numbers that
#    PRINT ON THE FACTORY DXF. ⛔ So the absence is DECLARED as a boolean, never left to prose, and it
#    carries a duty: an undocumented shipped number must name the tracker item that owns closing it.
#    ⛔ DECLARED CEILING on that axis, and it is the weakest of the five: the check is a REGEX for a
#    tracker-shaped token anywhere in the string, so the item that merely MEASURED the absence
#    (HW.48) satisfies it, and so would an incidental match. It refuses a blank, never a wrong owner.
#    because without an owner that is how it stays undocumented. Default when the key is absent is
#    TRUE — a silent omission must not buy the exemption.
TRACKER_ID = /\b(?:HW|ARCH|FW|SEC|E|INF|OPS|BIZ|UNI|DOC-T|S\d|STK|INS|SLASH|MRV|GOV|DR|DEPLOY|TEST|I18N|UI|PERF|CHEM|SILENCE)[.\-]?\d+/
ungrounded = rows.select { |r| r[:entry] && r[:entry]["canon_ground"] == false }
ownerless = ungrounded.reject { |r| r[:entry]["from"].to_s.match?(TRACKER_ID) }

if ARGV.include?("--missing")
  missing.group_by { |r| r[:file] }.sort.each do |file, list|
    puts "#{file}:"
    list.sort_by { |r| r[:field] }.each { |r| puts "  #{r[:field]} = #{r[:value]}" }
  end
  exit 0
end

puts "cem_provenance — HARD-гейт [HW.48]: exit 1, якщо бодай одне число не має оголошеної підстави."
puts
puts "⚠️  ВЛАСНА СЛІПОТА, названа першою:"
puts "  · скрипт судить НАЯВНІСТЬ оголошеної підстави, ніколи її ПРАВДИВІСТЬ. `from: «канон 01_01 §5.2»`"
puts "    зеленіє однаково, чи там справді це число, чи інше — рівно та помилка, що коштувала нам"
puts "    `rf_clearance_min_mm` (перевіряли АДРЕСУ, не КЛАУЗУ)."
puts "  · класифікація рукописна, тож «design» і «placeholder» розрізняє людина, а не вимір."
puts "  · поле-дитина успадковує запис від `kind` батька; вкладені маніфести (assembly/axial_stack)"
puts "    тому можуть читатись класифікованими там, де класифіковано ІНШУ деталь."
puts "  · `name` перекриває `kind`, тож дві деталі одного kind можуть нести різні підстави — але сам"
puts "    вибір яруса рукописний: запис на `kind` там, де провенанс РІЗНИЙ, зеленіє однаково."
puts

by_class = rows.group_by { |r| r[:entry] ? r[:entry]["class"] : "НЕ КЛАСИФІКОВАНО" }
puts format("%-20s %s", "клас", "входжень")
puts "-" * 34
(CLASSES + [ "НЕ КЛАСИФІКОВАНО" ]).each do |c|
  n = (by_class[c] || []).size
  puts format("%-20s %5d", c, n) if n.positive?
end
puts "-" * 34
puts format("%-20s %5d  (унікальних імен полів: %d · маніфестів: %d)",
            "УСЬОГО", rows.size, rows.map { |r| r[:field] }.uniq.size,
            rows.map { |r| r[:file] }.uniq.size)

unless no_from.empty?
  puts
  puts "🔴 підстава ПОРОЖНЯ — клас оголошено, `from:` ні (#{no_from.size}):"
  no_from.group_by { |r| [ r[:kind], r[:field] ] }.keys.sort.each { |k, f| puts "  #{k}.#{f}" }
end

# 🔴 Loud, counted, and ABOVE the verdict — this is the set a reader must see even on a green run.
unless ungrounded.empty?
  puts
  names = ungrounded.group_by { |r| [ r[:name] || r[:kind], r[:field] ] }
  puts "🔴 БЕЗ КАНОННОЇ ПІДСТАВИ (#{ungrounded.size} входжень у #{names.size} полях) — оголошено `canon_ground: false`:"
  puts "   Це НЕ провал гейта: відсутність задекларована й має власника. Це черга на закриття,"
  puts "   і кожне з цих чисел ДРУКУЄТЬСЯ на заводському кресленні."
  names.keys.sort.each { |k, f| puts "  #{k}.#{f}" }
end

unless ownerless.empty?
  puts
  puts "🔴 `canon_ground: false` БЕЗ ВЛАСНИКА (#{ownerless.size}) — незадокументоване число без пункту трекера:"
  ownerless.group_by { |r| [ r[:name] || r[:kind], r[:field] ] }.keys.sort.each { |k, f| puts "  #{k}.#{f}" }
end

unless dead_ref.empty?
  puts
  puts "🔴 `from:` цитує канон-док, якого НЕМА в `docs/` (#{dead_ref.size}):"
  dead_ref.group_by { |r, id| [ r[:kind], r[:field], id ] }.keys.sort.each { |k, f, id| puts "  #{k}.#{f} → #{id}" }
end

unless bad_class.empty?
  puts
  puts "🔴 невідомий клас (#{bad_class.size}) — дозволені: #{CLASSES.join(' · ')}"
  bad_class.group_by { |r| [ r[:kind], r[:field] ] }.keys.sort.each { |k, f| puts "  #{k}.#{f}" }
end

unless missing.empty?
  puts
  names = missing.group_by { |r| [ r[:kind], r[:field] ] }
  puts "НЕ КЛАСИФІКОВАНІ (#{missing.size} входжень у #{names.size} парах kind.field) — `--missing` дає по файлах:"
  names.keys.sort.first(40).each { |k, f| puts "  #{k}.#{f}" }
  puts "  …" if names.size > 40
end

# ── Вердикт [HW.48] ──────────────────────────────────────────────────────────────────────────
# ⚖️ Перекинуто з advisory у HARD 2026-09-12, бо настала передумова, яку сам цей файл записав:
# класифікація ПОВНА. Доти exit 1 був би постійно червоним над невиміряною множиною, а постійно
# червоний гейт учить читача гортати єдиний рядок, що має лишатись гучним (00_05 §5).
# ⛔ Що гейт судить: НАЯВНІСТЬ підстави, її клас, непорожність `from:` і резолв канон-адреси.
#    Чого НЕ судить — ПРАВДИВІСТЬ підстави; ця стеля оголошена в шапці й гейтом не закривається
#    за побудовою (рівно та помилка, що коштувала `rf_clearance_min_mm`: адреса, не клауза).
fails = { "без підстави" => missing.size, "невідомий клас" => bad_class.size,
          "порожній from" => no_from.size, "мертвий канон-реф" => dead_ref.size,
            "без власника" => ownerless.size }.reject { |_, n| n.zero? }
if fails.empty?
  puts
  puts "✅ кожне числове поле кожного маніфесту має оголошену підставу з класом і непорожнім `from:`."
    puts "   ⚠️ #{ungrounded.size} із них оголошують `canon_ground: false` — підстави в дереві немає, власник названий (список ↑)." unless ungrounded.empty?
  exit 0
end
puts
puts "❌ FAIL — #{fails.map { |k, n| "#{k}: #{n}" }.join(' · ')}"
exit 1
