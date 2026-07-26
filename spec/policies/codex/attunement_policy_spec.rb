# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::AttunementPolicy do
  let(:org)        { create(:organization) }
  let(:user)       { create(:user, organization: org) }
  let(:other_user) { create(:user, organization: org) }
  let(:node)       { create(:codex_node) }
  let(:own)        { create(:codex_attunement, user: user, node: node) }

  it "permits index/show/create for any authenticated user" do
    expect(described_class.new(user, own)).to be_index
    expect(described_class.new(user, own)).to be_show
    expect(described_class.new(user, Codex::Attunement.new)).to be_create
  end

  it "denies index/show for anonymous" do
    expect(described_class.new(nil, own)).not_to be_index
    expect(described_class.new(nil, own)).not_to be_show
  end

  it "denies create for anonymous" do
    expect(described_class.new(nil, Codex::Attunement.new)).not_to be_create
  end

  it "permits destroy/update only for the owner" do
    expect(described_class.new(user, own)).to be_destroy
    expect(described_class.new(user, own)).to be_update
    expect(described_class.new(other_user, own)).not_to be_destroy
    expect(described_class.new(other_user, own)).not_to be_update
  end

  it "denies destroy/update for anonymous users" do
    expect(described_class.new(nil, own)).not_to be_destroy
    expect(described_class.new(nil, own)).not_to be_update
  end

  it "Scope#resolve returns the full collection" do
    create(:codex_attunement, user: user, node: node)
    create(:codex_attunement, user: other_user, node: node)
    expect(described_class::Scope.new(user, Codex::Attunement.all).resolve.count).to eq(2)
  end
end
