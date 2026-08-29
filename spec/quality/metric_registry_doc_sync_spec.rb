# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "json"
require "set"
require "yaml"
require_relative "../support/repo_root"

# [DOC-T.88] Канонічний реєстр метрик у `06_03` вівся РУКАМИ — і розійшовся з
# Prometheus-реєстром рівно так, як передбачає правило `00_06 §1` про волатильні
# лічильники: шапка заявляла 47 counters при 48, бо `insurance_reserve_hold_total`
# лежав у таблиці ГЕЙДЖІВ (алерт на нього бере `increase()`, тобто читав його
# правильно, а док — ні).
#
# 🔴 Гейт судить ІМЕНА і ТИПИ, ніколи число. Саме число і є тим лічильником, який
# правило забороняє: воно дрейфує щокоміту, а множина імен — ні. Друга вісь нижче
# тримає цю заборону явно, інакше «поверни лічильник у шапку» повернулось би тихо.
#
# ⚠️ Дім — RSpec (а не rake-крок, як у `model_doc_sync`), і це вибір за ПЕРИМЕТРОМ:
# джерело істини тут `config/initializers/prometheus.rb`.
# 🔴 [INF.26, 2026-08-29] Ця клауза стверджувала «а НЕ крок `docs.yml`» — і власна
# правка того ж дня зробила її хибною: спека тепер стоїть У КРОЦІ `Cross-tree gates`
# саме тому, що дістала третій вхід — `deploy/grafana/**`. Фільтр джоби `test`
# (`ruby`) того дерева не містить, тож PR, що ВИДАЛЯЄ єдиного споживача метрики,
# цього гейта не запускав би взагалі (§Guard-craft #1 — декоративний за ВХОДОМ).
# Обидва доми легітимні одночасно: повна сюїта ловить дрейф із боку КОДУ,
# `docs.yml` — із боку доку й Grafana-IaC.
RSpec.describe "metric registry ⟷ 06_03 canonical tables" do # rubocop:disable RSpec/DescribeClass
  # Ліниво, як у `spec/deploy/grafana_alerts_spec.rb` [DOC-T.76]: у повній сюїті
  # Rails уже `load`-нув ініціалізатор, а `load` не пише в `$LOADED_FEATURES`,
  # тож безумовний `require_relative` дав би стос «already initialized constant».
  let(:registry) do
    unless defined?(SilkenNet::Metrics::REGISTRY)
      require_relative "../../config/initializers/prometheus"
    end
    SilkenNet::Metrics::REGISTRY
  end

  let(:doc) { REPO_ROOT.join("docs/06_03_Prometheus_Observability.md").read }

  # Метод, а не константа: константа в `describe` тече в глобальний простір
  # (RSpec/LeakyConstantDeclaration) — і сусідній спек дістав би її мовчки.
  def sections = { counter: "Counters", gauge: "Gauges", histogram: "Histograms" }

  # Таблиця живе між своєю шапкою і наступною; остання — до кінця секції.
  def documented(kind)
    label = sections.fetch(kind)
    body = doc[/^\*\*#{label}[^:]*:\*\*(.*?)(?=^\*\*(?:#{sections.values.join("|")})[^:]*:\*\*|\A\z|^---$)/m, 1]
    raise "у 06_03 немає таблиці `**#{label}:**`" if body.nil?

    body.scan(/^\|\s*`(silkennet_[a-z0-9_]+)`/).flatten.uniq
  end

  def registered(kind)
    registry.metrics.select { |m| m.type == kind }.map { |m| m.name.to_s }
  end

  %i[counter gauge histogram].each do |kind|
    it "the #{kind} table lists exactly the registered #{kind} metrics" do
      missing_from_doc = registered(kind) - documented(kind)
      missing_from_code = documented(kind) - registered(kind)

      expect(missing_from_doc).to be_empty,
        "У реєстрі є `#{kind}`, яких НЕМА в таблиці 06_03: #{missing_from_doc.join(', ')}. " \
        "Додай рядок — інакше метрика існує, а канон про неї мовчить."
      expect(missing_from_code).to be_empty,
        "У таблиці 06_03 (`#{kind}`) є метрики, яких НЕМА в реєстрі з таким типом: " \
        "#{missing_from_code.join(', ')}. Перевір ТИП — саме так `insurance_reserve_hold_total` " \
        "(counter) роками лежав серед гейджів."
    end
  end

  # ---------------------------------------------------------------------------
  # [INF.26 · ⚖️ 2026-08-29] ДВА ЯРУСИ РЕЄСТРУ.
  #
  # Присуд: «без споживача» перестає бути ДЕФЕКТОМ і стає ОГОЛОШЕНИМ СТАНОМ — але
  # лише коли його оголосили. Тож ярусів два, і різниця в ОБОВʼЯЗКУ, не у важливості:
  #   · алертна      — дефолт; мусить мати СПОЖИВАЧА (alert-правило АБО панель
  #                    дашборда в `deploy/grafana/**`). Маркера не несе.
  #   · діагностична — несе в докстрінгу `[<ID>; diagnostic tier: <подія дротування>]`
  #                    і споживача мати НЕ мусить.
  #
  # ⚠️ «Споживач», а не «алерт» — це формулювання самого присуду, і воно несуче:
  # чимало метрик живуть лише на панелях, і це здоровий стан (обсяг, пул, GC).
  # Вимога саме алерту зробила б декларацію обовʼязковою для більшості з них,
  # тобто перетворила б реєстр на шум — рівно те, що присуд відкинув.
  # Мітка «алертна» означає «мусить мати ЧИТАЧА», не «має алерт-правило».
  # (⛔ Числа тут свідомо немає: воно дрейфує на кожному дротуванні — той самий
  # клас, який `06_03 §2.8` уже забороняє. Перерахунок — прогін цієї спеки.)
  #
  # 🔴 ОГОЛОШЕНІ СТЕЛІ — читай як перелік того, що після правки звіряєш РУКАМИ:
  #  1. Судиться НАЯВНІСТЬ споживача, ніколи його ПРАВИЛЬНІСТЬ: поріг може бути
  #     безглуздий, `expr` — про сусідню метрику (§Guard-craft #74 — реєстр
  #     енфорсить ПАРИТЕТ, ніколи ЗАКОННІСТЬ). Тому декларацією «діагностична»
  #     МОЖНА узаконити справжню діру, і гейт не відрізнить її від чесної.
  #  2. Судиться НАЯВНІСТЬ події дротування, ніколи її НАСТАННЯ (§Guard-craft #53:
  #     `back` є передбаченням, і протухлий виняток виглядає точно як живий).
  #  3. Периметр споживачів — рівно два IaC-артефакти нижче. Правило, створене
  #     руками в Grafana Cloud UI, для цього гейта НЕ ІСНУЄ, і метрика під ним
  #     почервоніє. Це свідомо: `06_03` називає IaC єдиним домом.
  #  4. Histogram нормалізується суфіксами `_bucket/_sum/_count` — та сама
  #     нормалізація, що в `spec/deploy/grafana_alerts_spec.rb`. Інших немає.
  #
  # ⊥ Дзеркальний напрямок (alert-expr → реєстр, тобто «чи не мертве правило»)
  # живе в `spec/deploy/grafana_alerts_spec.rb` і сюди НЕ переїжджає.
  # ---------------------------------------------------------------------------
  describe "two-tier declaration [INF.26]" do
    let(:alerts_file) { REPO_ROOT.join("deploy/grafana/alerts/silkennet-alerts.yaml") }
    let(:dashboards) { REPO_ROOT.glob("deploy/grafana/dashboards/*.json") }

    # Витяг СТРУКТУРНИЙ, не грепом по файлу: коментар, що згадує метрику,
    # споживачем не є — а греп порахував би його, і саме так наївний вимір цього
    # ж проходу дав хибний нуль сиріт.
    let(:consumers) do
      exprs = YAML.safe_load(alerts_file.read, aliases: true).fetch("groups").flat_map do |group|
        group.fetch("rules").flat_map { |rule| rule.fetch("data").map { |datum| datum.dig("model", "expr") } }
      end
      dashboards.each { |file| exprs.concat(panel_exprs(JSON.parse(file.read))) }
      exprs.compact.join(" ").scan(/\bsilkennet_[a-z0-9_]+/).to_set
    end

    def panel_exprs(node)
      case node
      when Hash then node.flat_map { |k, v| k == "expr" && v.is_a?(String) ? [ v ] : panel_exprs(v) }
      when Array then node.flat_map { |v| panel_exprs(v) }
      else []
      end
    end

    def consumed?(metric)
      names = [ metric.name.to_s ]
      names += %w[bucket sum count].map { |suffix| "#{metric.name}_#{suffix}" } if metric.type == :histogram
      names.any? { |name| consumers.include?(name) }
    end

    # Метод, а не константа — той самий припис, що на `sections` вище: константа в
    # `describe` тече в глобальний простір (RSpec/LeakyConstantDeclaration).
    def diagnostic(metric) = metric.docstring[/diagnostic tier:\s*([^\]]+)/, 1]&.strip

    # Тіло однієї канонічної таблиці → [метрика, друга колонка]. Межі ті самі, що
    # в `documented` вище: від власної шапки до наступної.
    def table_rows(label)
      body = doc[/^\*\*#{label}[^:]*:\*\*(.*?)(?=^\*\*(?:#{sections.values.join('|')})[^:]*:\*\*|\A\z|^---$)/m, 1]
      raise "у 06_03 немає таблиці `**#{label}:**`" if body.nil?

      body.scan(/^\|\s*`(silkennet_[a-z0-9_]+)`\s*\|\s*([^|]*?)\s*\|/)
    end

    it "every metric WITHOUT the diagnostic marker has a consumer (alert rule or dashboard panel)" do
      undeclared = registry.metrics.reject { |m| diagnostic(m) }.reject { |m| consumed?(m) }.map { |m| m.name.to_s }

      expect(undeclared).to be_empty,
        "Метрики без споживача Й без декларації ярусу (#{undeclared.size}): #{undeclared.join(', ')}.\n" \
        "Кожна — власна розвилка, і механічне рішення для всіх ЗАБОРОНЕНО [INF.26]: або дротуй " \
        "споживача (правило в `deploy/grafana/alerts/`, панель у `deploy/grafana/dashboards/`), або " \
        "оголоси ярус, дописавши в докстрінг `[<ID>; diagnostic tier: <подія, після якої дротуємо>]`. " \
        "⛔ Декларація легітимна ЛИШЕ там, де питання справді немає: на грошовому, слешинговому, " \
        "MRV-доказовому чи безпековому шляху вона узаконює діру, а гейт цього не побачить."
    end

    # Staleness-половина [§Guard-craft #53]: без неї декларація гниє ЗЕЛЕНОЮ —
    # метрика дістає споживача, а реєстр і далі каже «читача не має».
    it "no metric claims the diagnostic tier while a consumer already reads it" do
      stale = registry.metrics.select { |m| diagnostic(m) }.select { |m| consumed?(m) }.map { |m| m.name.to_s }

      expect(stale).to be_empty,
        "Декларація ярусу протухла — споживач зʼявився (#{stale.join(', ')}). " \
        "Прибери `diagnostic tier: …` з докстрінга: метрика стала алертною."
    end

    # Подія дротування і є тим, що робить виняток ЗВОРОТНИМ. Без неї «діагностична»
    # означає «назавжди», а такого ярусу присуд не вводив.
    it "every diagnostic declaration names the event that ends it" do
      mute = registry.metrics.select { |m| m.docstring.include?("diagnostic tier") }
                     .reject { |m| diagnostic(m).to_s.length >= 12 }.map { |m| m.name.to_s }

      expect(mute).to be_empty,
        "Декларація без названої події дротування (#{mute.join(', ')}). Форма — " \
        "`[<ID>; diagnostic tier: <подія>]`, напр. «no alert until the retention window is ratified»."
    end

    # Колонка `Ярус` у 06_03 ВИВОДИТЬСЯ з докстрінга регенерацією — тож вона вміє
    # розійтись рівно так, як розходились імена й типи до DOC-T.88.
    # 🔴 Скан ОБМЕЖЕНО тілами трьох канонічних таблиць, а не файлом: підсекції
    # §2.3–§2.7 мають ІНШИЙ розклад колонок (друга — константа `SilkenNet::Metrics::…`),
    # тож файловий скан звіряв би ярус із назвою константи. Сьогодні його рятував
    # лише ПОРЯДОК рядків (`to_h` лишає останнє входження, а канонічні таблиці
    # стоять нижче) — тобто гейт був правильний ВИПАДКОВО, і перенесення секції
    # мовчки зробило б його хибним [§Guard-craft #17].
    it "the 06_03 tier column matches the code declaration" do
      documented = sections.values.flat_map { |label| table_rows(label) }.to_h
      drift = registry.metrics.filter_map do |m|
        want = diagnostic(m) ? "діагностична" : "алертна"
        got = documented[m.name.to_s]
        "#{m.name}: док каже «#{got}», код каже «#{want}»" if got && got != want
      end

      expect(drift).to be_empty,
        "Колонка `Ярус` у 06_03 розійшлась із докстрінгами (#{drift.size}): #{drift.join('; ')}. " \
        "Регенеруй таблиці командою в кінці §2.8 — вона виводить колонку з коду."
    end
  end

  # 🔴 Друга вісь, і вона не косметична: доти шапки несли `(N)`, і саме це число
  # протухло. Гейт на імена сам по собі не забороняє повернути лічильник назад.
  it "the table headers carry NO volatile count (00_06 §1)" do
    offenders = doc.scan(/^\*\*(#{sections.values.join("|")}) \(\d+\)\:\*\*/).flatten

    expect(offenders).to be_empty,
      "Шапки таблиць метрик знову несуть лічильник: #{offenders.join(', ')}. " \
      "`00_06 §1` це забороняє — число дрейфує щокоміту, а парність тримає цей гейт по ІМЕНАХ."
  end
end
