# frozen_string_literal: true

require "rails_helper"

RSpec.describe EwsAlertPolicy do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }

  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }

  describe "#resolve?" do
    it "denies investors" do
      alert = create(:ews_alert, cluster: cluster)
      expect(described_class.new(investor, alert).resolve?).to be false
    end

    it "allows foresters" do
      alert = create(:ews_alert, cluster: cluster)
      expect(described_class.new(forester, alert).resolve?).to be true
    end
  end

  describe "Scope" do
    let(:other_org) { create(:organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let!(:own_alert) { create(:ews_alert, cluster: cluster) }
    let!(:other_alert) { create(:ews_alert, cluster: other_cluster) }
    let!(:clusterless_alert) { create(:ews_alert, cluster: nil) }

    it "includes org alerts for user" do
      scope = described_class::Scope.new(investor, EwsAlert).resolve
      expect(scope).to include(own_alert)
      expect(scope).not_to include(other_alert)
    end

    it "includes clusterless alerts for user" do
      scope = described_class::Scope.new(investor, EwsAlert).resolve
      expect(scope).to include(clusterless_alert)
    end
  end

  describe "#index?" do
    let(:other_org) { create(:organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let!(:own_alert) { create(:ews_alert, cluster: cluster) }
    let(:admin) { create(:user, :admin, organization: organization) }
    let(:super_admin_idx) { create(:user, :super_admin) }

    it "returns true for all users" do
      expect(described_class.new(investor, own_alert).index?).to be true
      expect(described_class.new(forester, own_alert).index?).to be true
      expect(described_class.new(admin, own_alert).index?).to be true
      expect(described_class.new(super_admin_idx, own_alert).index?).to be true
    end
  end

  describe "Scope#resolve edge cases" do
    let(:other_org) { create(:organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let!(:own_alert) { create(:ews_alert, cluster: cluster) }
    let!(:other_alert) { create(:ews_alert, cluster: other_cluster) }
    let(:super_admin_scope) { create(:user, :super_admin) }

    it "returns all alerts for super_admin" do
      scope = described_class::Scope.new(super_admin_scope, EwsAlert).resolve
      expect(scope).to include(own_alert, other_alert)
    end

    it "scopes to org alerts for non-super_admin" do
      scope = described_class::Scope.new(investor, EwsAlert).resolve
      expect(scope).to include(own_alert)
      expect(scope).not_to include(other_alert)
    end
  end
end
