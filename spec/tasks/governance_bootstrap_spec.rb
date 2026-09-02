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

  it "names an empty TreeFamily loudly instead of seeding species (⚖️ founder) and reports the actor state" do
    TreeFamily.delete_all
    result = run_task

    expect(result[:err]).to include('TreeFamily порожня')
    expect(result[:out]).to include('oracle_executioner=created tree_families=0')

    create(:tree_family)
    expect(run_task[:err]).not_to include('TreeFamily порожня')
  end
end
