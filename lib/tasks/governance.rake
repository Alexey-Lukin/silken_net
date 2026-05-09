# frozen_string_literal: true

# = =====================================================================
# 🏛️  GOVERNANCE — Production-safe protocol parameter bootstrap
# = =====================================================================
# Rationale: db/seeds.rb is destructive (delete_all + reseed) and intended
# only for development/test bootstrapping. Production must NOT call it
# under any circumstance.
#
# This rake namespace exposes idempotent UPSERTs for governance-aware
# protocol parameters that *must* exist before the minting / insurance
# pipelines run. Re-run as many times as you like — each invocation
# converges to the desired state without touching unrelated rows or any
# parameter the DAO has subsequently overwritten via on-chain governance.
#
# Wiring:
#   * Kamal post-deploy hook: `bin/rails governance:seed_parameters`
#   * Manual recovery:        `bundle exec rake governance:seed_parameters`
#
# Source values: `db/seeds.rb` (kept as the single declarative source of
# default protocol constants); this task duplicates the *minimal* subset
# that previously lived in the now-squashed
# `20260501160000_seed_governance_system_parameters.rb` migration so the
# behaviour is preserved end-to-end.
namespace :governance do
  desc "Idempotently UPSERT governance-critical SystemParameter rows (production-safe)"
  task seed_parameters: :environment do
    parameters = [
      {
        key: "dynamic_tax_rate", value: "0.02", value_type: "decimal",
        category: "minting", source: "default",
        min_value: 0, max_value: 0.5,
        description: "DAO Treasury tax rate applied when insurance pool is below threshold (2% default)."
      },
      {
        key: "insurance_pool_threshold", value: "100000", value_type: "integer",
        category: "insurance", source: "default",
        min_value: 0, max_value: nil,
        description: "SCC balance below which the dynamic tax rate activates."
      }
    ]

    upserted = 0
    skipped  = 0

    parameters.each do |attrs|
      record = SystemParameter.find_or_initialize_by(key: attrs[:key])

      # Preserve DAO-authored values: if the parameter has been promoted
      # from `default` (this seed) to any other source (`dao_governance`,
      # `admin_panel`, ...) we must NOT clobber it.
      if record.persisted? && record.source != "default"
        skipped += 1
        next
      end

      record.assign_attributes(attrs)
      record.save!
      upserted += 1
    end

    puts "[governance:seed_parameters] upserted=#{upserted} skipped_dao_owned=#{skipped}"
  end
end
