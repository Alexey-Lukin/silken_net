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
  # Виміряне покриття (з урахуванням Phlex-компонентів): line 99.08%, branch 90.83%
  if ENV["FEATURE_TEST"]
    minimum_coverage line: 0, branch: 0
  else
    minimum_coverage line: 96, branch: 85
  end
  minimum_coverage_by_file 0
end

# Per-group coverage tripwire. SimpleCov ships with a global `minimum_coverage`
# гейтом, але без per-group — отже падіння покриття у Services/Workers може
# схуднути нижче критичного рівня, доки глобальний середній лишається ≈99%.
# Гейт відключаємо для feature-test run (там покриття вимірюється окремо).
unless ENV["FEATURE_TEST"]
  SimpleCov.at_exit do
    SimpleCov.result.format!

    # Conservative thresholds — global coverage is ~99% (.last_run.json),
    # but per-group baselines aren't pinned. Bump these up after a stable
    # CI run measures actual numbers. The tripwire still catches large
    # regressions (e.g. an accidentally-deleted spec dropping a group ≥10%).
    minimums = {
      "Services" => 90.0,
      "Workers"  => 85.0,
      "Models"   => 90.0
    }

    failures = SimpleCov.result.groups.filter_map do |name, files|
      threshold = minimums[name]
      next if threshold.nil? || files.empty?
      actual = files.covered_percent
      next if actual >= threshold
      "  #{name}: #{actual.round(2)}% < #{threshold}%"
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
