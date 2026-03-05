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
