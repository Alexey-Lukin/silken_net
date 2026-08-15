# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = =====================================================================
# 📖 CODEX — Production-safe lore seeding
# = =====================================================================
# Exposes the idempotent `Codex::NodeImportService` as a rake task so the
# The seed corpus (realms + lore nodes — кількість читається з
# `db/seeds/codex/`, не з цього рядка) can be loaded into production via
# the deployment pipeline without ever invoking the destructive
# `db/seeds.rb`.
#
# Wiring:
#   * Kamal post-deploy hook (after governance:seed_parameters):
#       bin/rails codex:seed
#   * Manual top-up after editing YAMLs:
#       bundle exec rake codex:seed
#
# Idempotency: every realm and node is keyed by stable `slug`; counters
# (attunement_count, view_count, ...) and battle state (attunement_elo)
# are preserved across re-runs. Newly added YAML rows are inserted; rows
# removed from YAML are LEFT IN PLACE (intentional — community/DAO data
# may already point at them and removing would orphan citations).
#
# SSOT: docs/04_05_Codex_Lore_Module.md §9.
namespace :codex do
  desc "Idempotently UPSERT Codex::Realm and Codex::Node seeds (production-safe)"
  task seed: :environment do
    result = Codex::NodeImportService.call

    puts "[codex:seed] realms=#{result.realms_upserted} " \
         "nodes=#{result.nodes_upserted} errors=#{result.errors.size}"
    result.errors.each { |e| warn "  ! #{e}" }

    abort("[codex:seed] FAILED — see errors above") unless result.success?
  end
end
