# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwareable do
  describe "when included in Tree" do
    it "defines firmware_update_status enum" do
      tree = build(:tree)
      expect(tree).to respond_to(:firmware_update_status)
    end

    it "defaults to fw_idle" do
      tree = build(:tree)
      expect(tree.firmware_update_status).to eq("fw_idle")
    end

    it "supports all OTA lifecycle states" do
      tree = build(:tree)
      %w[fw_idle fw_pending fw_downloading fw_verifying fw_flashing fw_failed fw_completed].each do |state|
        tree.firmware_update_status = state
        expect(tree.firmware_update_status).to eq(state)
      end
    end

    it "provides prefixed query methods" do
      tree = build(:tree, firmware_update_status: :fw_downloading)
      expect(tree).to be_firmware_fw_downloading
      expect(tree).not_to be_firmware_fw_idle
    end
  end

  describe "when included in Gateway" do
    it "defines firmware_update_status enum" do
      gateway = build(:gateway)
      expect(gateway).to respond_to(:firmware_update_status)
    end

    it "defaults to fw_idle" do
      gateway = build(:gateway)
      expect(gateway.firmware_update_status).to eq("fw_idle")
    end

    it "supports all OTA lifecycle states" do
      gateway = build(:gateway)
      %w[fw_idle fw_pending fw_downloading fw_verifying fw_flashing fw_failed fw_completed].each do |state|
        gateway.firmware_update_status = state
        expect(gateway.firmware_update_status).to eq(state)
      end
    end

    it "provides prefixed query methods" do
      gateway = build(:gateway, firmware_update_status: :fw_flashing)
      expect(gateway).to be_firmware_fw_flashing
      expect(gateway).not_to be_firmware_fw_idle
    end
  end

  it "shares the same enum values between Tree and Gateway" do
    tree_values = Tree.firmware_update_statuses
    gateway_values = Gateway.firmware_update_statuses

    expect(tree_values).to eq(gateway_values)
  end
end
