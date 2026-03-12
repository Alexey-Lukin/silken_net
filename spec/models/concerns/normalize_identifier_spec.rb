# frozen_string_literal: true

require "rails_helper"

RSpec.describe NormalizeIdentifier do
  describe ".normalize_identifier" do
    # Тестуємо через Tree, Gateway, HardwareKey які включають NormalizeIdentifier
    context "with Tree (did)" do
      it "normalizes did to uppercase" do
        tree = build(:tree, did: "snet-aabbccdd")
        expect(tree.did).to eq("SNET-AABBCCDD")
      end

      it "strips whitespace from did" do
        tree = build(:tree, did: "  SNET-AABBCCDD  ")
        expect(tree.did).to eq("SNET-AABBCCDD")
      end
    end

    context "with Gateway (uid)" do
      it "normalizes uid to uppercase" do
        gateway = build(:gateway, uid: "snet-q-aabbccdd")
        expect(gateway.uid).to eq("SNET-Q-AABBCCDD")
      end

      it "strips whitespace from uid" do
        gateway = build(:gateway, uid: "  SNET-Q-AABBCCDD  ")
        expect(gateway.uid).to eq("SNET-Q-AABBCCDD")
      end
    end

    context "with HardwareKey (device_uid)" do
      it "normalizes device_uid to uppercase" do
        key = build(:hardware_key, device_uid: "snet-aabbccdd")
        expect(key.device_uid).to eq("SNET-AABBCCDD")
      end

      it "strips whitespace from device_uid" do
        key = build(:hardware_key, device_uid: "  SNET-AABBCCDD  ")
        expect(key.device_uid).to eq("SNET-AABBCCDD")
      end
    end
  end
end
