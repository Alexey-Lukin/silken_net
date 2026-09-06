#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [S2.2/S2.3/FW.18b] One-command імпорт Grafana IaC у Grafana Cloud.
#
# Замінює багатокроковий ручний шлях (UI-кліки + curl із плейсхолдерами):
#   GRAFANA_URL=https://<stack>.grafana.net GRAFANA_API_TOKEN=<token> \
#     ruby deploy/grafana/import.rb
#
# Робить:
#   1. Авто-виявлення UID Prometheus datasource (або ENV DATASOURCE_UID).
#   2. Folder "SilkenNet" (створює, якщо нема; або ENV GRAFANA_FOLDER).
#   3. Дашборд: POST /api/dashboards/import з ПРАВИЛЬНИМ wrapper'ом
#      ({dashboard, overwrite, inputs: [DS_PROMETHEUS → uid]}) — голий JSON
#      без inputs datasource не прив'язує.
#   4. Alert rules: підстановка ${DATASOURCE_UID} У ПАМ'ЯТІ (репо-файл не
#      чіпається) → ідемпотентний upsert per-rule через Alerting
#      Provisioning API (POST, при конфлікті uid — PUT) з
#      X-Disable-Provenance (рулі лишаються редагованими в UI) → інтервал
#      групи best-effort через rule-groups endpoint.
#
# `--verify` — READ-ONLY звірка живого стека проти IaC (потребує credentials, нічого
#   не пише): чи всі правила сіли, чи привʼязався datasource, чи немає правил,
#   створених повз репо. Оголошені стелі — у шапці самого режиму. 🔴 Четверта стеля,
#   куплена живим тіком 2026-08-30: --verify НЕ судить, чи ЗБЕРЕЖЕНЕ правило реально
#   ОБЧИСЛЮЄТЬСЯ Ruler-ом — той приймає й неparsабельний SSE-вираз (валідація запису
#   слабша за evaluation; 57 правил без `expression:` у threshold-model пройшли POST
#   і verify зеленими, а перший тік дав [FIRING:57] DatasourceError). Другий інстанс
#   того ж класу (той самий день): relativeTimeRange > ~45 год пробиває Mimir-ліміт
#   11 000 точок/серію — теж зберігається мовчки, падає першим тіком (гейт вікон тепер
#   у grafana_alerts_spec). Після імпорту дивись стан правил через хвилину-дві
#   (alerting/list чи /api/prometheus/grafana/api/v1/rules): мірка = ВСІ оцінені
#   (lastEvaluation != 0001-01-01) І нуль error — health свіжозбереженого правила до
#   першого тіку стоїть «ok» порожнім дефолтом, не вердиктом.
#   🔴 І ця мірка НЕПОВНА — виміряно 2026-09-03, третім дефектом того самого класу:
#   вона правдива лише НАД МЕТРИКАМИ, ЩО МАЮТЬ ДАНІ. Правило над порожньою метрикою
#   звітує `nodata` й читається здоровим, тож вердикт «57/57 evaluated, 0 error» був
#   правдивий у мить виміру й помер САМ, щойно перший живий job-контейнер дав серії:
#   29 із 42 перевірених правил стали Error, 9 із 10 p0-critical. Структурну половину
#   (форма A→B(reduce,last)→C(threshold)) тепер тримає grafana_alerts_spec — вона
#   від наявності даних не залежить; ця ж стрічка лишається про ЖИВИЙ бік, і її
#   треба перезнімати в день, коли метрика оживає.
#
# `--dry-run` — без credentials і без HTTP: валідація форми обох артефактів
# (JSON парситься + DS_PROMETHEUS input; YAML парситься, uid'и унікальні,
# всі datasourceUid = плейсхолдер) + план дій.
#
#   5. Contact point + root notification policy — off-by-default через ENV
#      (ALERT_CONTACT_EMAIL та/або ALERT_CONTACT_TELEGRAM_TOKEN+_CHATID). Без
#      них — пропуск (канал = owner-рішення), але коли задані — кодифікуються,
#      а не клацаються в UI. Без contact point УСІ alert rules firing-ять у
#      нікуди (O3-MUST) — тому це частина One-Command, а не ручний хвіст.

require "json"
require "yaml"
require "net/http"
require "uri"

ROOT           = File.expand_path(__dir__)
DASHBOARD_PATH = File.join(ROOT, "dashboards", "silkennet-overview.json")
ALERTS_PATH    = File.join(ROOT, "alerts", "silkennet-alerts.yaml")
PLACEHOLDER    = "${DATASOURCE_UID}"
DS_INPUT_NAME  = "DS_PROMETHEUS"
RULE_UID_MAX   = 40 # вендорська межа Grafana на uid alert-правила

# Provisioning-API тримає interval групи в СЕКУНДАХ-цілим (`60`), а provisioning-ФАЙЛ —
# рядком-тривалістю (`1m`). Одна величина, дві шкали, і жодна не видна з імені поля.
# 🔴 Виміряно 2026-08-29 на живому стеку: код порівнював `60 != "1m"` — тобто ЗАВЖДИ
# нерівні — і слав рядок, дістаючи 400 на кожному прогоні. Тож warn «інтервал не
# виставився» був хибною тривогою про ПРАВИЛЬНИЙ стан, і ховав би справжнє розходження,
# якби воно колись з'явилось: тривога, що звучить завжди, не звучить ніколи.
def interval_seconds(value)
  return value if value.is_a?(Integer)

  m = value.to_s.match(/\A(\d+)([smh])\z/) or fail! "interval '#{value}': очікую <N>s|m|h або секунди-цілим"
  m[1].to_i * { "s" => 1, "m" => 60, "h" => 3600 }.fetch(m[2])
end

def fail!(msg)
  warn "✗ #{msg}"
  exit 1
end

def step(msg)
  puts "→ #{msg}"
end

# Contact-point integrations з ENV (off-by-default). Half-Telegram → fail-fast.
def contact_integrations(name)
  ints = []
  email = ENV["ALERT_CONTACT_EMAIL"].to_s
  ints << { "name" => name, "type" => "email", "settings" => { "addresses" => email } } unless email.empty?
  token = ENV["ALERT_CONTACT_TELEGRAM_TOKEN"].to_s
  chat  = ENV["ALERT_CONTACT_TELEGRAM_CHATID"].to_s
  fail! "Telegram потребує і ALERT_CONTACT_TELEGRAM_TOKEN, і _CHATID (задано лише одне)" if token.empty? ^ chat.empty?
  ints << { "name" => name, "type" => "telegram", "settings" => { "bottoken" => token, "chatid" => chat } } unless token.empty?
  ints
end

# ---------------------------------------------------------------------------
# Локальна валідація артефактів (працює і в dry-run, і перед live-імпортом)
# ---------------------------------------------------------------------------
def load_dashboard
  dash = JSON.parse(File.read(DASHBOARD_PATH))
  inputs = dash["__inputs"] || []
  ds = inputs.find { |i| i["name"] == DS_INPUT_NAME }
  fail! "#{DASHBOARD_PATH}: нема __inputs #{DS_INPUT_NAME} — import не зможе прив'язати datasource" unless ds
  fail! "#{DASHBOARD_PATH}: порожні panels" if Array(dash["panels"]).empty?
  dash
end

def load_alert_groups
  doc = YAML.safe_load(File.read(ALERTS_PATH))
  groups = doc.fetch("groups") { fail! "#{ALERTS_PATH}: нема груп" }
  uids = groups.flat_map { |g| g["rules"].map { |r| r["uid"] } }
  fail! "#{ALERTS_PATH}: дублікати uid: #{uids.tally.select { |_, c| c > 1 }.keys}" unless uids.uniq == uids
  groups.each do |g|
    g["rules"].each do |r|
      %w[uid title condition data].each do |k|
        fail! "#{ALERTS_PATH}: рул без '#{k}' у групі #{g['name']}" unless r[k]
      end
      # 🔴 Grafana ріже uid alert-правила на 40 символів, і відмова приходить ЛИШЕ з
      # живого API (`400: UID is longer than 40 symbols`) — тобто на етапі, де попередні
      # правила вже записані, а решта черги не поїде. Виміряно 2026-08-29: рул із uid на
      # 43 символи обірвав імпорт після 41-го з 57. Валідатор доти судив УНІКАЛЬНІСТЬ і
      # наявність ключів, а довжину — ні, тож `--dry-run` був зелений на явно нездатному
      # артефакті. ⚠️ Межа ВЕНДОРСЬКА, не наша: міняти її можна лише слідом за Grafana.
      if r["uid"].to_s.length > RULE_UID_MAX
        fail! "#{ALERTS_PATH}: uid '#{r['uid']}' — #{r['uid'].length} символів, " \
              "Grafana приймає щонайбільше #{RULE_UID_MAX} (живий API відмовить 400)"
      end
      r["data"].each do |d|
        next unless d.key?("datasourceUid")
        next if d["datasourceUid"] == PLACEHOLDER || d["datasourceUid"] == "__expr__"

        fail! "#{ALERTS_PATH}: #{r['uid']}: datasourceUid '#{d['datasourceUid']}' — не плейсхолдер і не __expr__"
      end
    end
  end
  groups
end

dashboard = load_dashboard
groups    = load_alert_groups
rule_count = groups.sum { |g| g["rules"].length }

if ARGV.include?("--dry-run")
  puts "✅ dry-run: артефакти валідні"
  puts "   дашборд: #{Array(dashboard['panels']).length} панелей, input #{DS_INPUT_NAME}"
  groups.each { |g| puts "   група #{g['name']}: #{g['rules'].length} рулів, interval #{g['interval']}" }
  puts "   план: discover datasource UID → folder → dashboards/import → #{rule_count}× provisioning upsert"
  cn = ENV.fetch("ALERT_CONTACT_NAME", "silkennet-oncall")
  ints = contact_integrations(cn) # валідує half-Telegram навіть у dry-run
  puts(ints.empty? ? "   contact point: ПРОПУСК (задай ALERT_CONTACT_EMAIL / ALERT_CONTACT_TELEGRAM_TOKEN+_CHATID)" : "   contact point «#{cn}»: #{ints.map { |i| i['type'] }.join(' + ')} → root policy")
  exit 0
end

# ---------------------------------------------------------------------------
# Live-імпорт
# ---------------------------------------------------------------------------
GRAFANA_URL = ENV["GRAFANA_URL"] or fail! "GRAFANA_URL не заданий (https://<stack>.grafana.net)"
TOKEN       = ENV["GRAFANA_API_TOKEN"] or fail! "GRAFANA_API_TOKEN не заданий (service-account token з роллю Editor+)"
FOLDER      = ENV.fetch("GRAFANA_FOLDER", "SilkenNet")

# Resolve the contact-point config UP FRONT so a half-configured channel (Telegram token
# without chat-id) fails BEFORE any dashboard/rules are imported — the live path matches the
# --dry-run pre-check. contact_integrations raises on half-Telegram.
CONTACT_NAME = ENV.fetch("ALERT_CONTACT_NAME", "silkennet-oncall")
integrations = contact_integrations(CONTACT_NAME)

def request(method, path, body: nil, headers: {})
  uri = URI.join(GRAFANA_URL, path)
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(method)
  req = klass.new(uri)
  req["Authorization"] = "Bearer #{TOKEN}"
  req["Content-Type"]  = "application/json"
  headers.each { |k, v| req[k] = v }
  req.body = JSON.generate(body) if body
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
  [ res.code.to_i, res.body.to_s.empty? ? {} : JSON.parse(res.body) ]
rescue JSON::ParserError
  [ res.code.to_i, { "raw" => res.body } ]
rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
  fail! "HTTP #{method.upcase} #{path} → #{e.class}: #{e.message} (перевір GRAFANA_URL / мережу / токен)"
end

# 1. Datasource UID
ds_uid = ENV["DATASOURCE_UID"]
if ds_uid.nil?
  code, list = request(:get, "/api/datasources")
  fail! "GET /api/datasources → #{code}: #{list}" unless code == 200
  proms = list.select { |d| d["type"] == "prometheus" }
  fail! "Prometheus datasource не знайдено — задай DATASOURCE_UID явно" if proms.empty?

  # 🔴 ЧОМУ НЕ `.find` — виміряно на живому стеку 2026-08-29, і промах був би ТИХИЙ.
  # Grafana Cloud віддає КІЛЬКА prometheus-джерел, і біллінгове `grafanacloud-usage`
  # стоїть у списку ПЕРШИМ, тоді як метрики стека живуть у `grafanacloud-<org>-prom`
  # (він же `isDefault`). Перша-ліпша означала б, що всі 57 правил привʼязані до бази,
  # у якій `silkennet_*` не буде НІКОЛИ: вони резолвляться, виглядають здоровими в UI
  # і не спрацьовують ніколи — «конфіг повний, шлях мертвий» у чистому вигляді.
  # ⚠️ Ім'я тут НЕ дискримінатор (денилист на `usage` протух би на першому ж
  # перейменуванні вендором): беремо `isDefault`, а за неоднозначності ВІДМОВЛЯЄМОСЬ —
  # мовчазне вгадування на цьому шляху дорожче за зупинку.
  prom = proms.find { |d| d["isDefault"] } || (proms.one? ? proms.first : nil)
  unless prom
    fail! "Prometheus-джерел кілька і жодне не is-default — задай DATASOURCE_UID явно. " \
          "Кандидати: #{proms.map { |d| "#{d['uid']} (#{d['name']})" }.join(', ')}"
  end
  ds_uid = prom["uid"]
  step "datasource: #{prom['name']} (uid #{ds_uid})#{proms.size > 1 ? " — обрано is-default із #{proms.size} prometheus-джерел" : ''}"
end

# ---------------------------------------------------------------------------
# `--verify` — READ-ONLY звірка живого стека проти IaC. Жодного POST/PUT.
#
# 🔑 Навіщо окремий режим, а не «глянути в UI»: імпорт — це ДІЯ, а «чи вона
# сталась» доти було питанням до ока. Око бачить те, що показує сторінка, і
# систематично сліпе до ЗВОРОТНОГО дрейфу — правила, створеного руками в UI й
# відсутнього в репо. Саме воно й переживе наступний імпорт (upsert per-uid
# чужого uid не чіпає), тобто розходження росте мовчки.
#
# 🔴 ОГОЛОШЕНА СТЕЛЯ — читай як перелік того, чого цей режим НЕ доводить:
#  1. Судиться НАЯВНІСТЬ, ПРИВʼЯЗКА і ЗБІГ ІЗ РЕПО, ніколи ПРАВИЛЬНІСТЬ: поріг
#     може бути безглуздий, `expr` — про сусідню метрику, `description` — точно
#     як у репо й водночас хибний по суті. Той самий паритет-⊥-законність, що в
#     реєстрі метрик (§Guard-craft #74).
#     🔴 [2026-09-06] Ця стеля ЗВУЗИЛАСЬ, і колишнє формулювання коштувало нам
#     двох поколінь тихого дрейфу: доти режим не порівнював АНОТАЦІЙ узагалі, а
#     ратифікована звірка (`spec.expressions…expr` побайтово) давала «✅ паритет»
#     при `description`, старшому за фікс 09-05 — тобто оператор читав «вичерпує
#     кошти» на гаманці, куди ніколи не клали монет, і його слали шукати витік.
#     ⚠️ Вираз ламає СПРАЦЮВАННЯ й помітний; речення ламає ДІЮ ЛЮДИНИ і мовчить.
#  2. Silences / mute timings НЕ читаються: правило може бути присутнє, звʼязане
#     й повністю заглушене — тут це виглядає здоровим.
#  3. Contact point і notification policy НЕ перевіряються: правило може бути
#     ідеальним і firing-ити В НІКУДИ. Це окрема вісь і окреме питання.
#  4. Порожній результат тут — НЕ доказ: якщо стек порожній, «жодного зайвого
#     правила» правдиве й нічого не варте. Дивись на число знайдених.
# ---------------------------------------------------------------------------
if ARGV.include?("--verify")
  code, folders = request(:get, "/api/folders")
  fail! "GET /api/folders → #{code}" unless code == 200
  folder = folders.find { |f| f["title"] == FOLDER }

  code, live = request(:get, "/api/v1/provisioning/alert-rules")
  fail! "GET provisioning/alert-rules → #{code}: #{live}" unless code == 200

  want = groups.flat_map { |g| g["rules"].map { |r| r["uid"] } }
  live_by_uid = live.to_h { |r| [ r["uid"], r ] }
  missing = want - live_by_uid.keys
  extra   = live_by_uid.keys - want

  # Плейсхолдер, що доїхав у стек живим, означає рулі, які НІКОЛИ не спрацюють:
  # запит іде в неіснуючий datasource. Мовчазний клас — у UI воно виглядає як рул.
  unbound = want.filter_map do |uid|
    r = live_by_uid[uid]
    next unless r

    uid if Array(r["data"]).any? { |d| d["datasourceUid"].to_s == PLACEHOLDER }
  end

  puts "── Grafana ⟷ IaC (read-only) ──"
  puts "  folder «#{FOLDER}»: #{folder ? "є (uid #{folder['uid']})" : 'НЕМАЄ'}"
  puts "  datasource: uid #{ds_uid}"
  puts "  правил у IaC: #{want.size} · у стеку всього: #{live.size}"
  puts "  ✓ усі правила IaC присутні" if missing.empty?
  puts "  ✗ ВІДСУТНІ у стеку (#{missing.size}): #{missing.join(', ')}" unless missing.empty?
  puts "  ✓ жодного правила поза IaC" if extra.empty?
  # 🔴 [S2.4, ⚖️ founder 2026-09-05] ТЕКСТ, А НЕ `--prune`, І РІЗНИЦЯ НЕСУЧА.
  # Доти цей рядок звав КОЖНЕ правило поза IaC «створеним руками» — і це
  # неправда за побудовою: імпорт односторонній, тож правило, ЗНЯТЕ з IaC,
  # лишається в стеку й потрапляє в рівно ту саму множину. Ціна помилки не
  # косметична: читач шукав би ЛЮДИНУ там, де відповідь — у git-історії
  # (виміряно на `sn-alert-cluster-entropy`, знятому 09-05: він був
  # IaC-керованим, а diagnostics приписав би його рукам).
  # ⛔ Це НЕ рішення про `--prune` — те свідомо відкладено до ДРУГОГО привида
  # (`00_07` S2.4). Тут виправлено хибне ТВЕРДЖЕННЯ, не додано поведінку:
  # автоматичне видалення й далі відсутнє, бо правило, справді створене
  # руками, формою від знятого з IaC не відрізнити.
  # 🔴 [S2.4, ⚖️ founder 2026-09-06] СИРОТА ТЕПЕР ЧЕРВОНИТЬ — і це третій хід, дешевший
  # за обидва, між якими пункт вибирав. Питання стояло «чи додавати `--prune`»; вимір
  # знаменника сказав ні: за живий період стеку (з 2026-08-29) правила знімали ДВІЧІ,
  # реально осиротіло ОДНЕ, сиріт зараз НУЛЬ — тобто клас має ~1 інстанс на пʼять тижнів,
  # а форма запису не відрізняє справді ручне правило від знятого з IaC, тож автопрун є
  # зарядженою рушницею проти квартальної проблеми.
  #
  # 🔑 **Реальна шкода була не у відсутності видалення, а в тому, що сирота стоїть
  # НЕПОМІЧЕНИМ**: при `noDataState: OK` він зеленіє над порожнечею (саме так прожив
  # `sn-alert-cluster-entropy`). Досить зробити його ЧЕРВОНИМ — накопичення стає
  # неможливим без людського рішення, при НУЛІ руйнівного коду (У-ВЕЙ: потрібне зробили
  # неважким, важке — непотрібним).
  #
  # ⚠️ ЦІНА НАЗВАНА ВГОЛОС, бо у відмови від `--prune` немає червоного, яке про неї
  # нагадає: правило, СПРАВДІ створене руками для діагностики, тепер червонить звірку,
  # доки його не заведуть в IaC або не знімуть. Це стандартна IaC-постава («у теці, якою
  # керує IaC, ручне правило Є дрейфом»), але вона МІНЯЄ операторський контракт — доти
  # `extra` свідомо не валив прогін. ⛔ Не послаблювати назад «щоб не заважало»: саме
  # м'якість цієї гілки й дала привиду прожити непоміченим.
  unless extra.empty?
    puts "  ✗ У СТЕКУ, але НЕ в IaC (#{extra.size}): #{extra.join(', ')}"
    puts "     — або створені руками, або ЗНЯТІ з IaC (імпорт односторонній, нічого не видаляє);"
    puts "     розрізняє це git-історія `deploy/grafana/alerts/`, не цей звіт. Імпорт їх НЕ чіпатиме."
    puts "     Лік — рівно два: завести правило в IaC, або видалити зі стеку руками."
  end
  # Стеля №1 у дії: «плейсхолдера немає» ще НЕ означає «привʼязано куди треба».
  # Тому друкуємо ФАКТИЧНИЙ набір джерел живих правил — рішення лишається читачеві.
  bound = live.flat_map { |r| Array(r["data"]).map { |d| d["datasourceUid"] } }
              .compact.reject { |u| u == "__expr__" }.tally
  puts "  джерела живих правил: #{bound.empty? ? '—' : bound.map { |u, n| "#{u}×#{n}" }.join(', ')}"
  puts "  ⚠ очікуване за автовиявленням: #{ds_uid} — розбіжність означає правила, що не спрацюють НІКОЛИ" \
    unless bound.empty? || bound.keys == [ ds_uid ]
  puts "  ✓ плейсхолдер datasource ніде не лишився" if unbound.empty?
  puts "  ✗ НЕПРИВʼЯЗАНІ (#{unbound.size}): #{unbound.join(', ')} — запит іде в неіснуючий datasource, правило не спрацює НІКОЛИ" unless unbound.empty?

  # 🔴 [S2.4, 2026-09-06] ЧЕТВЕРТА вісь — ТЕКСТ, ЯКИЙ ЧИТАЄ ОПЕРАТОР, і вона додана
  # тому, що її відсутність ВИМІРЯНА, а не уявлена. Ратифікована форма звірки
  # порівнювала `spec.expressions.{refId}.model.expr` побайтово й давала «✅ паритет»,
  # тоді як живий стек ніс `description` ДВОХ ПОКОЛІНЬ давнини: правку 09-05
  # («нуль ≠ вичерпання» — текст казав «вичерпує кошти» на непоповненій адресі й слав
  # оператора шукати витік, якого немає) не імпортували НІКОЛИ, і зелений verify це
  # покривав. Тобто найдорожчий дрейф тут не в виразі, а в реченні: вираз ламає
  # спрацювання й помітний, речення ламає ДІЮ ЛЮДИНИ і мовчить.
  #
  # ⚖️ Порівнюємо лише ключі, ОГОЛОШЕНІ в IaC: Grafana доливає власні анотації
  # (`__dashboardUid__`, `__panelId__`), і рівність повних мап дала б вічно-червоне
  # на порожній підставі — рівно та форма, що привчає скіпати вердикт.
  # ⚠️ `for` порівнюється ЧЕРЕЗ `interval_seconds`, не рядком — Grafana НОРМАЛІЗУЄ
  # тривалість (`0m` у IaC приїжджає назад як `0s`), тож наївна рівність рядків
  # червонила б на ЧЕСНОМУ дереві. Спіймано першим же прогоном цієї осі: 9 правил
  # «розійшлись по `for`» при побайтово однаковій семантиці — класика гейта, що
  # падає на КОРЕКТНОМУ вжитку ([`00_05 §4`](../../docs/00_05_AI_Native_Operating_Model.md)).
  # Решта полів — енуми (`OK`/`NoData`/`Error`), там нормалізації немає.
  ANNOTATION_KEYS = %w[summary description runbook_url].freeze
  ENUM_KEYS       = %w[noDataState execErrState].freeze

  iac_by_uid = groups.flat_map { |g| g["rules"] }.to_h { |r| [ r["uid"], r ] }
  text_drift = want.filter_map do |uid|
    live_rule = live_by_uid[uid]
    iac_rule  = iac_by_uid[uid]
    next unless live_rule && iac_rule

    diff = ANNOTATION_KEYS.select do |k|
      iac_rule.dig("annotations", k) && iac_rule.dig("annotations", k) != live_rule.dig("annotations", k)
    end
    diff += (iac_rule["labels"] || {}).keys.select { |k| iac_rule["labels"][k] != live_rule.dig("labels", k) }.map { |k| "label:#{k}" }
    diff += ENUM_KEYS.select { |k| iac_rule.key?(k) && iac_rule[k].to_s != live_rule[k].to_s }
    if iac_rule.key?("for") && interval_seconds(iac_rule["for"]) != interval_seconds(live_rule["for"])
      diff << "for (#{iac_rule['for']} ⟷ #{live_rule['for']})"
    end

    "#{uid} → #{diff.join(', ')}" unless diff.empty?
  end
  if text_drift.empty?
    puts "  ✓ анотації · мітки · поведінка збігаються (текст, який побачить оператор)"
  else
    puts "  ✗ ТЕКСТ/ПОВЕДІНКА розійшлись (#{text_drift.size}) — оператор прочитає НЕ ТЕ, що каже репо:"
    text_drift.each { |d| puts "     · #{d}" }
  end

  bad_interval = groups.filter_map do |g|
    next unless folder

    c, grp = request(:get, "/api/v1/provisioning/folder/#{folder['uid']}/rule-groups/#{g['name']}")
    want = interval_seconds(g["interval"])
    "#{g['name']}: у стеку #{grp['interval']}s, IaC каже #{want}s" if c == 200 && grp["interval"] != want
  end
  puts(bad_interval.empty? ? "  ✓ інтервали груп збігаються" : "  ✗ інтервали розійшлись: #{bad_interval.join('; ')}")

  drift = !missing.empty? || !unbound.empty? || !bad_interval.empty? || !text_drift.empty? || !extra.empty?
  puts(drift ? "\n✗ розходження — прожени імпорт без `--verify`" : "\n✅ стек у паритеті з IaC (у межах оголошених стель у шапці режиму)")
  exit(drift ? 1 : 0)
end

# 2. Folder
code, folders = request(:get, "/api/folders")
fail! "GET /api/folders → #{code}" unless code == 200
folder = folders.find { |f| f["title"] == FOLDER }
if folder
  step "folder «#{FOLDER}» вже існує (uid #{folder['uid']})"
else
  code, folder = request(:post, "/api/folders", body: { title: FOLDER })
  fail! "POST /api/folders → #{code}: #{folder}" unless code == 200
  step "folder «#{FOLDER}» створено (uid #{folder['uid']})"
end
folder_uid = folder["uid"]

# 3. Dashboard
code, res = request(:post, "/api/dashboards/import", body: {
                      dashboard: dashboard,
                      overwrite: true,
                      folderUid: folder_uid,
                      inputs: [ { name: DS_INPUT_NAME, type: "datasource",
                                  pluginId: "prometheus", value: ds_uid } ]
                    })
# 🔴 ДАШБОРД І ПРАВИЛА — НЕЗАЛЕЖНІ АРТЕФАКТИ, і зчеплювати їх `fail!` було дефектом
# звʼязності (виміряно на живому стеку 2026-08-29). Grafana Cloud скоупить RBAC ПО ТЕКАХ:
# у виміряному випадку service-account мав `alert.rules:*` на `folders:*`, а
# `dashboards:create` — лише на дві конкретні теки, тож 403 на дашборді ОБРИВАВ імпорт
# до того, як поїхало бодай одне правило. Тобто часткові права давали НУЛЬ результату
# замість більшої половини.
# ⚠️ Деградація тут не пом'якшення: провал лишається гучним І несе ненульовий exit нижче
# (`dashboard_failed`) — міняється лише ПОРЯДОК, а не суворість.
dashboard_failed = nil
if code == 200
  step "дашборд імпортовано: #{res['importedUrl'] || res['url']}"
else
  dashboard_failed = "#{code}: #{res}"
  warn "⚠ дашборд НЕ імпортовано → #{dashboard_failed}"
  warn "  403 тут майже завжди = права токена скоуповані по теках: перевір" \
       " GET /api/access-control/user/permissions → `dashboards:create`."
  warn "  Правила їдуть далі — вони окремий артефакт і власний скоуп мають."
end

# 4. Alert rules — per-rule upsert (стабільні uid'и в YAML = ідемпотентність)
prov_headers = { "X-Disable-Provenance" => "true" }
groups.each do |g|
  g["rules"].each do |rule|
    body = rule.merge("folderUID" => folder_uid, "ruleGroup" => g["name"], "orgID" => g.fetch("orgId", 1))
    body["data"] = rule["data"].map do |d|
      d.key?("datasourceUid") && d["datasourceUid"] == PLACEHOLDER ? d.merge("datasourceUid" => ds_uid) : d
    end
    code, res = request(:post, "/api/v1/provisioning/alert-rules", body: body, headers: prov_headers)
    if code == 409 || (code == 400 && res.to_s.include?("already exists"))
      code, res = request(:put, "/api/v1/provisioning/alert-rules/#{rule['uid']}", body: body, headers: prov_headers)
    end
    fail! "rule #{rule['uid']} → #{code}: #{res}" unless [ 200, 201, 202 ].include?(code)
    step "rule #{rule['uid']} ✓"
  end

  # Інтервал групи — best-effort: GET поточну групу → PUT з interval з YAML.
  code, grp = request(:get, "/api/v1/provisioning/folder/#{folder_uid}/rule-groups/#{g['name']}")
  want_interval = interval_seconds(g["interval"])
  if code == 200 && grp["interval"] != want_interval
    grp["interval"] = want_interval
    code, = request(:put, "/api/v1/provisioning/folder/#{folder_uid}/rule-groups/#{g['name']}",
                    body: grp, headers: prov_headers)
    warn "⚠ interval групи #{g['name']} не виставився (#{code}) — перевір у UI" unless code == 200
    step "interval групи #{g['name']} → #{want_interval}s ✓" if code == 200
  end
end

# 5. Contact point + root notification policy (CONTACT_NAME/integrations resolved up front).
if integrations.empty?
  warn "⚠ Contact point пропущено — задай ALERT_CONTACT_EMAIL та/або ALERT_CONTACT_TELEGRAM_TOKEN+_CHATID."
  warn "  Без нього alert rules firing-ять у нікуди (README §Notification channel)."
else
  code, existing = request(:get, "/api/v1/provisioning/contact-points")
  fail! "GET contact-points → #{code}: #{existing}" unless code == 200
  integrations.each do |cp|
    match = Array(existing).find { |e| e["name"] == CONTACT_NAME && e["type"] == cp["type"] }
    code, res = if match
                  request(:put, "/api/v1/provisioning/contact-points/#{match['uid']}",
                          body: cp.merge("uid" => match["uid"]), headers: prov_headers)
    else
                  request(:post, "/api/v1/provisioning/contact-points", body: cp, headers: prov_headers)
    end
    fail! "contact-point #{cp['type']} → #{code}: #{res}" unless [ 200, 201, 202 ].include?(code)
    step "contact point «#{CONTACT_NAME}» (#{cp['type']}) ✓"
  end

  # Root policy → маршрут на наш contact point; наявні routes зберігаються (GET→mutate→PUT).
  code, policy = request(:get, "/api/v1/provisioning/policies")
  fail! "GET policies → #{code}: #{policy}" unless code == 200
  policy["receiver"]        = CONTACT_NAME
  policy["group_by"]        = %w[grafana_folder alertname] if Array(policy["group_by"]).empty?
  policy["group_wait"]      = ENV.fetch("ALERT_GROUP_WAIT", "30s")
  policy["group_interval"]  = ENV.fetch("ALERT_GROUP_INTERVAL", "5m")
  policy["repeat_interval"] = ENV.fetch("ALERT_REPEAT_INTERVAL", "4h")
  code, res = request(:put, "/api/v1/provisioning/policies", body: policy, headers: prov_headers)
  fail! "PUT policies → #{code}: #{res}" unless [ 200, 201, 202 ].include?(code)
  step "notification policy → «#{CONTACT_NAME}» (wait #{policy['group_wait']} / interval #{policy['group_interval']} / repeat #{policy['repeat_interval']}) ✓"
end

suffix = integrations.empty? ? "" : " + contact point «#{CONTACT_NAME}»"
dash_part = dashboard_failed ? "дашборд ✗" : "дашборд ✓"
puts "#{dashboard_failed ? '⚠' : '✅'} імпортовано: #{dash_part} + #{rule_count} alert rules у «#{FOLDER}»#{suffix}."
puts "   Contact point пропущено — задай ALERT_CONTACT_* і перезапусти (README §Notification channel)." if integrations.empty?
if dashboard_failed
  warn "✗ дашборд лишився неімпортованим (#{dashboard_failed}) — exit 1, щоб провал не був тихим."
  exit 1
end
