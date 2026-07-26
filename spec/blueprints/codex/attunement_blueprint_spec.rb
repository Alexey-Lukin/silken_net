# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::AttunementBlueprint do
  let(:user) { create(:user) }
  let(:node) { create(:codex_node) }
  let(:attunement) { create(:codex_attunement, user: user, node: node, intensity: 4, quote: "resonance") }

  it "renders all fields" do
    payload = described_class.render_as_hash(attunement)

    aggregate_failures do
      expect(payload[:id]).to eq(attunement.id)
      expect(payload[:user_id]).to eq(user.id)
      expect(payload[:codex_node_id]).to eq(node.id)
      expect(payload[:intensity]).to eq(4)
      expect(payload[:quote]).to eq("resonance")
      expect(payload[:started_at]).to be_present
      expect(payload[:created_at]).to be_present
    end
  end
end
