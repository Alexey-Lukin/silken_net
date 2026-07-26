# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Admin::NodePolicy, type: :policy do
  let(:investor)    { create(:user, role: :investor) }
  let(:forester)    { create(:user, role: :forester) }
  let(:admin)       { create(:user, :admin) }
  let(:super_admin) { create(:user, :super_admin) }
  let(:node)        { create(:codex_node) }

  describe "read access (admin+)" do
    %i[index? show?].each do |action|
      it "#{action} denies investor + forester" do
        expect(described_class.new(investor, node).public_send(action)).to be(false)
        expect(described_class.new(forester, node).public_send(action)).to be(false)
      end

      it "#{action} allows admin + super_admin" do
        expect(described_class.new(admin, node).public_send(action)).to be(true)
        expect(described_class.new(super_admin, node).public_send(action)).to be(true)
      end
    end
  end

  describe "update? (admin+)" do
    it "allows admin and super_admin, denies investor + forester" do
      expect(described_class.new(admin, node).update?).to be(true)
      expect(described_class.new(super_admin, node).update?).to be(true)
      expect(described_class.new(forester, node).update?).to be(false)
      expect(described_class.new(investor, node).update?).to be(false)
    end
  end

  describe "create? / destroy? (super_admin only)" do
    it "denies admin, allows super_admin" do
      expect(described_class.new(admin, node).create?).to be(false)
      expect(described_class.new(admin, node).destroy?).to be(false)
      expect(described_class.new(super_admin, node).create?).to be(true)
      expect(described_class.new(super_admin, node).destroy?).to be(true)
    end
  end

  describe "Scope" do
    let!(:n1) { create(:codex_node) }
    let!(:n2) { create(:codex_node) }

    it "returns all rows to admin" do
      scope = described_class::Scope.new(admin, Codex::Node).resolve
      expect(scope).to include(n1, n2)
    end

    it "returns none to investor / forester / anonymous" do
      expect(described_class::Scope.new(investor, Codex::Node).resolve.count).to eq(0)
      expect(described_class::Scope.new(forester, Codex::Node).resolve.count).to eq(0)
      expect(described_class::Scope.new(nil, Codex::Node).resolve.count).to eq(0)
    end
  end
end
