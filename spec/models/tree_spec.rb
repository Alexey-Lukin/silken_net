# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tree, type: :model do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "after_create callbacks" do
    it "creates a wallet after creation" do
      tree = create(:tree)

      expect(tree.wallet).to be_present
      expect(tree.wallet.balance).to eq(0)
    end
  end

  describe "DID validation" do
    it "normalizes DID to uppercase" do
      tree = build(:tree, did: "snet-00000abc")
      tree.valid?

      expect(tree.did).to eq("SNET-00000ABC")
    end

    it "accepts valid hardware DID format" do
      tree = build(:tree, did: "SNET-1A2B3C4D")
      expect(tree).to be_valid
    end

    it "rejects DID that does not match hardware format" do
      tree = build(:tree, did: "INVALID-DID")
      expect(tree).not_to be_valid
      expect(tree.errors[:did]).to be_present
    end

    it "rejects DID with wrong length" do
      tree = build(:tree, did: "SNET-123")
      expect(tree).not_to be_valid
    end
  end

  describe "#mark_seen!" do
    it "updates last_seen_at" do
      tree = create(:tree)
      expect(tree.last_seen_at).to be_nil

      tree.mark_seen!
      tree.reload

      expect(tree.last_seen_at).not_to be_nil
      expect(tree.last_seen_at).to be_within(2.seconds).of(Time.current)
    end

    it "updates latest_voltage_mv when provided" do
      tree = create(:tree)

      tree.mark_seen!(4100)
      tree.reload

      expect(tree.latest_voltage_mv).to eq(4100)
    end

    it "never regresses last_seen_at (GREATEST semantics)" do
      tree = create(:tree)
      future_time = 1.hour.from_now

      tree.update_columns(last_seen_at: future_time)
      tree.mark_seen!
      tree.reload

      expect(tree.last_seen_at).to be_within(2.seconds).of(future_time)
    end
  end

  describe "#charge_percentage" do
    it "returns 0 when voltage is zero" do
      tree = build(:tree, latest_voltage_mv: nil)
      expect(tree.charge_percentage).to eq(0)
    end

    it "returns 0 at minimum voltage" do
      tree = build(:tree, latest_voltage_mv: Tree::VCAP_MIN_MV)
      expect(tree.charge_percentage).to eq(0)
    end

    it "returns 100 at maximum voltage" do
      tree = build(:tree, latest_voltage_mv: Tree::VCAP_MAX_MV)
      expect(tree.charge_percentage).to eq(100)
    end

    it "returns correct percentage for mid-range voltage" do
      mid_mv = (Tree::VCAP_MIN_MV + Tree::VCAP_MAX_MV) / 2
      tree = build(:tree, latest_voltage_mv: mid_mv)
      expect(tree.charge_percentage).to eq(50)
    end

    it "clamps below minimum to 0" do
      tree = build(:tree, latest_voltage_mv: 2000)
      expect(tree.charge_percentage).to eq(0)
    end
  end

  describe "#low_power?" do
    it "returns true below LOW_POWER_MV" do
      tree = build(:tree, latest_voltage_mv: Tree::LOW_POWER_MV - 1)
      expect(tree).to be_low_power
    end

    it "returns false at LOW_POWER_MV" do
      tree = build(:tree, latest_voltage_mv: Tree::LOW_POWER_MV)
      expect(tree).not_to be_low_power
    end

    it "returns false when voltage is zero (no data)" do
      tree = build(:tree, latest_voltage_mv: nil)
      expect(tree).not_to be_low_power
    end
  end
end
