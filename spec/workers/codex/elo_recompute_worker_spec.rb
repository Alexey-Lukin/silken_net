# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::EloRecomputeWorker, type: :worker do
  let(:realm) { create(:codex_realm) }
  let!(:left)  { create(:codex_node, realm: realm, attunement_elo: 1500, match_count: 0) }
  let!(:right) { create(:codex_node, realm: realm, attunement_elo: 1500, match_count: 0) }

  it "is wired to the low queue with retry: 3" do
    expect(described_class.sidekiq_options["queue"].to_s).to eq("low")
    expect(described_class.sidekiq_options["retry"]).to eq(3)
  end

  it "applies deltas atomically and increments match_count for both nodes" do
    described_class.new.perform(left.id, right.id, 16, -16)
    expect(left.reload.attunement_elo).to eq(1516)
    expect(right.reload.attunement_elo).to eq(1484)
    expect(left.reload.match_count).to eq(1)
    expect(right.reload.match_count).to eq(1)
  end

  it "uses UPDATE … SET col = col + ? — concurrent runs both apply" do
    # Simulate a race by invoking the worker twice in sequence; both
    # increments must land (atomic UPDATE pattern, no lost-update bug).
    described_class.new.perform(left.id, right.id, 8, -8)
    described_class.new.perform(left.id, right.id, 4, -4)
    expect(left.reload.attunement_elo).to eq(1512)
    expect(right.reload.attunement_elo).to eq(1488)
    expect(left.reload.match_count).to eq(2)
  end

  it "is a no-op for unknown ids (update_all returns 0)" do
    expect {
      described_class.new.perform(0, 0, 16, -16)
    }.not_to raise_error
  end
end
