# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# DR.1 posture guard. The Cloud SQL DR promise (docs/06_06: PITR + 30-day window +
# 30 daily backups + REGIONAL HA) is CONFIGURED in terraform/database.tf, but a DR-posture
# regression is SILENT — it surfaces only post-incident, when a restore is actually needed.
# terraform_drift catches live-vs-tf drift, not a tf edit that LOWERS the posture (both move
# together); trivy doesn't know our RTO/RPO targets. This asserts the committed backup config
# meets the documented minimums, so weakening it (disable PITR, cut retention, ZONAL) fails in
# CI instead of at the worst possible moment.
RSpec.describe "Cloud SQL DR posture (terraform/database.tf ↔ 06_06)" do # rubocop:disable RSpec/DescribeClass
  let(:database_tf) { File.read(REPO_ROOT.join("terraform/database.tf")) }
  let(:variables_tf) { File.read(REPO_ROOT.join("terraform/variables.tf")) }

  it "point-in-time recovery is enabled" do
    expect(database_tf).to match(/point_in_time_recovery_enabled\s*=\s*true/)
  end

  # 🔴 Поріг 7 = PRE-FLEET-ПІДЛОГА, а не нова планка: ціль 30 лишається чинною для проду
  # З ДАНИМИ і повертається разом із підвищенням едиції (⚖️ founder 2026-08-31 — «на
  # production і canopy якщо буде по-різному, обіцянку в DR ми не порушимо»; інстанс один
  # на обидва слоти, тож розведення в ЧАСІ, не одночасне). Механіка межі: `edition = ENTERPRISE`
  # приймає 1..7 днів транзакційних логів (API: «must be between 1 and 7» — виміряно живим
  # apply 2026-08-31); 30 днів існують лише на ENTERPRISE_PLUS, який приймає виключно
  # `db-perf-optimized-*` тири. Доти цей приклад вимагав >= 30 при тирі `db-custom-*`,
  # тобто стеріг стан, недосяжний ЗА ПОБУДОВОЮ — гейт був зелений на конфізі, який не міг
  # створити інстанс. ⛔ Не піднімати назад без зміни edition: підніметься гейт, а не PITR.
  # ⊕ Сусідній приклад (`retained_backups >= 30`) НЕ рухається — 30 днів покриття лишаються.
  it "PITR window (transaction log retention) is >= 7 days — ENTERPRISE API ceiling (06_06 RPO)" do
    days = database_tf[/transaction_log_retention_days\s*=\s*(\d+)/, 1]&.to_i
    expect(days).to be >= 7
  end

  it "retains >= 30 daily backups (06_06)" do
    count = database_tf[/retained_backups\s*=\s*(\d+)/, 1]&.to_i
    expect(count).to be >= 30
  end

  # NOTE: this checks the tf-var DEFAULT, not the effective value — a `-var db_availability_type=ZONAL`
  # or a *.tfvars override would deploy ZONAL while this stays green. The default is the committed
  # posture; an override is an explicit operator act (and terraform_drift would surface the live state).
  it "defaults to REGIONAL HA (automatic failover, not single-zone ZONAL)" do
    default = variables_tf[/variable "db_availability_type".*?default\s*=\s*"(\w+)"/m, 1]
    expect(default).to eq("REGIONAL")
  end
end
