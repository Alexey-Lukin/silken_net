# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "json"
require "yaml"
require_relative "../support/repo_root"

# [INF.22] Ловить «конфіг повний, шлях мертвий» для Grafana-алертів: alert-правило, що
# посилається на метрику з typo в назві (або на прибрану з реєстру метрику), тихо НІКОЛИ
# не спрацює — так само як web:80 віддавав job-метрики нулями (§06-нора). Цей spec звіряє
# КОЖНУ silkennet_-метрику з усіх alert-expr проти Prometheus::Client реєстру, який будує
# config/initializers/prometheus.rb.
RSpec.describe "Grafana alert rules ↔ Prometheus registry consistency" do # rubocop:disable RSpec/DescribeClass
  # Base-імена всіх зареєстрованих метрик (counter несе _total у назві; histogram — базове
  # ім'я, expr додає _bucket/_sum/_count — нормалізуємо на боці referenced нижче).
  # 🔴 [DOC-T.76] Реєстр метрик живе в Rails-ІНІЦІАЛІЗАТОРІ, а джоба `docs_check`
  # Rails не піднімає за побудовою. Файл вантажиться автономно: усі його
  # `Rails.`-звернення сидять у тілах sampler-методів, що на load-time не біжать.
  # ⚠️ Гард І ЛІНЬ несучі РАЗОМ: у повній сюїті (`ci.yml` job `test`) Rails уже
  # `load`-нув цей файл, а `load` НЕ пише в `$LOADED_FEATURES`, тож безумовний
  # `require_relative` дав би 83 попередження «already initialized constant».
  # Ліниво = на момент виклику Rails або вже є, або його не буде, і порядок
  # завантаження спек не впливає ні на що.
  let(:registered) do
    require_relative "../../config/initializers/prometheus" unless defined?(SilkenNet::Metrics::REGISTRY)
    SilkenNet::Metrics::REGISTRY.metrics.map { |m| m.name.to_s }.to_set
  end

  let(:alerts_file) { REPO_ROOT.join("deploy/grafana/alerts/silkennet-alerts.yaml") }

  let(:referenced) do
    yaml = YAML.safe_load(File.read(alerts_file), aliases: true)
    exprs = yaml.fetch("groups").flat_map do |group|
      group.fetch("rules").flat_map do |rule|
        rule.fetch("data").map { |datum| datum.dig("model", "expr") }
      end
    end
    exprs.compact.join(" ").scan(/\bsilkennet_[a-z0-9_]+/).uniq
  end

  # [INF.26/S2.2] `import.rb --verify` ОГОЛОШУЄ себе read-only — і доти це була
  # обіцянка без носія. Ціна помилки асиметрична: режим існує саме щоб його ганяли
  # НАОСЛІП проти живого стека, тож випадковий `request(:post …)`, що заїде в цю
  # гілку, мутуватиме прод у момент, коли оператор упевнений, що лише дивиться.
  # ⚠️ Стеля: спека судить ФОРМУ виклику в цій гілці, не досяжність — метод,
  # винесений за межі гілки й покликаний звідти, вона не побачить.
  it "the --verify branch of import.rb performs no writes" do
    src = REPO_ROOT.join("deploy/grafana/import.rb").read
    branch = src[/^if ARGV\.include\?\("--verify"\)$(.*?)^end$/m, 1]

    expect(branch).not_to be_nil, "гілку `--verify` не знайдено — режим перейменували чи зняли?"
    expect(branch).not_to match(/request\(:(post|put|delete|patch)\b/),
      "у гілці `--verify` зʼявився мутуючий виклик — режим оголошений read-only, " \
      "і його ганяють проти живого стека саме на цій підставі."
  end

# [S2.4] Ruler API ЗБЕРІГАЄ правило, чиє data-вікно Mimir потім ВІДМОВИТЬСЯ рахувати:
# ліміт 11 000 точок/серію при step 15s = стеля ~45 год на relativeTimeRange. Три правила
# (8d/1w/30d) імпортувались зеленими і падали в DatasourceError на першій оцінці. Довгий
# lookback — робота PromQL (`increase(x[30d])` — серверний range vector), не вікна
# запиту: вузол `reduce` (гейт нижче) читає одну останню точку. 86400 (24h = 5 760 точок) —
# найбільше живе вікно, запас ~2× до стелі.
it "no alert query window exceeds 24h (Mimir 11k-points resolution ceiling)" do
  yaml = YAML.safe_load(File.read(alerts_file), aliases: true)
  oversized = yaml.fetch("groups").flat_map do |group|
    group.fetch("rules").filter_map do |rule|
      from = rule.fetch("data").filter_map { |d| d.dig("relativeTimeRange", "from") }.max
      "#{rule.fetch("uid")} (from: #{from}s)" if from && from > 86_400
    end
  end
  expect(oversized).to be_empty,
    "вікно запиту цих правил перевищить Mimir-ліміт точок — lookback має жити " \
    "в PromQL-виразі, не в relativeTimeRange: #{oversized.join(", ")}"
end

# [S2.4 · ТРЕТІЙ клас «stored ≠ evaluates», виміряно на живому canopy 2026-09-03]
# Вираз `threshold` приймає ЛИШЕ зведене число. Датасорс-запит віддає ЧАСОВИЙ РЯД, тож
# правило, чия alert-condition читає його напряму, падає в evaluation — і лік приписує
# сама Grafana: «You cannot use time series data as an alert condition, consider adding
# a reduce expression».
# 🔴 Чому цього не спіймали двічі: дефект ЛАТЕНТНИЙ, доки метрика порожня — без даних
# правило звітує `nodata` й читається як здорове. Вердикт «57/57 evaluated, 0 error»
# (клас 2) був ПРАВДИВИЙ у мить виміру і впав від першого живого job-контейнера: 29 із
# 42 перевірених правил стали Error, серед них 9 із 10 P0 — включно з тим, що стереже
# сам скрейп. Упала не форма фікса, а ПІДСТАВА вердикту ([`00_05 §5`] — пін на порожній
# множині зелений завжди). Тому гейт СТРУКТУРНИЙ: він не залежить від наявності даних.
# ⛔ `instant: true` замість `reduce` ВІДХИЛЕНО виміром: редактор Grafana малює
# `Type: Instant` там, де бекенд усе одно біжить range — тобто прапорець спирається на
# дефолт, який у цього імпортера вже двічі розійшовся зі збереженою моделлю.
# ⚠️ ОГОЛОШЕНА СТЕЛЯ: гейт судить ФОРМУ ланцюга, ніколи доречність редьюсера —
# `reduce` з хибним `reducer` (напр. `sum` там, де треба `last`) пройде зеленим.
it "no expression reads a raw datasource query — only a reduce may" do
  yaml = YAML.safe_load(File.read(alerts_file), aliases: true)
  rules = yaml.fetch("groups").flat_map { |g| g.fetch("rules") }
  expect(rules.size).to be > 50, "правил #{rules.size} — множина зіщулилась, гейт судив би порожнечу"

  offenders = rules.filter_map do |rule|
    data = rule.fetch("data")
    queries = data.reject { |d| d["datasourceUid"] == "__expr__" }.map { |d| d.fetch("refId") }
    raw = data.select do |d|
      d["datasourceUid"] == "__expr__" &&
        d.dig("model", "type") != "reduce" &&
        queries.include?(d.dig("model", "expression"))
    end
    next if raw.empty?

    "#{rule.fetch("uid")} → #{raw.map { |d| "#{d.dig('model', 'type')}(#{d.dig('model', 'expression')})" }.join(', ')}"
  end

  expect(offenders).to be_empty,
    "ці вирази читають сирий датасорс-запит замість зведеного значення — на живих даних " \
    "вони НЕ спрацюють, а на порожніх виглядатимуть здоровими: #{offenders.join('; ')}"
end

  # [S2.4] Дашборд скоуплено по `slot` — і без носія наступна панель приїхала б без нього.
  # `RAILS_ENV` = production для ОБОХ слотів (canopy різниться лише `POSTGRES_DATABASE`),
  # тож `slot` є ЄДИНИМ, що їх розводить; панель без матчера мовчки зливає staging із продом.
  # ⊥ Сиблінг для АЛЕРТІВ — нижче, і форма там ІНША: дашборд фільтрує (`{slot=~"$slot"}`),
  # алерт РОЗЩЕПЛЮЄ (`by (slot)`). Різницю ухвалено присудом, див. коментар того прикладу.
  it "every dashboard panel query is scoped by the slot label" do
    dash = JSON.parse(REPO_ROOT.join("deploy/grafana/dashboards/silkennet-overview.json").read)
    exprs = []
    walk = lambda do |node|
      case node
      when Hash then node.each { |k, v| k == "expr" && v.is_a?(String) ? exprs << v : walk.call(v) }
      when Array then node.each { |v| walk.call(v) }
      end
    end
    walk.call(dash)

    expect(exprs).not_to be_empty, "у дашборді не знайдено жодного `expr` — змінився формат?"
    # ⚠️ `scan` з ОДНІЄЮ групою віддає масиви з ОДНОГО елемента — деструктуризація на
    # дві змінні тихо клала селектор у `_`, і гейт кричав «41 без скоупу» на здоровому
    # дашборді. Тому тут дві явні групи: імʼя метрики й (опційний) селектор.
    unscoped = exprs.reject do |expr|
      expr.scan(/(silkennet_[a-z0-9_]+)(\{[^}]*\})?/).all? { |_name, selector| selector.to_s.include?("slot") }
    end

    expect(unscoped).to be_empty,
      "Панелі без `{slot=~\"$slot\"}` (#{unscoped.size}): #{unscoped.first(3).join(' | ')}. " \
      "Без матчера панель зливає canopy з production в одну лінію — а розводить їх лише ця мітка."
  end

  # [S2.4 · ⚖️ founder 2026-08-29] Алерти РОЗЩЕПЛЕНІ по `slot`, а не відфільтровані — і
  # різниця несуча, бо фільтр `{slot="production"}` заглушив би `sn-alert-db-pool-saturation`
  # (Cloud SQL — ОДИН інстанс на обидва слоти, бюджет зʼєднань спільний, тож насичення з боку
  # canopy Є продовим ризиком; мітка `database` не розводить — це `primary`/`cache`/`cable`
  # в обох).
  # 🔴 ДРУГА підстава цього ⛔ ПОМЕРЛА 2026-08-31, і вердикт від того не змінився — пару
  # тримаємо розведеною ([`00_05 §5`]). Тут стояло ще й «фільтр зробив би смерть canopy-Alloy
  # невидимою»; canopy-Alloy НЕ ІСНУЄ. Alloy-контейнер один на два слоти
  # (`Kamal::Configuration::Accessory#service_name` не несе destination), а canopy з аліасами, дизʼюнктними від скрейплених (OPS.37; доти alias-less)
  # за побудовою (`canopy-*` ∉ скрейплених — `alloy_scrape_topology_spec`), тож цілей скрейпу не має взагалі —
  # `-d canopy` не створював другого агента, а перемарковував єдиного. Механізм і носій —
  # `spec/deploy/alloy_scrape_topology_spec.rb` §«the ONE-Alloy invariant».
  #
  # 🔴 Проблема, яку це лікує: 33 із 57 виразів ЗНИЩУВАЛИ мітку агрегацією (28 голих
  # `sum`/`max`, 5 із `by(…)` без slot) — і в ці 33 потрапляли ВСІ грошові агрегати.
  # Найгірший — `sn-alert-mint-slo-breach`: `sum(succ)/sum(att)` збирав чисельник і
  # знаменник із РІЗНИХ реєстрів, тож canopy зі 100% успіху МАСКУВАВ би продову аварію.
  #
  # ⚠️ ОГОЛОШЕНА СТЕЛЯ: розщеплення дає мітку на КОЖНОМУ інстансі — воно не вирішує,
  # КОГО будити. Це окремий ⚖️ (notification-policy route на `slot=canopy`), і зелена
  # цієї спеки його НЕ закриває. ⛔ І ще одного вона не закриває принципово:
  # `sn-alert-chain-audit-drift` порівнює суму БД проти `totalSupply` СПІЛЬНОГО ланцюга —
  # якщо canopy колись змінтить, продова дельта стане ненульовою назавжди, і жодна
  # мітка цього не полагодить (дім питання — `00_07` OPS.37, ⚖️ форми canopy).
  it "every alert-rule aggregation is split by the slot label" do
    yaml = YAML.safe_load(File.read(alerts_file), aliases: true)
    rules = yaml.fetch("groups").flat_map { |g| g.fetch("rules") }
    agg = /(?<![a-zA-Z0-9_])(?:sum|max|min|count|avg)\s*(?:by\s*)?\(/

    unsplit = rules.filter_map do |rule|
      exprs = rule.fetch("data").filter_map { |d| d.dig("model", "expr") }
      bad = exprs.select { |e| e.scan(agg).size != e.scan("by (slot").size }
      "#{rule['uid']}: #{bad.join(' | ')}" if bad.any?
    end

    expect(unsplit).to be_empty,
      "Агрегації без `by (slot…)` (#{unsplit.size}): #{unsplit.first(3).join('; ')}. " \
      "Гола агрегація ЗНИЩУЄ мітку — і тоді злиття слотів міняє САМЕ ЧИСЛО, не додає серію."
  end

  # 🔴 [S2.4, 2026-09-06] РАТЧЕТ ПРОТИ ФІЛЬТРА, ЩО ЗАСЛІПЛЮЄ ВЛАСНЕ ПРАВИЛО.
  #
  # Правило застою приладу має форму `time() - max(<...>_timestamp_seconds) > N`. Спокуса —
  # дописати `> 0`, «щоб не рахувати від нуля». Ціна виміряна: безлейблову серію
  # `prometheus-client` реєструє зі ЗНАЧЕННЯМ 0.0 від старту процесу (`init_label_set({})`),
  # тож фільтр викидає її, інстант-вектор стає ПОРОЖНІМ, `reduce` віддає NoData — і при
  # `noDataState: OK` правило ЗЕЛЕНЕ. Тобто фільтр робить дед-мена сліпим рівно до того
  # випадку, заради якого він написаний: рестарт контейнера обнулив штамп, а писач не
  # піднявся ЖОДНОГО разу.
  #
  # ⚖️ Фільтр ЛЕГІТИМНИЙ рівно тоді, коли каденс писача ДОВШИЙ за вікно `for` — тоді без
  # нього здоровий рестарт червонить, бо наступний прогін просто ще не настав. Це
  # `partition-sampler` (крон `30 0 * * *` ≫ `for`). Для `*/5` і `*/15` навпаки: `for: 30m`
  # довший за каденс, тож Pending резолвиться сам, і фільтр коштує все, не купуючи нічого.
  #
  # ⛔ Тому це РАТЧЕТ, а не заборона: щоб додати `> 0` до нового правила, треба вписати
  # його сюди — тобто НАЗВАТИ каденс, що це виправдовує. Скопіювати токен мовчки не вийде.
  # Стеля оголошена: спека судить НАЯВНІСТЬ фільтра, а не те, чи каденс справді довший —
  # cron у цьому файлі не живе.
  it "no staleness rule silently filters `> 0` off its own freshness stamp" do
    yaml = YAML.safe_load(File.read(alerts_file), aliases: true)
    rules = yaml.fetch("groups").flat_map { |g| g.fetch("rules") }

    # Каденс писача ДОВШИЙ за `for` → без фільтра здоровий рестарт червонив би.
    justified = %w[sn-alert-partition-sampler-stale].to_set

    blinded = rules.filter_map do |rule|
      exprs = rule.fetch("data").filter_map { |d| d.dig("model", "expr") }
      next if exprs.none? { |e| e =~ /_timestamp_seconds\s*>\s*0/ }

      rule["uid"] unless justified.include?(rule["uid"])
    end

    expect(blinded).to be_empty,
      "Правила застою з `> 0` поза оголошеним списком (#{blinded.size}): #{blinded.join(', ')}. " \
      "Безлейблова серія існує зі значенням 0.0 від старту процесу, тож фільтр робить правило " \
      "СЛІПИМ до «писач не біг жодного разу після рестарту» — саме до того, що воно й ловить. " \
      "Легітимно лише коли каденс писача довший за вікно `for` — тоді впиши uid у `justified` разом із каденсом. " \
      "⚠️ Прийшов сюди, бо побачив у стеку серію зі значенням 0? Вона РЕАЛЬНА — реєстр у кожного процесу свій, штамп пише job, web тримає нуль назавжди. " \
      "Її вже прибирає `max by (slot)`; і саме той нуль лишається один, коли job помирає, тобто він і Є сигнал."
  end

  it "every silkennet_ metric referenced in an alert expr exists in the Prometheus registry" do
    missing = referenced.reject do |name|
      registered.include?(name) || registered.include?(name.sub(/_(bucket|sum|count)\z/, ""))
    end

    expect(missing).to be_empty,
      "Alert-правила посилаються на НЕзареєстровані метрики (мертвий alert — ніколи не спрацює): " \
      "#{missing.join(', ')}. Звір deploy/grafana/alerts/silkennet-alerts.yaml ↔ " \
      "config/initializers/prometheus.rb."
  end

  it "the three INF.22 observability metrics are wired to an alert" do
    %w[
      silkennet_anchor_missed_weeks_total
      silkennet_filecoin_unarchived_depth
      silkennet_hadron_kyc_pending_depth
    ].each do |name|
      expect(referenced).to include(name), "#{name} втратив alert-правило (INF.22 регресія)"
    end
  end

  it "the ARCH.66 anchor-confirmation metrics are wired to an alert" do
    %w[
      silkennet_ethereum_anchor_stuck_sent_depth
      silkennet_ethereum_anchor_manual_review_depth
      silkennet_ethereum_anchor_reverted_total
    ].each do |name|
      expect(referenced).to include(name), "#{name} втратив alert-правило (ARCH.66 регресія)"
    end
  end

  it "the S6.1 Redis→DB nonce-fallback counters are wired to an alert" do
    %w[
      silkennet_m2m_nonce_fallback_total
      silkennet_qatt_nonce_fallback_total
    ].each do |name|
      expect(referenced).to include(name),
        "#{name} без alert-правила — escalation-тригер multi-zone Upstash сліпий (S6.1, 04_03 §5.15)"
    end
  end

  it "the E.37 telemetry-volume scale trigger is wired to an alert" do
    expect(referenced).to include("silkennet_telemetry_processed_total"),
      "row-count-тригер E.37 (>100M/міс) знову сліпий — ⚖️-рішення про scale-двигун без раннього сигналу"
  end

  # [ARCH.70] Сиблінг E.37-піна вище, і поставлений із тієї самої підстави: обидві
  # осі росту існують ЛИШЕ щоб ⚖️ (ширина вікна дропу) ухвалювався за кривою, а не
  # наосліп. Гейдж без alert-правила — саме той дефект, який E.37 уже оплатив
  # («метрика існувала, дивитись на неї проти порога не було кому»).
  it "the ARCH.70 partition-growth gauges are wired to an alert" do
    %w[
      silkennet_partitions
      silkennet_partitioned_table_bytes
      silkennet_partition_sample_timestamp_seconds
    ].each do |name|
      expect(referenced).to include(name),
        "#{name} без alert-правила — поріг «пора дропати» знову невидимий, і ⚖️ ширини вікна (ARCH.70) " \
        "ухвалюватиметься наосліп разом із SEC.18-retention та SLA §3.3"
    end
  end
end
