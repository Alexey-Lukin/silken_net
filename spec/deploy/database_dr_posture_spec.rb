# frozen_string_literal: true

require "rails_helper"

# DR.1 posture guard. The Cloud SQL DR promise (docs/06_06: PITR + 30-day window +
# 30 daily backups + REGIONAL HA) is CONFIGURED in terraform/database.tf, but a DR-posture
# regression is SILENT — it surfaces only post-incident, when a restore is actually needed.
# terraform_drift catches live-vs-tf drift, not a tf edit that LOWERS the posture (both move
# together); trivy doesn't know our RTO/RPO targets. This asserts the committed backup config
# meets the documented minimums, so weakening it (disable PITR, cut retention, ZONAL) fails in
# CI instead of at the worst possible moment.
RSpec.describe "Cloud SQL DR posture (terraform/database.tf ↔ 06_06)" do # rubocop:disable RSpec/DescribeClass
  let(:database_tf) { File.read(Rails.root.join("terraform/database.tf")) }
  let(:variables_tf) { File.read(Rails.root.join("terraform/variables.tf")) }

  it "point-in-time recovery is enabled" do
    expect(database_tf).to match(/point_in_time_recovery_enabled\s*=\s*true/)
  end

  it "PITR window (transaction log retention) is >= 30 days (06_06 RPO)" do
    days = database_tf[/transaction_log_retention_days\s*=\s*(\d+)/, 1]&.to_i
    expect(days).to be >= 30
  end

  it "retains >= 30 daily backups (06_06)" do
    count = database_tf[/retained_backups\s*=\s*(\d+)/, 1]&.to_i
    expect(count).to be >= 30
  end

  it "defaults to REGIONAL HA (automatic failover, not single-zone ZONAL)" do
    default = variables_tf[/variable "db_availability_type".*?default\s*=\s*"(\w+)"/m, 1]
    expect(default).to eq("REGIONAL")
  end
end
