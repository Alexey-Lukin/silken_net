# SPDX-License-Identifier: AGPL-3.0-or-later
# SimpleCov — аналіз покриття тестами.
# Має бути на самому початку, до завантаження будь-якого коду додатка.
require "simplecov"

# 🔴 [TEST.15] `COVERAGE=0` вимикає ЗАПИС, а не лише поріг — і це виправлення
# розбіжності, яку три доми документували як данність («COVERAGE=0 вимикає ГЕЙТ,
# не запис» — `rails_helper` · `docs_band.rb` §3 · `04_06 §B.3`).
#
# Доти SimpleCov стартував безумовно, тож pure-unit прогін (смуга Docs ганяє
# `COVERAGE=0 bin/rspec spec/lib/docs_*`) писав у СПІЛЬНИЙ `coverage/.resultset.json`
# поряд із повною сюїтою. Симптом колізії читається не як колізія, а як «я зламав
# покриття»: `0 failures` разом із `EXIT=2` і ВСІ групи по 0.0 % — тому він крав
# сесію чотири рази. Діагностична ознака була однозначна (реальний провал підлоги
# зсуває ОДНУ групу на десяті, а не всі одразу в нуль), але її треба було знати.
#
# ⚖️ Чому саме «не стартувати», а не власний `coverage_dir`: `COVERAGE=0` уже
# означає «покриття цього прогону не потрібне», тож ізольована тека була б
# артефактом, якого ніхто не читає. Це заразом лікує ДРУГИЙ бік того ж класу —
# субсет-прогін більше не перезаписує локальний `coverage/coverage.json` ≈0%-звітом.
# ⚠️ `FEATURE_TEST` навмисно НЕ сюди: там поріг знято, але звіт лишається потрібним
# (окремий CI-job зі своїм скоупом).
COLLECT_COVERAGE = ENV["COVERAGE"] != "0"

SimpleCov.start "rails" do
  enable_coverage :branch

  # Emit both human-readable HTML and machine-readable JSON so CI can upload
  # both as artifacts and downstream tooling (e.g. PR comments, dashboards)
  # can parse coverage without HTML scraping.
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter
  ])

  skip "/spec/"
  skip "/config/"
  skip "/db/"
  skip "/vendor/"
  skip "/firmware/"
  skip "/lib/daemons/"

  # lib/tasks/*.rake — Rake tasks are ops/SSOT orchestration, not the running
  # production app. Their real logic is extracted into lib/*.rb engines
  # (DocsLinter, DocsToc, DocsGraph, WikiLinkNormalizer, …) which ARE unit-tested
  # to 100%; the rake wrappers are file iteration + human-readable `puts` report
  # blocks + abort() gates. Those tasks ARE exercised — `rake docs:check_refs`,
  # `docs:toc`, `tracker:check` run in docs.yml / ssot_guard.yml CI — just not
  # under the RSpec coverage instrument. Counting their unmeasured `puts` lines
  # diluted the production-code gate (they were ~373 LOC / 155 branches of the
  # uncovered total). Same rationale as the /firmware/ and /lib/daemons/ filters
  # above. See 04_06 §B.3 for the coverage-scope policy.
  skip "/lib/tasks/"
  # Standalone CLI guard-scripts (workflow_gate_perimeter / guard_registry_sync /
  # docs_check / stan_audit …) — pure-Ruby drift-gates run via `ruby scripts/*.rb`
  # in docs.yml, NOT Rails-runtime code; their quality gate is their own spec +
  # mutation-verification, not the app coverage-floor. Same rationale as /lib/tasks/.
  skip "/scripts/"

  # Boilerplate Rails-файли без бізнес-логіки
  skip "app/jobs/application_job.rb"
  skip "app/helpers/application_helper.rb"
  skip "app/mailers/application_mailer.rb"

  group "Models",      "app/models"
  group "Controllers", "app/controllers"
  group "Services",    "app/services"
  group "Workers",     "app/workers"
  group "Blueprints",  "app/blueprints"
  group "Views",       "app/views"

  # Feature-тести запускаються окремим CI job і мають свій скоуп.
  # Мінімальний кавередж застосовується тільки до unit/integration спеків.
  # Гейт тримається нижче фактичного покриття — лишає маржу під seed-залежний
  # флак (кілька рядків/гілок плавають між прогонами) + майбутній churn.
  # COVERAGE=0 — повне відключення гейту для pure-unit прогонів (напр. docs.yml
  # ганяє лише файли спеків лінтерів → загальне покриття ≈0, гейт хибно впав би).
  # [DOC-T.89] branch 98 → 97.9: SFC-гард у `BlockchainMintingService` зробив дві
  # гілки недосяжними (резолв SFC-контракту + `tax_rate: nil`), і обидві лишені
  # свідомо як §B.4-leave — оживляти їх `send`-піном заборонено (`04_06 §A.4` BP 16-17),
  # а знімати не можна: у день SEC.1 знадобляться. `04_06 §B.5` для цього класу велить
  # прямо: «перерахуй підлогу, а не допиши тест». Групові підлоги НЕ рухались — усі
  # п'ять проходять; просіла саме глобальна, бо вона рахує ще й негруповані `lib/` та
  # `app/policies/`. 🔦 Ліхтар: у мить зняття гарда факт стрибне назад на ≈98.02 —
  # грепни DOC-T.89 і підніми ратчет разом із двома надгробками в сервісі.
  if ENV["FEATURE_TEST"] || ENV["COVERAGE"] == "0"
    minimum_coverage line: 0, branch: 0
  else
    minimum_coverage line: 99, branch: 97.9
  end

  # Per-group coverage tripwire [TEST.13] — глобальний `minimum_coverage` не
  # бачить, як Services/Workers худнуть нижче критичного, доки середнє тримається
  # ≈99%. Пороги — RATCHET на floor(поточного покриття): проміжок між фактом і
  # підлогою Є дозволом ерозії, тож підлоги тримаються ~0.5–1pp нижче факту суто
  # під seed-flake margin, НЕ під drift-room. Branch — тонший сигнал (line ~99.8
  # усюди). Services branch → 98 (15 leave-гілок після DOC-T.89; на 99 дво-гілковий float дав би
  # хибне падіння). Models і Views мають найменшу маржу — послаблюй на 1, якщо
  # seed-залежний прогін хибно впаде. Скоуп-політика → 04_06 §B.3.
  unless ENV["FEATURE_TEST"] || ENV["COVERAGE"] == "0"
    coverage(:line) do
      minimum_per_group 99.0, only: "Services"
      minimum_per_group 99.0, only: "Workers"
      minimum_per_group 99.0, only: "Models"
      minimum_per_group 99.0, only: "Controllers"
      minimum_per_group 99.0, only: "Views"
    end
    coverage(:branch) do
      minimum_per_group 98.0, only: "Services"
      minimum_per_group 99.0, only: "Workers"
      minimum_per_group 99.0, only: "Models"
      minimum_per_group 99.0, only: "Controllers"
      minimum_per_group 98.0, only: "Views"
    end
  end
end if COLLECT_COVERAGE

# See https://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    # Makes `description` and `failure_message` of custom matchers include
    # text for helper methods defined using `chain`.
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    # Prevents mocking or stubbing a method that does not exist on a real
    # object. Defaults to `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  # Shared context metadata is inherited by the metadata hash of host groups
  # and examples (`:apply_to_host_groups` will be the default in RSpec 4).
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Limit a spec run to examples tagged with `:focus`. When nothing is tagged,
  # all examples run. Aliases: `fit`, `fdescribe`, `fcontext`.
  config.filter_run_when_matching :focus

  # Persist example statuses to support `--only-failures` / `--next-failure`.
  # Add `spec/examples.txt` to .gitignore.
  config.example_status_persistence_file_path = "spec/examples.txt"

  # Zero monkey-patching mode — no `should` / `should_not` on every object.
  config.disable_monkey_patching!

  # Documentation formatter when running a single file.
  config.default_formatter = "doc" if config.files_to_run.one?

  # Run specs in random order to surface order dependencies.
  config.order = :random
  Kernel.srand config.seed

  # 🔦 [OPS.28] Ліхтар «ця сюїта НЕ та, якою CI міряє поріг».
  #
  # Носієм тут не могла бути команда: локальний `bin/rspec` і CI-джоба `test`
  # виконують РІЗНІ множини. CI ганяє `--exclude-pattern "features/**"` (features
  # мають власну джобу з нульовим порогом), а локально вони входять у прогін —
  # тобто те саме число рахується по більшому знаменнику. Ціна не гіпотетична:
  # `main` червонів на 97.99 при локальних 98.01, і обидва були правдиві.
  # Тому носій — рядок у ВИВОДІ, а не команда, яку треба памʼятати: він стоїть
  # рівно там, де читають число, і мовчить, коли множини збігаються.
  config.after(:suite) do
    next unless COLLECT_COVERAGE && ENV["FEATURE_TEST"].nil?
    next unless RSpec.configuration.files_to_run.any? { |f| f.include?("spec/features/") }

    warn "\n🔦 [OPS.28] Цей прогін ВКЛЮЧАЄ `spec/features/**`, а CI-джоба `test` їх " \
         "виключає (`--exclude-pattern`). Отже покриття нижче порахувано по ІНШІЙ " \
         "множині, ніж та, на якій CI судить підлогу — воно систематично ВИЩЕ. " \
         "Щоб побачити CI-число: bin/rspec --exclude-pattern \"features/**/*_spec.rb\"\n"
  end
end
