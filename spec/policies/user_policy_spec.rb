# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserPolicy do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }

  let(:subscriber) { create(:user, :subscriber, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  describe "#index?" do
    it "denies subscribers" do
      expect(described_class.new(subscriber, User).index?).to be false
    end

    it "denies foresters" do
      forester = create(:user, :forester, organization: organization)
      expect(described_class.new(forester, User).index?).to be false
    end

    it "allows admins" do
      expect(described_class.new(admin, User).index?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, User).index?).to be true
    end
  end

  describe "#show?" do
    it "allows viewing users in the same organization" do
      other_user = create(:user, :forester, organization: organization)
      expect(described_class.new(admin, other_user).show?).to be true
    end

    it "denies viewing users in a different organization" do
      other_org_user = create(:user, :forester, organization: other_org)
      expect(described_class.new(admin, other_org_user).show?).to be false
    end

    # [SEC.25 Ф2] Дзеркалення `Scope` лишилось — але дзеркалиться вже acting-org,
    # а не `scope.all`.
    it "дозволяє super_admin бачити користувача лише в контексті його організації" do
      other_org_user = create(:user, :forester, organization: other_org)

      expect(described_class.new(UserContext.new(super_admin, other_org), other_org_user).show?).to be true
      expect(described_class.new(UserContext.new(super_admin, organization), other_org_user).show?).to be false
    end

    it "allows subscriber to view users in the same org" do
      same_org_user = create(:user, :forester, organization: organization)
      expect(described_class.new(subscriber, same_org_user).show?).to be true
    end
  end

  describe "#me?" do
    it "allows any authenticated user" do
      expect(described_class.new(subscriber, subscriber).me?).to be true
    end

    it "allows admin" do
      expect(described_class.new(admin, admin).me?).to be true
    end

    it "allows super_admin" do
      expect(described_class.new(super_admin, super_admin).me?).to be true
    end
  end

  describe "#create?" do
    it "denies subscribers (inherited from ApplicationPolicy)" do
      expect(described_class.new(subscriber, User).create?).to be false
    end

    it "allows admins (inherited from ApplicationPolicy)" do
      expect(described_class.new(admin, User).create?).to be true
    end
  end

  describe "#update?" do
    it "denies subscribers (inherited from ApplicationPolicy)" do
      expect(described_class.new(subscriber, User).update?).to be false
    end

    it "allows admins (inherited from ApplicationPolicy)" do
      expect(described_class.new(admin, User).update?).to be true
    end
  end

  describe "#destroy?" do
    it "denies subscribers (inherited from ApplicationPolicy)" do
      expect(described_class.new(subscriber, User).destroy?).to be false
    end

    it "allows admins (inherited from ApplicationPolicy)" do
      expect(described_class.new(admin, User).destroy?).to be true
    end
  end

  describe "Scope" do
    let!(:org_user) { create(:user, :forester, organization: organization) }
    let!(:other_user) { create(:user, :forester, organization: other_org) }

    it "scopes to organization for admin" do
      scope = described_class::Scope.new(admin, User).resolve
      expect(scope).to include(org_user)
      expect(scope).not_to include(other_user)
    end

    # [UI.7] Пара `Scope` ⊥ `show?` мусить відповідати на ПОРОЖНІЙ контекст
    # однаково — і саме на ньому вона роками розходилась: предикат починається з
    # `organization_id.present?` і ВІДМОВЛЯЄ, а скоуп будував `IS NULL`, тобто
    # фільтр, що ЗБІГАЄТЬСЯ з org-less рядками.
    #
    # ⚠️ Ліхтар на набір несучий (`04_06 §B.2` BP 21): без org-less користувача в
    # базі `where(organization_id: nil)` віддає порожньо САМ ПО СОБІ, і пін був
    # би зелений із повністю знятим гардом.
    context "when the acting organization is missing" do
      let!(:platform_user) { create(:user, :super_admin, organization: nil) }
      let(:contextless) { UserContext.new(super_admin, nil) }

      it "resolves to nothing even though org-less rows exist" do
        expect(User.where(organization_id: nil)).to include(platform_user)

        expect(described_class::Scope.new(contextless, User).resolve).to be_empty
      end

      it "refuses the record predicate on the very row the scope would have matched" do
        expect(described_class.new(contextless, platform_user).show?).to be false
      end
    end

    it "звужує super_admin до acting-організації, і перемикання її змінює" do
      in_own = described_class::Scope.new(UserContext.new(super_admin, organization), User).resolve
      in_other = described_class::Scope.new(UserContext.new(super_admin, other_org), User).resolve

      expect(in_own).to include(org_user)
      expect(in_own).not_to include(other_user)
      expect(in_other).to include(other_user)
      expect(in_other).not_to include(org_user)
    end
  end
end
