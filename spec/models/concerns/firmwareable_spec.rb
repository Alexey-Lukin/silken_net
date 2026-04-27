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

  describe "AASM state machine transitions" do
    subject(:tree) { create(:tree) }

    describe "schedule_update event" do
      it "transitions from fw_idle to fw_pending" do
        expect(tree).to be_firmware_fw_idle
        tree.schedule_update!
        expect(tree).to be_firmware_fw_pending
      end

      it "transitions from fw_completed to fw_pending" do
        tree.update_column(:firmware_update_status, :fw_completed)
        tree.reload
        tree.schedule_update!
        expect(tree).to be_firmware_fw_pending
      end

      it "transitions from fw_failed to fw_pending" do
        tree.update_column(:firmware_update_status, :fw_failed)
        tree.reload
        tree.schedule_update!
        expect(tree).to be_firmware_fw_pending
      end

      it "raises error when transitioning from fw_downloading" do
        tree.update_column(:firmware_update_status, :fw_downloading)
        tree.reload
        expect { tree.schedule_update! }.to raise_error(AASM::InvalidTransition)
      end

      it "raises error when transitioning from fw_verifying" do
        tree.update_column(:firmware_update_status, :fw_verifying)
        tree.reload
        expect { tree.schedule_update! }.to raise_error(AASM::InvalidTransition)
      end

      it "raises error when transitioning from fw_flashing" do
        tree.update_column(:firmware_update_status, :fw_flashing)
        tree.reload
        expect { tree.schedule_update! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "start_download event" do
      it "transitions from fw_pending to fw_downloading" do
        tree.update_column(:firmware_update_status, :fw_pending)
        tree.reload
        tree.start_download!
        expect(tree).to be_firmware_fw_downloading
      end

      it "raises error when transitioning from fw_idle" do
        expect { tree.start_download! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "start_verification event" do
      it "transitions from fw_downloading to fw_verifying" do
        tree.update_column(:firmware_update_status, :fw_downloading)
        tree.reload
        tree.start_verification!
        expect(tree).to be_firmware_fw_verifying
      end

      it "raises error when transitioning from fw_pending" do
        tree.update_column(:firmware_update_status, :fw_pending)
        tree.reload
        expect { tree.start_verification! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "start_flashing event" do
      it "transitions from fw_verifying to fw_flashing" do
        tree.update_column(:firmware_update_status, :fw_verifying)
        tree.reload
        tree.start_flashing!
        expect(tree).to be_firmware_fw_flashing
      end

      it "raises error when transitioning from fw_downloading" do
        tree.update_column(:firmware_update_status, :fw_downloading)
        tree.reload
        expect { tree.start_flashing! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "complete_update event" do
      it "transitions from fw_flashing to fw_completed" do
        tree.update_column(:firmware_update_status, :fw_flashing)
        tree.reload
        tree.complete_update!
        expect(tree).to be_firmware_fw_completed
      end

      it "raises error when transitioning from fw_verifying" do
        tree.update_column(:firmware_update_status, :fw_verifying)
        tree.reload
        expect { tree.complete_update! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "fail_update event" do
      %i[fw_pending fw_downloading fw_verifying fw_flashing].each do |from_state|
        it "transitions from #{from_state} to fw_failed" do
          tree.update_column(:firmware_update_status, from_state)
          tree.reload
          tree.fail_update!
          expect(tree).to be_firmware_fw_failed
        end
      end

      it "raises error when transitioning from fw_idle" do
        expect { tree.fail_update! }.to raise_error(AASM::InvalidTransition)
      end

      it "raises error when transitioning from fw_completed" do
        tree.update_column(:firmware_update_status, :fw_completed)
        tree.reload
        expect { tree.fail_update! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "reset_firmware event" do
      it "transitions from fw_failed to fw_idle" do
        tree.update_column(:firmware_update_status, :fw_failed)
        tree.reload
        tree.reset_firmware!
        expect(tree).to be_firmware_fw_idle
      end

      it "transitions from fw_completed to fw_idle" do
        tree.update_column(:firmware_update_status, :fw_completed)
        tree.reload
        tree.reset_firmware!
        expect(tree).to be_firmware_fw_idle
      end

      it "raises error when transitioning from fw_downloading" do
        tree.update_column(:firmware_update_status, :fw_downloading)
        tree.reload
        expect { tree.reset_firmware! }.to raise_error(AASM::InvalidTransition)
      end

      it "raises error when transitioning from fw_idle" do
        expect { tree.reset_firmware! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "full OTA lifecycle (happy path)" do
      it "completes the full fw_idle -> fw_pending -> fw_downloading -> fw_verifying -> fw_flashing -> fw_completed -> fw_idle cycle" do
        expect(tree).to be_firmware_fw_idle

        tree.schedule_update!
        expect(tree).to be_firmware_fw_pending

        tree.start_download!
        expect(tree).to be_firmware_fw_downloading

        tree.start_verification!
        expect(tree).to be_firmware_fw_verifying

        tree.start_flashing!
        expect(tree).to be_firmware_fw_flashing

        tree.complete_update!
        expect(tree).to be_firmware_fw_completed

        tree.reset_firmware!
        expect(tree).to be_firmware_fw_idle
      end
    end

    describe "failure recovery lifecycle" do
      it "handles failure during download and retry" do
        tree.schedule_update!
        tree.start_download!

        tree.fail_update!
        expect(tree).to be_firmware_fw_failed

        tree.schedule_update!
        expect(tree).to be_firmware_fw_pending
      end
    end
  end
end
