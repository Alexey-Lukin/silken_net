# frozen_string_literal: true

require "rails_helper"

RSpec.describe MaintenanceRecordPolicy do
  let(:organization) { create(:organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  describe "#index?" do
    it "denies investors" do
      expect(described_class.new(investor, double("Record")).index?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, double("Record")).index?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, double("Record")).index?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, double("Record")).index?).to be true
    end
  end

  describe "#show?" do
    it "denies investors" do
      expect(described_class.new(investor, double("Record")).show?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, double("Record")).show?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, double("Record")).show?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, double("Record")).show?).to be true
    end
  end

  describe "#create?" do
    it "denies investors" do
      expect(described_class.new(investor, double("Record")).create?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, double("Record")).create?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, double("Record")).create?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, double("Record")).create?).to be true
    end
  end

  describe "#update?" do
    it "denies investors" do
      expect(described_class.new(investor, double("Record")).update?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, double("Record")).update?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, double("Record")).update?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, double("Record")).update?).to be true
    end
  end

  describe "#verify?" do
    it "denies investors" do
      expect(described_class.new(investor, double("Record")).verify?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, double("Record")).verify?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, double("Record")).verify?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, double("Record")).verify?).to be true
    end
  end

  describe "#photos?" do
    it "denies investors" do
      expect(described_class.new(investor, double("Record")).photos?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, double("Record")).photos?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, double("Record")).photos?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, double("Record")).photos?).to be true
    end
  end

  describe "Scope" do
    let(:other_org) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:gateway) { create(:gateway, cluster: cluster) }

    let!(:own_tree_record) { create(:maintenance_record, maintainable: tree, user: forester) }
    let!(:other_tree_record) { create(:maintenance_record, maintainable: create(:tree, cluster: other_cluster), user: forester) }
    let!(:own_gateway_record) { create(:maintenance_record, maintainable: gateway, user: forester) }
    let!(:other_gateway_record) { create(:maintenance_record, maintainable: create(:gateway, cluster: other_cluster), user: forester) }

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
