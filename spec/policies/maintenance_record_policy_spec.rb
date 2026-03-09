# frozen_string_literal: true

require "rails_helper"

RSpec.describe MaintenanceRecordPolicy do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  let(:record) { double("Record") }

  describe "#index?" do
    it "denies investors" do
      expect(described_class.new(investor, record).index?).to be false
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
    it "denies investors" do
      expect(described_class.new(investor, record).show?).to be false
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

  describe "#create?" do
    it "denies investors" do
      expect(described_class.new(investor, record).create?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, record).create?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, record).create?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).create?).to be true
    end
  end

  describe "#update?" do
    it "denies investors" do
      expect(described_class.new(investor, record).update?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, record).update?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, record).update?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).update?).to be true
    end
  end

  describe "#verify?" do
    it "denies investors" do
      expect(described_class.new(investor, record).verify?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, record).verify?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, record).verify?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).verify?).to be true
    end
  end

  describe "#photos?" do
    it "denies investors" do
      expect(described_class.new(investor, record).photos?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, record).photos?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, record).photos?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).photos?).to be true
    end
  end

  describe "Scope" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:other_tree) { create(:tree, cluster: other_cluster) }
    let(:gateway) { create(:gateway, cluster: cluster) }
    let(:other_gateway) { create(:gateway, cluster: other_cluster) }

    let!(:own_tree_record) { create(:maintenance_record, maintainable: tree, user: forester) }
    let!(:other_tree_record) { create(:maintenance_record, maintainable: other_tree, user: forester) }
    let!(:own_gateway_record) { create(:maintenance_record, maintainable: gateway, user: forester) }
    let!(:other_gateway_record) { create(:maintenance_record, maintainable: other_gateway, user: forester) }

    it "includes records for org trees and gateways" do
      scope = described_class::Scope.new(forester, MaintenanceRecord).resolve
      expect(scope).to include(own_tree_record, own_gateway_record)
    end

    it "excludes records from other organizations" do
      scope = described_class::Scope.new(forester, MaintenanceRecord).resolve
      expect(scope).not_to include(other_tree_record, other_gateway_record)
    end
  end
end
