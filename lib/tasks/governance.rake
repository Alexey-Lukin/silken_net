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
  #   3. `TreeFamily` — ⚠️ deliberately NOT seeded: the species list of a real deployment is a
  #      ⚖️ founder decision (00_07 OPS.38), and `Tree belongs_to :tree_family` is not optional,
  #      so an empty table is named LOUDLY here instead of being filled with the demo pair.
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

    families = TreeFamily.count
    if families.zero?
      warn "[governance:bootstrap] ⚠️ TreeFamily порожня — жодне реальне дерево не провіжиться " \
           "(`Tree belongs_to :tree_family`); склад видів = ⚖️ founder, 00_07 OPS.38. Не сіється автоматично."
    end

    puts "[governance:bootstrap] oracle_executioner=#{actor_state} tree_families=#{families} slot=#{SilkenNet::DeploymentSlot.current}"
  end
end
