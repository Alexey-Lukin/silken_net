# SPDX-License-Identifier: AGPL-3.0-or-later
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
    let(:own_record) { double("Record", organization_id: organization.id) }
    let(:other_record) { double("Record", organization_id: other_org.id) }

    it "denies investors" do
      expect(described_class.new(investor, own_record).show?).to be false
    end

    it "denies foresters" do
      expect(described_class.new(forester, own_record).show?).to be false
    end

    it "allows an admin their own org's log" do
      expect(described_class.new(admin, own_record).show?).to be true
    end

    it "denies an admin another org's log (org-scoped, not platform)" do
      expect(described_class.new(admin, other_record).show?).to be false
    end

    # [SEC.25 Ф2] Роль лишається умовою (журнал не для лісника/інвестора), але вже
    # не дає крос-тенантного доступу.
    it "дозволяє super_admin журнал лише тієї організації, в контексті якої він працює" do
      expect(described_class.new(UserContext.new(super_admin, other_org), other_record).show?).to be true
      expect(described_class.new(UserContext.new(super_admin, organization), other_record).show?).to be false
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

    it "звужує super_admin до acting-організації, і перемикання її змінює" do
      in_own = described_class::Scope.new(UserContext.new(super_admin, organization), AuditLog).resolve
      in_other = described_class::Scope.new(UserContext.new(super_admin, other_org), AuditLog).resolve

      expect(in_own).to include(own_log)
      expect(in_own).not_to include(other_log)
      expect(in_other).to include(other_log)
      expect(in_other).not_to include(own_log)
    end
  end
end
