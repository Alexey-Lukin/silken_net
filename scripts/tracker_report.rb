#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Advisory-звіти по `00_07` — **НЕ гейти** [DOC-T.92].
#
# Обидва режими нижче стережуть осі, на яких HARD-гейт було ВИМІРЯНО й ВІДМОВЛЕНО, і
# відмова записана, щоб не перевідкривалась:
#
#   · **доступність роботи.** Дискримінатор семантичний: гейт бачив би `🤖`-лід і не
#     бачив би `(demand-gated)` чи «після присуду» в прозі того ж рядка, тож був би
#     бездоганно зеленим над роботою, робити яку заборонено. Вердикт дає READ тіла.
#   · **`🚦 Critical Path`.** Сира точність «архівний ID у рядку Critical Path» — 4 з 14
#     (29%); звужена форма давала 80%, але exclusion-лист виведено ІЗ ТИХ САМИХ 14, тобто
#     in-sample, і числу вірити не можна. Носій лишається advisory + правило в
#     `.claude/prompts/deep_archival.md` («архівуючи ID, грепни його в `🚦`»).
#
# 🔴 **Обидва режими друкують ВЛАСНУ сліпоту ПЕРЕД результатом, і це не ввічливість.**
# Звіт, чиї числа правдиві над КУРОВАНОЮ множиною, є палантіром (`00_05 §7`): Саурон не
# підробив жодного зображення — він керував тим, ЩО показувалось. Тут той самий ризик:
# лічильник «вільних ніг» точний рівно настільки, наскільки повний перелік форм
# відкладення, а той перелік — рукописний.
#
# Pure Ruby, без Rails. Ростер режимів — `case` нижче; читати його, а не цю шапку.
#   ruby scripts/tracker_report.rb --takeable
#   ruby scripts/tracker_report.rb --desk
#   ruby scripts/tracker_report.rb --critical-path
# Exit 0 ЗАВЖДИ (окрім помилки аргументів): це звіт, а не вердикт.

require_relative "../lib/tracker/dashboard"

D = Tracker::Dashboard

# Форми ВІДКЛАДЕННЯ, що трапляються в прозі ноги. Перелік рукописний і саме тому
# друкується читачеві: усе, чого тут немає, порахується ВІЛЬНИМ, тож число «вільних» є
# ВЕРХНЬОЮ межею. Виведено з корпусу (не з голови) — кожна форма має живі входження.
DEFERRAL_FORMS = {
  "demand-gated" => /demand[-\s]?gated/i,
  "після присуду" => /післ\p{L}*\s+(?:⚖️\s*)?присуд/i,
  "після <події>" => /\bпісля\s/i,
  "bench" => /\bbench\b/i,
  "gated" => /gated/i,
  "чекає" => /чека[єю]/i,
  "⛔ у самій нозі" => /⛔/,
  "коли · щойно" => /\b(?:коли|щойно)\s/i,
  "блокується" => /блоку[єʼ']/i,
  "не раніше" => /не раніше/i,
  "потребує" => /потребу[єю]/i,
  "TBD" => /\bTBD\b/,
  # Додано 2026-08-28 після хибного позитиву на `OPS.28`: корпус має ВЛАСНУ форму
  # оголошення відкладення з назвою події, і без неї звіт систематично переоцінює саме
  # ті ноги, які founder свідомо відклав, назвавши пускач.
  "пускач названо" => /пускач/i,
  "(тригер: …)" => /тригер:/i,
  "свідомо не додано" => /свідомо\s+(?:не|НЕ)\b/,
  # Другий хибний позитив того ж проходу (`OPS.36` ×2): нога веде `🤖`, а ТІЛО каже
  # «⚖️ Спершу присуд, чи це взагалі наша нога». Лід і тіло тут стверджують різне, і
  # правий саме останній.
  "спершу присуд" => /спершу\s+(?:⚖️\s*)?присуд/i,
  # Додано 2026-08-31. Дискримінатор був не «скільки спіймає», а «це формулювання чи
  # СЛОВНИК»: `00_05 §5` велить при класі на два інстанси лікувати інстанси, і за самим
  # уловом (2 з 2, точність 100%) форма цей поріг не переходила. Перевагу дав інший
  # вимір — `pre-mainnet` є стоячою назвою одного з найбільших наших гейтів: 14 входжень
  # у 7 пунктах трекера й 11 файлів по канону, скілах і КОДІ (`oracle_signer.rb`,
  # `production.rb`). Тобто фільтр учиться нашого словника, а не купує два рядки.
  # ⛔ Сусідній кандидат `post-scale` ВІДМОВЛЕНО тим самим проходом — рівно ОДИН інстанс
  # (`ARCH.10`) і жодного іншого вжитку в дереві, тобто це формулювання, а не гейт-ім'я;
  # ціна відмови названа: та нога рахується вільною, доки її не перепишуть на «тригер:».
  "pre-mainnet" => /pre-mainnet/i
}.freeze
# ⛔ ГОЛИЙ `тригер` (без двокрапки) ВИМІРЯНО Й ВІДМОВЛЕНО 2026-08-28 — 3 із 5, і промах
# коштує дорожче за улов: `FW.63` — нога ПРО неіснуючий тригер метрики, а не нога, що на
# тригер чекає, тож форма СХОВАЛА б вільну машинну роботу. Асиметрія тут несуча: брак
# форми лише подовжує читання (нога видима, читач відкидає її сам), а зайва форма робить
# роботу НЕВИДИМОЮ, і невидиме ніхто не переміряє. Те саме з `передумов` і `лише при`.
# ⛔ І ГОЛИЙ `⚖️` — 57 хітів, тобто форма сховала б 57 ніг заради двох справжніх: гліф
# у тілі найчастіше ЦИТУЄ вже ухвалений присуд, а не оголошує очікування на новий.
# Дискримінує саме ДЕКЛАРАТИВНА зв'язка («спершу присуд»), не наявність гліфа.

# ── РУКИ: чим САМЕ зайняті `👤`-ноги [2026-09-05, ⚖️ founder] ───────────────────────
#
# 🔑 Питання founder-а було «`👤` відповідає за занадто багато», і вимір відповів
# НЕ так, як очікувалось. Розкол на три (термінал ⊥ стенд ⊥ люди) покриває лише
# **70%** із 277 `👤`-ніг: 15% — мокра лаба (ICP-MS, SEM/µCT, синтези, ферменти,
# 12-тижневі тести), яку жоден із трьох не тримає, а 14% лягають у ДВА одразу.
# Тобто гліфовий розкол викинув би підклас, що його легенда `00_07` уже називає
# окремо («hardware, **лабораторія**, секрети, …»).
#
# 🔴 І головне: `bench` уже має носія (тег `[bench:slug]` + гейт), люди — секцію
# `§00b`. Носія не має РІВНО ОДИН клас — desk, і саме він розмазаний по 12 секціях
# (max 27% в одній). Тобто «перевантажений гліф» був симптомом, а хворобою —
# НЕВИДИМІСТЬ тієї єдиної черги, яку founder може взяти сьогодні, не встаючи.
# Тому лік — цей ЧИТАЧ, а не новий токен (`WHO_CANON` лишається шести-значним,
# гейти не чіпаються; ⛔ не «полагоджувати» це гліфом, вимір відмовлено).
#
# ⛔ **`desk` НЕ детектується позитивно — він ЗАЛИШОК**, і це не лінощі, а чесність:
# спільного словника в «сісти й зробити» немає (KiCad ⊥ ENV-змінна ⊥ RFQ-лист ⊥ абзац
# канону), тож будь-який позитивний перелік був би вужчим за клас і ховав би роботу.
# Ціна форми названа: у залишок падає й те, що просто не має ключових слів сусідів.
HANDS_BUCKETS = {
  "стенд" => /\[bench:|\bbench\b|кремні|стенд[ уі]|осцилограф|PPK2|запая|спая|термокамер|припо/i,
  "лаба" => /ICP-MS|\bSEM\b|µCT|\bEIS\b|\bCV\b|синтез|фермент|Nafion|PTFE|електрод|W[oö]hler|LECO|біореактор|\bгамма\b|стерил/i,
  "люди" => /зустріч|cold contact|first-contact|workshop|воркшоп|sit-down|юрист|повірен|\bNDA\b|\bMoU\b|консультац|методолог|через декана|співрозмов/i
}.freeze

def sections(markdown)
  current = nil
  markdown.each_line.with_object(Hash.new { |h, k| h[k] = [] }) do |line, acc|
    if line.start_with?("## ")
      current = line.match?(D::REGISTRY_SECTION) && !line.match?(D::SKIP_SECTION) ? line[/## (§\S+)/, 1] : nil
      next
    end
    acc[current] << line if current
  end
end

# [section, id, lead, body] для кожної ВІДКРИТОЇ ноги — той самий скоуп, що в
# `item_residuals`; секція додається окремим проходом, бо `item_residuals` її не несе.
def open_legs(markdown)
  by_section = sections(markdown)
  # STAGE живе на meta-рядку ПУНКТА, не на нозі, тож його треба принести сюди окремо:
  # `item_residuals` знає лише ноги. [DOC-T.92, 2026-08-28]
  stages = D.parse(markdown).to_h { |it| [ it.id, it.stage ] }
  D.item_residuals(markdown).flat_map do |it|
    section = by_section.find { |_, lines| lines.any? { |l| l.match(D::ITEM_HEAD)&.captures&.first == it[:id] } }&.first
    it[:open].map { |b| { section:, id: it[:id], stage: stages[it[:id]], lead: b[D::WHO_LEAD].to_s, body: b } }
  end
end

# STAGE'и, під якими пункт СТВЕРДЖУЄ, що зараз його не беруть. [DOC-T.92]
# ⚠️ Це твердження ПУНКТА, а не вимір — саме тому такі ноги не ховаються, а виводяться
# окремим списком: `00_05 §3` фіксує, що STAGE протухає (пункт перепризначили, гліф лишили),
# і сховане під протухлим гліфом ніхто ніколи не перемірює.
NOT_NOW_STAGES = %i[blocked far_horizon vacuous].freeze

def stage_gated?(leg) = NOT_NOW_STAGES.include?(leg[:stage])

def deferred?(body) = DEFERRAL_FORMS.any? { |_, re| body.match?(re) }

def takeable_report(markdown)
  legs = open_legs(markdown)
  unrecognised = legs.reject { |l| l[:lead].empty? || l[:lead].match?(D::WHO_GLYPH) }

  puts "tracker:takeable — ЗВІТ, не гейт. Числа правдиві; МНОЖИНА КУРОВАНА."
  puts
  puts "⚠️  СПЕРШУ ПРО ВЛАСНУ СЛІПОТУ — читати ДО результату:"
  puts "  · гліф-вісь ТОЧНА: словник ліда закритий і гейтований (`residual_lead_form`),"
  puts "    нерозпізнаних лідів зараз #{unrecognised.size}."
  puts "  · проза-вісь ЕВРИСТИЧНА: знає #{DEFERRAL_FORMS.size} форм відкладення (нижче), і все, чого"
  puts "    в переліку НЕМАЄ, рахується ВІЛЬНИМ. Отже «вільних» — це ВЕРХНЯ МЕЖА, ніколи точне число."
  puts "  · `⛔` у `**Стан:**` ПУНКТА фільтр не читає — і це СВІДОМО [DOC-T.92, 2026-08-28]."
  puts "    Прочитано всі 7 пунктів, де `⛔` стоїть у Стані ПРИ вільній нозі: справжньою"
  puts "    забороною роботи виявилась ОДНА, решта — скоуп-нотатки, записи відхилених"
  puts "    опцій і застереження про форму ліку. Символ несе ≥6 значень, тож він тут"
  puts "    слабкий сигнал, а не «найчастіше справжній гейт», як стояло доти."
  puts "  · STAGE ПУНКТА тепер читається — але НЕ фільтрує (стовпчик `∖STAGE` + список нижче)."
  puts "    `00_05 §3`: доступність кодує STAGE пункта, а WHO ноги до неї ортогональний."
  puts "    Ноги під `🔗`/`🌿`/`⚫` НЕ ховаються, бо STAGE протухає (пункт перепризначили,"
  puts "    гліф лишили), а сховане під протухлим гліфом ніхто не перемірює НІКОЛИ."
  puts "  · вердикт «чи цю ногу можна брати» дає READ тіла пункту. Тут — КАНДИДАТИ."
  puts "  · форми, які фільтр знає: #{DEFERRAL_FORMS.keys.join(' · ')}"
  puts

  rows = legs.group_by { |l| l[:section] }.sort_by { |s, _| s.to_s }
  puts format("%-8s %10s %10s %10s %10s %10s", "секція", "гліф", "∖проза", "🤖 гліф", "🤖 ∖проза", "🤖 ∖STAGE")
  totals = Hash.new(0)
  rows.each do |section, ls|
    glyph = ls.count { |l| l[:lead].match?(D::WHO_GLYPH) }
    free  = ls.count { |l| l[:lead].match?(D::WHO_GLYPH) && !deferred?(l[:body]) }
    mglyph = ls.count { |l| l[:lead].include?("🤖") }
    mfree  = ls.count { |l| l[:lead].include?("🤖") && !deferred?(l[:body]) }
    mstage = ls.count { |l| l[:lead].include?("🤖") && !deferred?(l[:body]) && !stage_gated?(l) }
    totals[:glyph] += glyph
    totals[:free] += free
    totals[:mglyph] += mglyph
    totals[:mfree] += mfree
    totals[:mstage] += mstage
    puts format("%-8s %10d %10d %10d %10d %10d", section, glyph, free, mglyph, mfree, mstage)
  end
  puts format("%-8s %10d %10d %10d %10d %10d", "УСЬОГО",
              totals[:glyph], totals[:free], totals[:mglyph], totals[:mfree], totals[:mstage])
  puts
  ratio = totals[:mfree].zero? ? nil : (totals[:mglyph].to_f / totals[:mfree])
  puts "🔑 Множник завищення по `🤖`-осі: #{ratio ? format('×%.1f', ratio) : 'н/д'} — тобто скан за самим гліфом"
  puts "   бачить у стільки разів більше машинної роботи, ніж лишається після прози. Число"
  puts "   є ВЛАСТИВІСТЮ ЗРІЗУ: по секціях воно різне, тож цитувати його можна лише з прогону."
  puts "   ⚠️ ОДИНИЦЯ — НОГА, не пункт. Множник, порахований по ПУНКТАХ (скільки items несуть"
  puts "   сольний `🤖` проти скількох справді вільні), — інше число над іншою множиною; два"
  puts "   такі множники правдиві одночасно й НЕ взаємозамінні."
  puts

  dry = rows.reject { |_, ls| ls.any? { |l| l[:lead].match?(D::WHO_GLYPH) && !deferred?(l[:body]) } }
  if dry.empty?
    puts "Секцій, де після прози не лишилось ЖОДНОЇ вільної ноги: немає."
  else
    puts "Секції, де після прози не лишилось ЖОДНОЇ вільної ноги (#{dry.size}): #{dry.map(&:first).join(', ')}"
  end

  by_item = legs.group_by { |l| l[:id] }
  stuck = by_item.reject { |_, ls| ls.any? { |l| l[:lead].match?(D::WHO_GLYPH) && !deferred?(l[:body]) } }
  puts "Пунктів, де `гліф ∖ проза` = 0 (усе відкрите виглядає відкладеним): #{stuck.size}"
  stuck.keys.sort.each_slice(12) { |s| puts "  #{s.join(' · ')}" }
  puts

  # 🔴 Розходження `∖проза` ⊥ `∖STAGE` — це НЕ шум і не подвійний облік: воно має рівно
  # дві причини, і вони протилежні за знаком. Або STAGE правий (нога справді не на часі,
  # і проза цього не сказала), або STAGE протух (пункт перепризначили, гліф лишили) — і
  # тоді це найдорожчий клас, бо робота є, а її не видно ЖОДНОМУ скану. Розсудити може
  # лише READ, тож список друкується поіменно замість того, щоб мовчки відняти число.
  conflicted = legs.select { |l| l[:lead].include?("🤖") && !deferred?(l[:body]) && stage_gated?(l) }
  if conflicted.empty?
    puts "Ніг, вільних за гліфом+прозою, але під STAGE `🔗`/`🌿`/`⚫`: немає."
  else
    grouped = conflicted.group_by { |l| l[:id] }
    puts "🤖-ніг, вільних за гліфом+прозою, але під STAGE `🔗`/`🌿`/`⚫`: #{conflicted.size} " \
         "у #{grouped.size} пунктах."
    puts "  Кожен — розвилка: STAGE правий (гейт у гліфі, не в прозі) АБО STAGE протух."
    grouped.sort_by { |id, _| id }.each do |id, ls|
      puts format("  · %-12s %s × %d", id, D::STAGES.key(ls.first[:stage]) || "?", ls.size)
    end
  end
end

def hands_buckets(body) = HANDS_BUCKETS.select { |_, re| body.match?(re) }.keys

def desk_report(markdown)
  legs = open_legs(markdown).select { |l| l[:lead].include?("👤") }
  classified = legs.map { |l| l.merge(buckets: hands_buckets(l[:body])) }
  desk = classified.select { |l| l[:buckets].empty? }
  multi = classified.select { |l| l[:buckets].size > 1 }
  lab = classified.select { |l| l[:buckets] == [ "лаба" ] }
  # 🔴 `🟢` СЮДИ НЕ ВХОДИТЬ, і це не та сама межа, що в `--takeable`. Легенда:
  # `🟢` = «host/код done, чекає bench-фліпу або активації ЗА ГЕЙТОМ» — тобто пункт
  # САМ стверджує, що робота зроблена, а лишилась подія. Пустити його в «зараз»
  # означало б завищити чергу вдвічі (виміряно на першому прогоні: 127 проти 58
  # ручного відліку) — і завищена черга гірша за відсутню, бо її перестають читати.
  not_now = NOT_NOW_STAGES + [ :done_inert ]
  now = desk.reject { |l| deferred?(l[:body]) || not_now.include?(l[:stage]) }

  puts "tracker:desk — ЗВІТ, не гейт. Кандидати «за ноутбуком», НЕ вердикт."
  puts
  puts "⚠️  СПЕРШУ ПРО ВЛАСНУ СЛІПОТУ — читати ДО результату:"
  puts "  · `desk` тут — ЗАЛИШОК, а не знахідка: нога, що не впізналась ані стендом,"
  puts "    ані лабою, ані людьми. Спільного словника в «сісти й зробити» не існує,"
  puts "    тож позитивний перелік був би вужчим за клас і ХОВАВ би роботу."
  puts "    Ціна: у залишок падає й те, що просто не має ключових слів сусідів."
  puts "  · три кошики покривають ~70% корпусу `👤`-ніг (вимір 2026-09-05). Ноги, що"
  puts "    лягають у ДВА одразу, виводяться окремо — гліф двох значень не тримає."
  puts "  · мокра ЛАБА — власний клас, не підвид стенда: #{lab.size} ніг. Легенда `00_07`"
  puts "    називає «лабораторія» окремо від «hardware», тож трійка її б викинула."
  puts "  · проза-вісь та сама, що в `--takeable` (#{DEFERRAL_FORMS.size} форм відкладення),"
  puts "    тож «доступно зараз» — ВЕРХНЯ межа, ніколи точне число."
  puts "  · STAGE пункта ТУТ фільтрує ШИРШЕ, ніж у `--takeable`: окрім `🔗`/`🌿`/`⚫`"
  puts "    відсікається ще й `🟢` — пункт САМ каже, що код готовий і чекає ГЕЙТА."
  puts "    не «де вся робота», а «що взяти НЕ ВСТАЮЧИ». Ціна названа: нога під"
  puts "    протухлим `🔗`/`🌿` звідси зникне — саме тому `--takeable` її НЕ ховає."
  puts

  puts format("%-8s %8s %8s %8s %8s %8s", "секція", "👤", "стенд", "лаба", "люди", "🖥 зараз")
  totals = Hash.new(0)
  classified.group_by { |l| l[:section] }.sort_by { |s, _| s.to_s }.each do |section, ls|
    row = {
      all: ls.size,
      bench: ls.count { |l| l[:buckets].include?("стенд") },
      lab: ls.count { |l| l[:buckets].include?("лаба") },
      people: ls.count { |l| l[:buckets].include?("люди") },
      now: ls.count { |l| now.include?(l) }
    }
    row.each { |k, v| totals[k] += v }
    puts format("%-8s %8d %8d %8d %8d %8d", section, *row.values_at(:all, :bench, :lab, :people, :now))
  end
  puts format("%-8s %8d %8d %8d %8d %8d", "УСЬОГО", *totals.values_at(:all, :bench, :lab, :people, :now))
  puts

  puts "🖥  ЗА НОУТБУКОМ — #{now.size} ніг у #{now.map { |l| l[:id] }.uniq.size} пунктах:"
  now.group_by { |l| l[:section] }.sort_by { |s, _| s.to_s }.each do |section, ls|
    ls.each { |l| puts format("  %-6s %-12s %s", section, l[:id], l[:body].gsub(/\s+/, " ")[0, 96]) }
  end
  puts

  if multi.any?
    puts "⊥ Ноги у ДВОХ кошиках одразу (#{multi.size}) — гліф їх не закодує, тег закодує:"
    multi.group_by { |l| l[:id] }.sort_by { |id, _| id }.each do |id, ls|
      puts format("  · %-12s %s", id, ls.map { |l| l[:buckets].join("+") }.tally.map { |k, v| v > 1 ? "#{k}×#{v}" : k }.join(" · "))
    end
  end
end

def critical_path_report(markdown)
  live = D.parse(markdown).map(&:id).to_set
  all  = D.all_item_ids(markdown).to_set
  archived = all - live

  in_cp = []
  in_section = false
  markdown.each_line do |line|
    if line.start_with?("## ")
      in_section = line.start_with?("## 🚦")
      next
    end
    next unless in_section

    line.scan(/(?<![A-Za-z0-9_])([A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*[.\-][0-9A-Za-z.\-]+)/) do |id,|
      in_cp << id.sub(/[.\-]+\z/, "")
    end
  end
  in_cp.uniq!

  puts "tracker:critical-path — ЗВІТ, не гейт. Кандидати, НЕ вердикт."
  puts
  puts "⚠️  ВЛАСНА СЛІПОТА, названа першою:"
  puts "  · сира точність цієї осі ВИМІРЯНА і низька — 4 справжні з 14 (29%). Більшість"
  puts "    цитувань архівного ID у `🚦` законні: корпус посилається на закриті пункти як на"
  puts "    ПРОВЕНАНС («ex-…», «поглинув …»), і це не борг."
  puts "  · звужену форму (80%) відхилено, бо exclusion-лист був виведений із ТІЄЇ САМОЇ"
  puts "    чотирнадцятки — in-sample, тобто число описує підгонку, а не точність."
  puts "  · тому це advisory назавжди; правило-носій живе в `.claude/prompts/deep_archival.md`."
  puts

  hits = in_cp.select { |id| archived.include?(id) }.sort
  puts "ID у `🚦 Critical Path`: #{in_cp.size} · з них архівних: #{hits.size}"
  puts
  if hits.empty?
    puts "Архівних ID у рядках Critical Path не знайдено."
  else
    puts "Кандидати (кожен ЧИТАТИ очима — інваріант «закритий елемент ВИПАДАЄ з рядка»):"
    hits.each { |id| puts "  · #{id}" }
  end
end

MODE = ARGV.find { |a| a.start_with?("--") } || "--takeable"
md = File.read(D::DEFAULT_PATH)

case MODE
when "--takeable"      then takeable_report(md)
when "--desk"          then desk_report(md)
when "--critical-path" then critical_path_report(md)
else
  warn "невідомий режим #{MODE}. Ростер: --takeable · --desk · --critical-path"
  exit 2
end
