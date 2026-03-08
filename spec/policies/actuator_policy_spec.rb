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
end
