# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "rake"

# [OPS.38] The production bootstrap composition, run as the REAL task (a fresh Rake
# application loading `lib/tasks/governance.rake`), never as a copy of its body.
#
# 🔴 Why this is a carrier and not a courtesy: `oracle_executioner` is the loudest SILENT
# dependency in the tree — `Auditable#record_money_audit_trail` returns early with a WARN when
# the row is absent, so a production database bootstrapped without it runs every money
# transition without a tamper-evident trail, and nothing else in the suite would notice.
# The hook that calls this task (`.kamal/hooks/post-deploy`) re-runs it after EVERY deploy,
# so idempotence is not a nicety: a second row, or a touched first row, would be a defect
# delivered on the second deploy.
#
# 🔒 Ceiling: the hook itself (shell → `kamal app exec`) is judged only for syntax
# (`scripts/shell_parse_check.rb`); its first real run is a deploy.
RSpec.describe "governance:bootstrap" do # rubocop:disable RSpec/DescribeClass
  def run_task
    previous = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/governance.rake").to_s
    out = StringIO.new
    err = StringIO.new
    orig_out, orig_err = $stdout, $stderr
    begin
      $stdout = out
      $stderr = err
      Rake::Task["governance:bootstrap"].invoke
    ensure
      $stdout, $stderr = orig_out, orig_err
      Rake.application = previous
    end
    { out: out.string, err: err.string }
  end

  let(:actor_scope) { User.where(email_address: User::ORACLE_EXECUTIONER_EMAIL) }

  it "creates the money-audit actor exactly once and converges on a second run" do
    expect { run_task }.to change(actor_scope, :count).from(0).to(1)
    expect(User.oracle_executioner).to be_super_admin

    expect { run_task }.not_to change(User, :count)
  end

  it "never touches an actor that already exists (password, role and timestamps stay)" do
    existing = create(:user, email_address: User::ORACLE_EXECUTIONER_EMAIL, role: :super_admin,
                             password: "operator-chosen-pw")
    stamp = existing.updated_at

    run_task

    expect(existing.reload.updated_at).to eq(stamp)
    expect(existing.authenticate("operator-chosen-pw")).to be_truthy
  end

  it "upserts the governance parameters as part of the composition" do
    run_task

    expect(SystemParameter.where(key: %w[dynamic_tax_rate insurance_pool_threshold]).count).to eq(2)
  end

  # ⚖️ [OPS.38, 2026-09-03] The first deployment's species is FIXED by canon (01_01 §6 Stage 4 —
  # the anchor is tuned to Pinus sylvestris), so the roster is one family; its numbers are
  # declared provisional IN THE ROW, because the calibration protocol (05_05 §8) has not run.
  it "seeds Pinus sylvestris exactly once with declared-provisional numbers and converges on a second run" do
    TreeFamily.delete_all
    result = run_task
    family = TreeFamily.find_by!(scientific_name: "Pinus sylvestris")

    aggregate_failures do
      expect(TreeFamily.count).to eq(1)
      expect(family.carbon_sequestration_coefficient).to eq(1.0)  # ratified default (ARCH.84), not the demo's 0.8
      expect(family.effective_optimal_z_target).to eq(29.0)        # firmware BioContract::OPTIMAL_Z_TARGET
      expect(family.fire_resistance_rating).to eq(60)              # platform fire threshold
      expect(family.biological_properties["provenance"]).to include("provisional")
      expect(result[:out]).to include("first_family=created tree_families=1")
    end

    expect { run_task }.not_to change(TreeFamily, :count)
    expect(run_task[:out]).to include("first_family=present")
  end

  it "never touches a family that already exists (operator-calibrated numbers stay)" do
    existing = create(:tree_family, scientific_name: "Pinus sylvestris",
                                    critical_z_min: 7.5, critical_z_max: 42.0)
    stamp = existing.updated_at

    run_task

    expect(existing.reload.updated_at).to eq(stamp)
    expect(existing.critical_z_min).to eq(7.5)
  end
end
