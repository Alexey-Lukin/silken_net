# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "#full_name" do
    it "returns first and last name" do
      user = build(:user, first_name: "Olena", last_name: "Kovalenko")
      expect(user.full_name).to eq("Olena Kovalenko")
    end

    it "falls back to email when names are blank" do
      user = build(:user, first_name: nil, last_name: nil, email_address: "test@example.com")
      expect(user.full_name).to eq("test@example.com")
    end
  end

  describe "#forest_commander?" do
    it "returns true for admin" do
      expect(build(:user, :admin).forest_commander?).to be true
    end

    it "returns true for forester" do
      expect(build(:user, :forester).forest_commander?).to be true
    end

    it "returns true for super_admin" do
      expect(build(:user, :super_admin).forest_commander?).to be true
    end

    it "returns false for investor" do
      expect(build(:user, :investor).forest_commander?).to be false
    end
  end

  describe "email normalization" do
    it "normalizes email_address to downcase" do
      user = User.new(email_address: "  ADMIN@EXAMPLE.COM  ", password: "password123", role: :admin)
      user.valid?
      expect(user.email_address).to eq("admin@example.com")
    end
  end

  describe "#touch_visit!" do
    it "updates last_seen_at when nil" do
      user = create(:user)
      user.update_columns(last_seen_at: nil)

      user.touch_visit!
      user.reload

      expect(user.last_seen_at).not_to be_nil
    end

    it "updates last_seen_at when stale (older than 5 minutes)" do
      user = create(:user)
      user.update_columns(last_seen_at: 10.minutes.ago)

      travel_to Time.current do
        user.touch_visit!
        user.reload

        expect(user.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end

    it "skips update when last_seen_at is recent (within 5 minutes)" do
      user = create(:user)
      recent_time = 2.minutes.ago
      user.update_columns(last_seen_at: recent_time)

      user.touch_visit!
      user.reload

      expect(user.last_seen_at).to be_within(1.second).of(recent_time)
    end
  end
end
