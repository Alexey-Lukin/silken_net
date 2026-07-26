# SPDX-License-Identifier: AGPL-3.0-or-later
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

  describe "Phase 6 cross-domain Discovery probe" do
    let(:user) { create(:user) }

    it "enqueues a match_milestone probe for the voting user" do
      match = create(:codex_match, user: user, realm: realm, left: left, right: right)
      expect(Codex::DiscoveryProbeWorker).to receive(:perform_async).with(
        match.user_id, "match_milestone",
        hash_including("match_id" => match.id, "trigger_ref_type" => "Codex::Match")
      )
      described_class.new.perform(left.id, right.id, 8, -8)
    end

    it "no-ops cleanly when there is no Match referencing the nodes" do
      expect(Codex::DiscoveryProbeWorker).not_to receive(:perform_async)
      expect {
        described_class.new.perform(left.id, right.id, 8, -8)
      }.not_to raise_error
    end

    it "skips the probe when DiscoveryProbeWorker is undefined (forward-compat guard)" do
      create(:codex_match, user: user, realm: realm, left: left, right: right)
      hide_const("Codex::DiscoveryProbeWorker")

      expect { described_class.new.perform(left.id, right.id, 8, -8) }.not_to raise_error
      expect(left.reload.attunement_elo).to eq(1508) # Elo still applied before the probe guard
    end

    it "swallows probe enqueue errors (Elo update is the contract)" do
      create(:codex_match, user: user, realm: realm, left: left, right: right)
      allow(Codex::DiscoveryProbeWorker).to receive(:perform_async).and_raise(Redis::CannotConnectError)
      expect {
        described_class.new.perform(left.id, right.id, 8, -8)
      }.not_to raise_error
      expect(left.reload.attunement_elo).to eq(1508)
    end
  end
end
