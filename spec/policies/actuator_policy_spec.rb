# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActuatorPolicy do
  let(:organization) { create(:organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }

  describe "#index?" do
    it "denies investors" do
      expect(described_class.new(investor, Actuator).index?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, Actuator).index?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, Actuator).index?).to be true
    end
  end

  describe "#execute?" do
    it "denies investors" do
      expect(described_class.new(investor, Actuator).execute?).to be false
    end

    it "allows foresters" do
      expect(described_class.new(forester, Actuator).execute?).to be true
    end
  end

  describe "#show? edge cases" do
    let(:super_admin) { create(:user, :super_admin) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:gateway) { create(:gateway, cluster: cluster) }
    let(:actuator) { create(:actuator, gateway: gateway) }

    it "allows forester" do
      expect(described_class.new(forester, actuator).show?).to be true
    end

    it "denies investor" do
      expect(described_class.new(investor, actuator).show?).to be false
    end

    it "allows admin" do
      expect(described_class.new(admin, actuator).show?).to be true
    end

    it "allows super_admin" do
      expect(described_class.new(super_admin, actuator).show?).to be true
    end
  end

  describe "Scope#resolve" do
    let(:super_admin) { create(:user, :super_admin) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:gateway) { create(:gateway, cluster: cluster) }
    let!(:own_actuator) { create(:actuator, gateway: gateway) }
    let(:other_org) { create(:organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let(:other_gateway) { create(:gateway, cluster: other_cluster) }
    let!(:other_actuator) { create(:actuator, gateway: other_gateway) }

    it "returns all actuators for super_admin" do
      scope = described_class::Scope.new(super_admin, Actuator).resolve
      expect(scope).to include(own_actuator)
      expect(scope).to include(other_actuator)
    end

    it "scopes to org actuators for non-super_admin" do
      scope = described_class::Scope.new(investor, Actuator).resolve
      expect(scope).to include(own_actuator)
      expect(scope).not_to include(other_actuator)
    end

    it "scopes to org actuators for forester" do
      scope = described_class::Scope.new(forester, Actuator).resolve
      expect(scope).to include(own_actuator)
      expect(scope).not_to include(other_actuator)
    end
  end
end
