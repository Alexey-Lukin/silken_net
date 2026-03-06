# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  # --- ВАЛІДАЦІЇ ---

  describe "validations" do
    it "requires email_address" do
      user = build(:user, email_address: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to be_present
    end

    it "requires unique email_address" do
      create(:user, email_address: "taken@example.com")
      user = build(:user, email_address: "taken@example.com")
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to include("has already been taken")
    end

    it "requires valid email format" do
      user = build(:user, email_address: "not-an-email")
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to be_present
    end

    it "requires password on create" do
      user = User.new(email_address: "test@example.com", password: nil, role: :investor)
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "requires password of at least 12 characters" do
      user = build(:user, password: "short")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "accepts valid password of 12+ characters" do
      user = build(:user, password: "password12345")
      expect(user).to be_valid
    end

    it "requires role" do
      user = build(:user, role: nil)
      expect(user).not_to be_valid
      expect(user.errors[:role]).to be_present
    end

    it "validates phone_number format when present" do
      user = build(:user, phone_number: "+0123")
      expect(user).not_to be_valid
      expect(user.errors[:phone_number]).to be_present
    end

    it "allows valid E.164 phone_number" do
      user = build(:user, phone_number: "+380501234567")
      expect(user).to be_valid
    end

    it "allows blank phone_number" do
      user = build(:user, phone_number: "")
      expect(user).to be_valid
    end
  end

  # --- НОРМАЛІЗАЦІЯ ---

  describe "email normalization" do
    it "normalizes email_address to downcase and strips whitespace" do
      user = User.new(email_address: "  ADMIN@EXAMPLE.COM  ", password: "password12345", role: :admin)
      user.valid?
      expect(user.email_address).to eq("admin@example.com")
    end
  end

  describe "phone normalization" do
    it "strips non-numeric characters except +" do
      user = build(:user, phone_number: "+38 (050) 123-45-67")
      user.valid?
      expect(user.phone_number).to eq("+380501234567")
    end
  end

  # --- РОЛЬОВА МОДЕЛЬ (RBAC) ---

  describe "role enum" do
    it "defaults to investor" do
      user = User.new
      expect(user.role).to eq("investor")
    end

    it "defines all four roles" do
      expect(described_class.roles).to eq(
        "investor" => 0, "forester" => 1, "admin" => 2, "super_admin" => 3
      )
    end

    it "generates prefixed query methods" do
      user = build(:user, :admin)
      expect(user).to respond_to(:role_investor?, :role_forester?, :role_admin?, :role_super_admin?)
    end

    it "generates prefixed scopes" do
      expect(described_class).to respond_to(:role_investor, :role_forester, :role_admin, :role_super_admin)
    end
  end

  # --- #full_name ---

  describe "#full_name" do
    it "returns first and last name" do
      user = build(:user, first_name: "Olena", last_name: "Kovalenko")
      expect(user.full_name).to eq("Olena Kovalenko")
    end

    it "returns only first name when last name is blank" do
      user = build(:user, first_name: "Olena", last_name: "")
      expect(user.full_name).to eq("Olena")
    end

    it "returns only last name when first name is blank" do
      user = build(:user, first_name: "", last_name: "Kovalenko")
      expect(user.full_name).to eq("Kovalenko")
    end

    it "falls back to email when names are blank" do
      user = build(:user, first_name: nil, last_name: nil, email_address: "test@example.com")
      expect(user.full_name).to eq("test@example.com")
    end
  end

  # --- #forest_commander? ---

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

  # --- #access_level (Series D RBAC) ---

  describe "#access_level" do
    it "returns :system for super_admin" do
      user = create(:user, :super_admin)
      expect(user.access_level).to eq(:system)
    end

    it "returns :organization for admin with organization" do
      user = create(:user, :admin)
      expect(user.access_level).to eq(:organization)
    end

    it "returns :read_only for admin without organization" do
      user = create(:user, :admin, organization: nil)
      expect(user.access_level).to eq(:read_only)
    end

    it "returns :field for forester with organization" do
      user = create(:user, :forester)
      expect(user.access_level).to eq(:field)
    end

    it "returns :read_only for forester without organization" do
      user = create(:user, :forester, organization: nil)
      expect(user.access_level).to eq(:read_only)
    end

    it "returns :read_only for investor" do
      user = create(:user, :investor)
      expect(user.access_level).to eq(:read_only)
    end

    it "returns :system for super_admin regardless of organization" do
      user = create(:user, :super_admin, organization: nil)
      expect(user.access_level).to eq(:system)
    end
  end

  # --- #super_admin? ---

  describe "#super_admin?" do
    it "returns true for super_admin role" do
      expect(build(:user, :super_admin).super_admin?).to be true
    end

    it "returns false for admin role" do
      expect(build(:user, :admin).super_admin?).to be false
    end

    it "returns false for investor role" do
      expect(build(:user, :investor).super_admin?).to be false
    end
  end

  # --- #organization_admin? ---

  describe "#organization_admin?" do
    it "returns true for admin with organization" do
      user = create(:user, :admin)
      expect(user.organization_admin?).to be true
    end

    it "returns false for admin without organization" do
      user = create(:user, :admin, organization: nil)
      expect(user.organization_admin?).to be false
    end

    it "returns false for super_admin (not scoped to organization)" do
      user = create(:user, :super_admin)
      expect(user.organization_admin?).to be false
    end

    it "returns false for forester even with organization" do
      user = create(:user, :forester)
      expect(user.organization_admin?).to be false
    end

    it "returns false for investor" do
      user = create(:user, :investor)
      expect(user.organization_admin?).to be false
    end
  end

  # --- #touch_visit! ---

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

  # --- .oracle_executioner ---

  describe ".oracle_executioner" do
    it "returns user with oracle email" do
      oracle = create(:user, email_address: "oracle.executioner@system.silken.net")
      expect(described_class.oracle_executioner).to eq(oracle)
    end

    it "returns nil when oracle does not exist" do
      expect(described_class.oracle_executioner).to be_nil
    end
  end

  # --- СКОУПИ ---

  describe ".notifiable" do
    it "includes users with phone_number" do
      user = create(:user, phone_number: "+380501234567")
      expect(described_class.notifiable).to include(user)
    end

    it "includes users with telegram_chat_id" do
      user = create(:user, phone_number: nil)
      user.update_columns(telegram_chat_id: "12345")
      expect(described_class.notifiable).to include(user)
    end

    it "excludes users without phone or telegram" do
      user = create(:user, phone_number: nil, telegram_chat_id: nil)
      expect(described_class.notifiable).not_to include(user)
    end
  end

  describe ".active_foresters" do
    it "includes foresters seen within the last hour" do
      user = create(:user, :forester)
      user.update_columns(last_seen_at: 30.minutes.ago)
      expect(described_class.active_foresters).to include(user)
    end

    it "excludes foresters not seen within the last hour" do
      user = create(:user, :forester)
      user.update_columns(last_seen_at: 2.hours.ago)
      expect(described_class.active_foresters).not_to include(user)
    end

    it "excludes non-foresters even if recently seen" do
      user = create(:user, :admin)
      user.update_columns(last_seen_at: 5.minutes.ago)
      expect(described_class.active_foresters).not_to include(user)
    end
  end

  # --- АСОЦІАЦІЇ ---

  describe "associations" do
    it "belongs to organization optionally" do
      user = build(:user, organization: nil)
      expect(user).to be_valid
    end

    it "has many sessions" do
      assoc = described_class.reflect_on_association(:sessions)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end

    it "has many identities" do
      assoc = described_class.reflect_on_association(:identities)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end

    it "has many wallets through organization" do
      assoc = described_class.reflect_on_association(:wallets)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:through]).to eq(:organization)
    end

    it "has many maintenance_records with restrict" do
      assoc = described_class.reflect_on_association(:maintenance_records)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:restrict_with_error)
    end

    it "has many audit_logs with restrict" do
      assoc = described_class.reflect_on_association(:audit_logs)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:restrict_with_error)
    end
  end
end
