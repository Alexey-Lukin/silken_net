# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::PresenceTracker do
  let(:user) { create(:user) }
  let(:tree) { create(:tree) }

  before do
    Kredis.redis(config: :shared).del(described_class.send(:key_for, tree.id))
  end

  it "registers + lists observers" do
    described_class.touch(user_id: user.id, tree_id: tree.id)
    expect(described_class.observers_for_tree(tree.id)).to include(user.id)
    expect(described_class.observed?(tree.id)).to be(true)
  end

  it "is idempotent on duplicate touch (Set semantics)" do
    3.times { described_class.touch(user_id: user.id, tree_id: tree.id) }
    expect(described_class.observers_for_tree(tree.id).size).to eq(1)
  end

  it "removes via leave" do
    described_class.touch(user_id: user.id, tree_id: tree.id)
    described_class.leave(user_id: user.id, tree_id: tree.id)
    expect(described_class.observed?(tree.id)).to be(false)
  end

  it "applies a TTL roughly equal to TTL constant" do
    described_class.touch(user_id: user.id, tree_id: tree.id)
    ttl = Kredis.redis(config: :shared).ttl(described_class.send(:key_for, tree.id))
    expect(ttl).to be_between(1, described_class::TTL.to_i)
  end

  it "returns [] / false safely on Redis errors" do
    allow(Kredis).to receive(:redis).and_raise(Redis::CannotConnectError)
    expect(described_class.touch(user_id: user.id, tree_id: tree.id)).to be(false)
    expect(described_class.observers_for_tree(tree.id)).to eq([])
    expect(described_class.observed?(tree.id)).to be(false)
  end

  it "noop on blank inputs" do
    expect(described_class.touch(user_id: nil, tree_id: tree.id)).to be(false)
    expect(described_class.leave(user_id: nil, tree_id: tree.id)).to be(false)
    expect(described_class.observers_for_tree(nil)).to eq([])
  end
end
