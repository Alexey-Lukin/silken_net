# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::MatchPolicy, type: :policy do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }
  let(:realm) { create(:codex_realm) }
  let(:left)  { create(:codex_node, realm: realm) }
  let(:right) { create(:codex_node, realm: realm) }
  let(:own_match) do
    create(:codex_match, user: user, realm: realm, left: left, right: right)
  end
  let(:other_match) do
    create(:codex_match, user: other, realm: realm, left: left, right: right)
  end

  it "permits index/create for any authenticated user" do
    expect(described_class.new(user, Codex::Match.new).index?).to be(true)
    expect(described_class.new(user, Codex::Match.new).create?).to be(true)
    expect(described_class.new(nil,  Codex::Match.new).index?).to be(false)
    expect(described_class.new(nil,  Codex::Match.new).create?).to be(false)
  end

  it "permits show only on own record" do
    expect(described_class.new(user, own_match).show?).to be(true)
    expect(described_class.new(user, other_match).show?).to be(false)
    expect(described_class.new(nil, own_match).show?).to be(false)
  end

  describe "Scope" do
    it "returns only the user's own matches" do
      own_match
      other_match
      scope = described_class::Scope.new(user, Codex::Match.all).resolve
      expect(scope).to contain_exactly(own_match)
    end

    it "returns none for anonymous" do
      own_match
      scope = described_class::Scope.new(nil, Codex::Match.all).resolve
      expect(scope.count).to eq(0)
    end
  end
end
