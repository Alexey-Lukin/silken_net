# SPDX-License-Identifier: AGPL-3.0-or-later
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
# Wiring (2026-09-03, OPS.38): `.kamal/hooks/post-deploy` runs `governance:bootstrap` in a
# one-off `web`-role container after EVERY `kamal deploy` (both slots); `bootstrap` composes
# the money-audit actor + this task. Until that day the header here said «the hook does not
# exist yet» — and it was right: nothing called this task on any slot.
#   * Automatic: `.kamal/hooks/post-deploy` → `bin/rails governance:bootstrap`
#   * Manual recovery:            `bundle exec rake governance:bootstrap` (or `seed_parameters` alone)
#
# 🔴 МЕЖІ ТУТ НЕ ЖИВУТЬ, і це не стиль. Дім `min`/`max`/`value_type`/`category` — один,
# `Governance::ParameterSyncWorker::PARAMETER_MAP` (канон `05_06 §7`: «One-Home меж =
# PARAMETER_MAP ↔ db/seeds.rb», гейт `scripts/governance_bounds_sync.rb`). Та пара
# гейтована ДВОСТОРОННЬО — а третя копія в неї не входила взагалі й не звірялась нічим:
# саме так тут дожили `dynamic_tax_rate` з `max 0.5` проти 0.10 в обох дзеркалах і
# `insurance_pool_threshold` без верхньої межі проти 10_000..1_000_000. Ціна не
# теоретична — це ПРОДОВИЙ bootstrap, тож прод приймав би DAO-значення, яке dev і
# синк-воркер відхилили б, і розходження було б видно лише на живих грошах.
# Локально лишається рівно те, чого в `PARAMETER_MAP` немає за побудовою: bootstrap-ЗНАЧЕННЯ
# (мапа несе конфіг синку, не дефолти) і людський опис.
namespace :governance do
  desc "Idempotently UPSERT governance-critical SystemParameter rows (production-safe)"
  task seed_parameters: :environment do
    bootstrap = {
      dynamic_tax_rate: {
        value: "0.02",
        description: "DAO Treasury tax rate applied when insurance pool is below threshold (2% default)."
      },
      insurance_pool_threshold: {
        value: "100000",
        description: "SCC balance below which the dynamic tax rate activates."
      }
    }

    parameter_map = Governance::ParameterSyncWorker::PARAMETER_MAP

    # Fail-closed ПЕРЕД будь-яким записом: ключ, вилучений із `PARAMETER_MAP`, означає,
    # що DAO ним більше не керує. Мовчазний fallback тут записав би ручку без меж —
    # тобто гард, що не відрізняє «межі такі» від «я не зміг подивитись».
    orphans = bootstrap.keys - parameter_map.keys
    if orphans.any?
      abort "[governance:seed_parameters] ⛔ #{orphans.join(', ')} — немає в PARAMETER_MAP. " \
            "Або ключ свідомо знято з governance-синку (тоді зніми його і звідси), " \
            "або дзеркало розійшлось. Bootstrap без меж не пишемо."
    end

    upserted = 0
    skipped  = 0

    bootstrap.each do |key, local|
      config = parameter_map.fetch(key)
      record = SystemParameter.find_or_initialize_by(key: key.to_s)

      # Preserve DAO-authored values: if the parameter has been promoted
      # from `default` (this seed) to any other source (`dao_governance`,
      # `admin_panel`, ...) we must NOT clobber it.
      if record.persisted? && record.source != "default"
        skipped += 1
        next
      end

      record.assign_attributes(
        value: local[:value],
        description: local[:description],
        source: "default",
        value_type: config[:value_type],
        category: config[:category],
        min_value: config[:min],
        max_value: config[:max]
      )
      record.save!
      upserted += 1
    end

    puts "[governance:seed_parameters] upserted=#{upserted} skipped_dao_owned=#{skipped}"
  end

  # [OPS.38] The production bootstrap COMPOSITION — everything an empty database needs before
  # the money pipelines run, minus what is a founder decision. Slot-agnostic and idempotent by
  # construction (find_or_create / UPSERT), so the post-deploy hook may re-run it after every
  # deploy and after a half-failed `db:prepare` (NOT atomic — 06_06 §5.6) without duplicating.
  #   1. `oracle_executioner` — the money-audit actor. This row is the loudest SILENT dependency
  #      in the tree: `Auditable#record_money_audit_trail` returns early (WARN) when it is
  #      absent, so every money transition would run without a tamper-evident trail. Never
  #      updated once present (a rotated password or role is an operator act, not ours).
  #   2. `governance:seed_parameters` — the DAO-aware UPSERT above.
  #   3. `TreeFamily` — the species of the FIRST real deployment (⚖️ 2026-09-03, delegated; the
  #      ground was already canon): 01_01 §6 Stage 4 = Черкаський бір, the anchor is tuned to
  #      *Pinus sylvestris* and oak is a separate SKU, so the first roster is ONE family. Its
  #      NUMBERS are declared PROVISIONAL in the row itself (`biological_properties.provenance`),
  #      because the calibration protocol (05_05 §8) has not run: the Z-window is the engineering
  #      estimate the demo seed carries, `optimal_z_target` mirrors the firmware constant (29.0,
  #      BioContract::OPTIMAL_Z_TARGET) and `fire_resistance_rating` the platform fire threshold
  #      (60 °C, AlertDispatchService#fire_limit); the sequestration coefficient is the RATIFIED
  #      default 1.0 (ARCH.84) — not the demo's uncited 0.8. Never updated once present: numbers
  #      the operator calibrated are theirs (same rule as the actor above).
  desc "Production bootstrap composition (OPS.38): oracle_executioner + governance parameters; idempotent"
  task bootstrap: :environment do
    oracle = User.find_or_create_by!(email_address: User::ORACLE_EXECUTIONER_EMAIL) do |u|
      u.first_name = "Oracle"
      u.last_name  = "Executioner"
      u.role       = :super_admin
      u.password   = SecureRandom.hex(32)
    end
    actor_state = oracle.previously_new_record? ? "created" : "present"

    Rake::Task["governance:seed_parameters"].invoke

    first_family = {
      name: "Сосна звичайна", scientific_name: "Pinus sylvestris",
      critical_z_min: 5.0, critical_z_max: 45.0, carbon_sequestration_coefficient: 1.0,
      biological_properties: {
        "optimal_z_target" => 29.0, "fire_resistance_rating" => 60,
        "provenance" => "provisional — 00_07 OPS.38 ⚖️ 2026-09-03: Z-window is an engineering estimate, " \
                        "calibration protocol 05_05 §8 not yet run; optimal_z_target = firmware constant, " \
                        "fire_resistance_rating = platform fire threshold"
      }
    }
    family = TreeFamily.find_or_create_by!(scientific_name: first_family[:scientific_name]) do |f|
      f.assign_attributes(first_family)
    end
    family_state = family.previously_new_record? ? "created" : "present"

    puts "[governance:bootstrap] oracle_executioner=#{actor_state} first_family=#{family_state} " \
         "tree_families=#{TreeFamily.count} slot=#{SilkenNet::DeploymentSlot.current}"
  end
end
