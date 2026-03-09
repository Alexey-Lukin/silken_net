# frozen_string_literal: true

require "rails_helper"

RSpec.describe BioContractFirmwarePolicy do
  let(:organization) { create(:organization) }
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

  describe "#create?" do
    it "denies investors" do
      expect(described_class.new(investor, record).create?).to be false
    end

    it "denies foresters" do
      expect(described_class.new(forester, record).create?).to be false
    end

    it "allows admins" do
      expect(described_class.new(admin, record).create?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).create?).to be true
    end
  end

  describe "#inventory?" do
    it "denies investors" do
      expect(described_class.new(investor, record).inventory?).to be false
    end

    it "denies foresters" do
      expect(described_class.new(forester, record).inventory?).to be false
    end

    it "allows admins" do
      expect(described_class.new(admin, record).inventory?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).inventory?).to be true
    end
  end

  describe "#deploy?" do
    it "denies investors" do
      expect(described_class.new(investor, record).deploy?).to be false
    end

    it "denies foresters" do
      expect(described_class.new(forester, record).deploy?).to be false
    end

    it "allows admins" do
      expect(described_class.new(admin, record).deploy?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).deploy?).to be true
    end
  end

  describe "Scope" do
    let!(:firmware_a) { create(:bio_contract_firmware) }
    let!(:firmware_b) { create(:bio_contract_firmware) }

    it "returns all records for admins" do
      scope = described_class::Scope.new(admin, BioContractFirmware).resolve
      expect(scope).to include(firmware_a, firmware_b)
    end

    it "returns all records for super_admins" do
      scope = described_class::Scope.new(super_admin, BioContractFirmware).resolve
      expect(scope).to include(firmware_a, firmware_b)
    end
  end
end
