# SPDX-License-Identifier: AGPL-3.0-or-later
# SimpleCov — аналіз покриття тестами.
# Має бути на самому початку, до завантаження будь-якого коду додатка.
require "simplecov"
require "simplecov_json_formatter"
SimpleCov.start "rails" do
  enable_coverage :branch

  # Emit both human-readable HTML and machine-readable JSON so CI can upload
  # both as artifacts and downstream tooling (e.g. PR comments, dashboards)
  # can parse coverage without HTML scraping.
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter
  ])

  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/db/"
  add_filter "/vendor/"
  add_filter "/firmware/"
  add_filter "/lib/daemons/"

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
  add_filter "/lib/tasks/"
  # Standalone CLI guard-scripts (workflow_gate_perimeter / guard_registry_sync /
  # docs_check / stan_audit …) — pure-Ruby drift-gates run via `ruby scripts/*.rb`
  # in docs.yml, NOT Rails-runtime code; their quality gate is their own spec +
  # mutation-verification, not the app coverage-floor. Same rationale as /lib/tasks/.
  add_filter "/scripts/"

  # Boilerplate Rails-файли без бізнес-логіки
  add_filter "app/jobs/application_job.rb"
  add_filter "app/helpers/application_helper.rb"
  add_filter "app/mailers/application_mailer.rb"

  add_group "Models",      "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services",    "app/services"
  add_group "Workers",     "app/workers"
  add_group "Blueprints",  "app/blueprints"
  add_group "Views",       "app/views"

  # Feature-тести запускаються окремим CI job і мають свій скоуп.
  # Мінімальний кавередж застосовується тільки до unit/integration спеків.
  # Гейт тримається нижче фактичного покриття — лишає маржу під seed-залежний
  # флак (кілька рядків/гілок плавають між прогонами) + майбутній churn.
  # COVERAGE=0 — повне відключення гейту для pure-unit прогонів (напр. docs.yml
  # ганяє лише файли спеків лінтерів → загальне покриття ≈0, гейт хибно впав би).
  if ENV["FEATURE_TEST"] || ENV["COVERAGE"] == "0"
    minimum_coverage line: 0, branch: 0
  else
    minimum_coverage line: 99, branch: 98
  end
  minimum_coverage_by_file 0
end

# Per-group coverage tripwire. SimpleCov ships with a global `minimum_coverage`
# гейтом, але без per-group — отже падіння покриття у Services/Workers може
# схуднути нижче критичного рівня, доки глобальний середній лишається ≈99%.
# Гейт відключаємо для feature-test run (там покриття вимірюється окремо)
# та для pure-unit прогонів з COVERAGE=0 (subset спеків лінтерів у docs.yml).
unless ENV["FEATURE_TEST"] || ENV["COVERAGE"] == "0"
  SimpleCov.at_exit do
    SimpleCov.result.format!

    # Per-group line + branch floors — a RATCHET set to floor(current coverage).
    # The gap between fact and floor IS permission to erode: every PR without a
    # test slides down it until fact meets floor. Floors therefore track fact,
    # kept ~0.5–1pp below it purely for seed-flake margin, NOT for drift-room.
    # Branch is the tighter signal (line is ~99.8 everywhere).
    # Services branch (99.06%, 13 leave-branches) → floor 98 not 99: at 99 a
    # 2-branch seed-float would false-fail. Models (99.44) & Views (98.66) have
    # the least margin — loosen by 1 if a seed-dependent run false-fails.
    minimums = {
      "Services"    => { line: 99.0, branch: 98.0 },
      "Workers"     => { line: 99.0, branch: 99.0 },
      "Models"      => { line: 99.0, branch: 99.0 },
      "Controllers" => { line: 99.0, branch: 99.0 },
      "Views"       => { line: 99.0, branch: 98.0 }
    }

    failures = SimpleCov.result.groups.flat_map do |name, files|
      floors = minimums[name]
      next [] if floors.nil? || files.empty?

      {
        "line"   => [ files.covered_percent,        floors[:line] ],
        "branch" => [ files.branch_covered_percent, floors[:branch] ]
      }.filter_map do |metric, (actual, threshold)|
        next if actual >= threshold
        "  #{name} #{metric}: #{actual.round(2)}% < #{threshold}%"
      end
    end

    next if failures.empty?

    warn "\nSimpleCov per-group coverage failures:"
    failures.each { |line| warn line }
    Kernel.exit SimpleCov::ExitCodes::MINIMUM_COVERAGE
  end
end

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
end
