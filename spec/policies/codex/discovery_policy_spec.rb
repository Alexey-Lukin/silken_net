# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::DiscoveryPolicy, type: :policy do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:node)  { create(:codex_node) }
  let(:own)   { create(:codex_discovery, user: user, node: node) }
  let(:foreign) { create(:codex_discovery, user: other, node: node) }

  it "permits index for any authenticated, denies for anonymous" do
    expect(described_class.new(user, Codex::Discovery.new).index?).to be(true)
    expect(described_class.new(nil,  Codex::Discovery.new).index?).to be(false)
  end

  it "show only on own record" do
    expect(described_class.new(user, own).show?).to be(true)
    expect(described_class.new(user, foreign).show?).to be(false)
    expect(described_class.new(nil, own).show?).to be(false)
  end

  it "create / manual restricted to admin+" do
    expect(described_class.new(user,  Codex::Discovery.new).create?).to be(false)
    expect(described_class.new(admin, Codex::Discovery.new).create?).to be(true)
    expect(described_class.new(user,  Codex::Discovery.new).manual?).to be(false)
    expect(described_class.new(admin, Codex::Discovery.new).manual?).to be(true)
  end

  describe "Scope" do
    it "returns own only; none for anonymous" do
      own
      foreign
      expect(described_class::Scope.new(user, Codex::Discovery.all).resolve).to contain_exactly(own)
      expect(described_class::Scope.new(nil, Codex::Discovery.all).resolve.count).to eq(0)
    end
  end
end
