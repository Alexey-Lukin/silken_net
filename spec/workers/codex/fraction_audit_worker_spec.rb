# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe Codex::FractionAuditWorker, type: :worker do
  let(:org)  { create(:organization) }
  let(:user) { create(:user, organization: org) }
  let(:fraction) { create(:codex_fraction, user: user) }

  it "is wired to the default queue with retry: 3" do
    expect(described_class.sidekiq_options["queue"].to_s).to eq("default")
    expect(described_class.sidekiq_options["retry"]).to eq(3)
  end

  it "writes an AuditLog with action `codex.fraction.chosen` and rich metadata" do
    expect {
      described_class.new.perform(user.id, fraction.id, 42)
    }.to change(AuditLog, :count).by(1)

    log = AuditLog.last
    expect(log.action).to eq("codex.fraction.chosen")
    expect(log.user_id).to eq(user.id)
    expect(log.organization_id).to eq(org.id)
    expect(log.auditable).to eq(fraction)
    expect(log.metadata["codex_node_id"]).to eq(fraction.codex_node_id)
    expect(log.metadata["archetype_key"]).to eq(fraction.archetype_key)
    expect(log.metadata["previous_node_id"]).to eq(42)
  end

  it "is a no-op for users without an organization (audit ledger is per-org)" do
    orphan = create(:user, organization: nil)
    orphan_fraction = create(:codex_fraction, user: orphan)
    expect {
      described_class.new.perform(orphan.id, orphan_fraction.id, nil)
    }.not_to change(AuditLog, :count)
  end

  it "is a no-op for unknown user_id / fraction_id" do
    expect {
      described_class.new.perform(0, 0, nil)
    }.not_to change(AuditLog, :count)
  end
end
