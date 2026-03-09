# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLogPolicy do
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

    it "denies foresters" do
      expect(described_class.new(forester, record).index?).to be false
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

    it "denies foresters" do
      expect(described_class.new(forester, record).show?).to be false
    end

    it "allows admins" do
      expect(described_class.new(admin, record).show?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).show?).to be true
    end
  end

  describe "Scope" do
    let(:other_admin) { create(:user, :admin, organization: other_org) }
    let!(:own_log) { create(:audit_log, user: admin, organization: organization) }
    let!(:other_log) { create(:audit_log, user: other_admin, organization: other_org) }

    it "returns only org logs for admins" do
      scope = described_class::Scope.new(admin, AuditLog).resolve
      expect(scope).to include(own_log)
      expect(scope).not_to include(other_log)
    end

    it "returns all logs for super_admins" do
      scope = described_class::Scope.new(super_admin, AuditLog).resolve
      expect(scope).to include(own_log, other_log)
    end
  end
end
