# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClusterPolicy do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  let(:record) { double("Record") }

  describe "#index?" do
    it "allows investors" do
      expect(described_class.new(investor, record).index?).to be true
    end

    it "allows foresters" do
      expect(described_class.new(forester, record).index?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, record).index?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).index?).to be true
    end
  end

  describe "#show?" do
    it "allows investors" do
      expect(described_class.new(investor, record).show?).to be true
    end

    it "allows foresters" do
      expect(described_class.new(forester, record).show?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, record).show?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).show?).to be true
    end
  end

  describe "Scope" do
    let!(:own_cluster) { create(:cluster, organization: organization) }
    let!(:other_cluster) { create(:cluster, organization: other_org) }

    it "returns only org clusters for regular users" do
      scope = described_class::Scope.new(investor, Cluster).resolve
      expect(scope).to include(own_cluster)
      expect(scope).not_to include(other_cluster)
    end

    it "returns all clusters for super_admins" do
      scope = described_class::Scope.new(super_admin, Cluster).resolve
      expect(scope).to include(own_cluster, other_cluster)
    end
  end
end
