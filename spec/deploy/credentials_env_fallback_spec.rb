# frozen_string_literal: true

require "rails_helper"

# SEC.22 drift guard. Phase-2 drops RAILS_MASTER_KEY from the runtime ENV, so any
# `Rails.application.credentials` read that is NOT ENV-first resolves to nil in production once
# the vault is gone → 401 / boot-crash. This is the exact dead-on-first-boot class SEC.22 already
# hit twice (AR-encryption keys were DEAD-in-prod, unconfigured). The 07-09 sweep moved 8 services
# + storage.yml to `ENV[..].presence || Rails.application.credentials...`; this makes that a
# durable invariant instead of a one-shot grep — a bare `credentials.dig(:x)` added tomorrow fails
# CI now, not in production after the RAILS_MASTER_KEY drop.
#
# Mirror of INF.12 env_fetch_declaration_spec: a one-time set-diff → a standing gate.
RSpec.describe "every Rails.application.credentials read is ENV-first (SEC.22)" do # rubocop:disable RSpec/DescribeClass
  # app + lib code, config/*.rb, and config/*.yml (storage.yml reads creds via ERB).
  let(:files) do
    Dir[
      Rails.root.join("app/**/*.rb"),
      Rails.root.join("lib/**/*.rb"),
      Rails.root.join("config/**/*.rb"),
      Rails.root.join("config/**/*.yml")
    ]
  end

  # Count credential reads NOT guarded by an ENV-first fallback. Whole-line comments are stripped
  # (doc examples like production.rb's `#   password: Rails.application.credentials...` and the
  # `# Credentials:` note must not count), then whitespace is collapsed so a multi-line
  # `ENV[..].presence ||\n  Rails.application.credentials` (puro_earth) still matches the good form.
  def unguarded_reads(path)
    code    = File.readlines(path).reject { |l| l.strip.start_with?("#") }.join.gsub(/\s+/, " ")
    total   = code.scan(/Rails\.application\.credentials/).size
    guarded = code.scan(/ENV\[[^\]]*\]\.presence\s*\|\|\s*Rails\.application\.credentials/).size
    total - guarded
  end

  it "reads every service credential through ENV[..].presence || (Phase-2 RAILS_MASTER_KEY-drop safe)" do
    offenders = files.select { |f| unguarded_reads(f).positive? }
                     .map { |f| Pathname.new(f).relative_path_from(Rails.root).to_s }
    expect(offenders).to be_empty,
                         "bare Rails.application.credentials read (no ENV-first fallback) → nil in prod after " \
                         "Phase-2 RAILS_MASTER_KEY drop (SEC.22 dead-on-first-boot): #{offenders.join(', ')}"
  end
end
