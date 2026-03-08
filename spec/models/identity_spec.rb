# frozen_string_literal: true

require "rails_helper"

# Мінімальний auth_hash double для тестів OmniAuth інтеграції.
# Ruby 4 requires explicit `require 'ostruct'`; using RSpec doubles is cleaner.
def build_auth_hash(provider: "google_oauth2", uid: "uid_123", token: "tok_abc",
                    refresh_token: "ref_xyz", expires_at: 1.hour.from_now.to_i)
  credentials = double("credentials",
    token:         token,
    refresh_token: refresh_token,
    expires_at:    expires_at,
    present?:      true
  )
  double("auth_hash",
    provider:    provider,
    uid:         uid,
    credentials: credentials,
    to_h:        { "provider" => provider, "uid" => uid }
  )
end

RSpec.describe Identity, type: :model do
  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "belongs to user" do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end
  end

  # =========================================================================
  # DELEGATIONS
  # =========================================================================
  describe "delegations" do
    it "delegates organization to user" do
      identity = build(:identity)
      expect(identity.organization).to eq(identity.user.organization)
    end

    it "delegates role to user" do
      identity = build(:identity, user: build(:user, :admin))
      expect(identity.role).to eq("admin")
    end
  end

  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:identity)).to be_valid
    end

    it "requires provider" do
      expect(build(:identity, provider: nil)).not_to be_valid
    end

    it "requires uid" do
      expect(build(:identity, uid: nil)).not_to be_valid
    end

    it "enforces uid uniqueness within the same provider" do
      create(:identity, provider: "google_oauth2", uid: "same_uid")
      duplicate = build(:identity, provider: "google_oauth2", uid: "same_uid")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:uid]).to be_present
    end

    it "allows the same uid for different providers" do
      create(:identity, provider: "google_oauth2", uid: "shared_uid")
      apple = build(:identity, :apple, uid: "shared_uid")

      expect(apple).to be_valid
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe ".by_provider" do
    it "returns identities for the given provider" do
      google = create(:identity, provider: "google_oauth2")
      apple  = create(:identity, :apple)

      expect(described_class.by_provider("google_oauth2")).to include(google)
      expect(described_class.by_provider("google_oauth2")).not_to include(apple)
    end
  end

  describe ".active" do
    it "includes identities without locked_at" do
      active = create(:identity)
      expect(described_class.active).to include(active)
    end

    it "excludes locked identities" do
      locked = create(:identity, :locked)
      expect(described_class.active).not_to include(locked)
    end
  end

  describe ".locked" do
    it "includes locked identities" do
      locked = create(:identity, :locked)
      expect(described_class.locked).to include(locked)
    end

    it "excludes active identities" do
      active = create(:identity)
      expect(described_class.locked).not_to include(active)
    end
  end

  describe ".primary_identity" do
    it "returns only primary identities" do
      primary = create(:identity, :primary_identity)
      non_primary = create(:identity)

      expect(described_class.primary_identity).to include(primary)
      expect(described_class.primary_identity).not_to include(non_primary)
    end
  end

  # =========================================================================
  # SUPPORTED PROVIDERS
  # =========================================================================
  describe "SUPPORTED_PROVIDERS" do
    it "includes the four expected providers" do
      expect(Identity::SUPPORTED_PROVIDERS).to contain_exactly("google_oauth2", "facebook", "linkedin", "twitter")
    end
  end

  # =========================================================================
  # .find_or_create_from_auth_hash
  # =========================================================================
  describe ".find_or_create_from_auth_hash" do
    let(:user)      { create(:user) }
    let(:auth_hash) { build_auth_hash }

    it "creates a new identity with the given user" do
      identity = described_class.find_or_create_from_auth_hash(auth_hash, user: user)

      expect(identity).to be_persisted
      expect(identity.user).to eq(user)
      expect(identity.provider).to eq("google_oauth2")
      expect(identity.uid).to eq("uid_123")
    end

    it "stores access_token and refresh_token" do
      identity = described_class.find_or_create_from_auth_hash(auth_hash, user: user)

      expect(identity.access_token).to eq("tok_abc")
      expect(identity.refresh_token).to eq("ref_xyz")
    end

    it "stores expires_at as a Time value" do
      identity = described_class.find_or_create_from_auth_hash(auth_hash, user: user)

      expect(identity.expires_at).to be_a(Time)
    end

    it "returns the existing identity without creating a duplicate" do
      existing = create(:identity, user: user, provider: "google_oauth2", uid: "uid_123")

      expect {
        described_class.find_or_create_from_auth_hash(auth_hash, user: user)
      }.not_to change(described_class, :count)

      expect(described_class.find_or_create_from_auth_hash(auth_hash, user: user).id).to eq(existing.id)
    end

    it "updates access_token on an existing identity" do
      create(:identity, user: user, provider: "google_oauth2", uid: "uid_123",
             access_token: "old_token")
      updated_hash = build_auth_hash(token: "new_token")

      identity = described_class.find_or_create_from_auth_hash(updated_hash, user: user)

      expect(identity.access_token).to eq("new_token")
    end

    it "does not update a locked identity" do
      locked = create(:identity, user: user, provider: "google_oauth2", uid: "uid_123",
                       access_token: "old_token", locked_at: Time.current)
      updated_hash = build_auth_hash(token: "new_token")

      identity = described_class.find_or_create_from_auth_hash(updated_hash, user: user)

      expect(identity.access_token).to eq("old_token")
      expect(identity.id).to eq(locked.id)
    end

    it "sets first identity as primary for the user" do
      identity = described_class.find_or_create_from_auth_hash(auth_hash, user: user)

      expect(identity.primary?).to be true
    end

    it "does not set subsequent identities as primary" do
      create(:identity, user: user, provider: "facebook", uid: "fb_123")
      identity = described_class.find_or_create_from_auth_hash(auth_hash, user: user)

      expect(identity.primary?).to be false
    end

    it "handles missing expires_at gracefully" do
      creds_no_expiry = double("credentials",
        token:         "tok",
        refresh_token: "ref",
        expires_at:    nil,
        present?:      true
      )
      hash_without_expiry = double("auth_hash",
        provider:    "google_oauth2",
        uid:         "uid_no_expiry",
        credentials: creds_no_expiry,
        to_h:        {}
      )

      expect {
        described_class.find_or_create_from_auth_hash(hash_without_expiry, user: user)
      }.not_to raise_error
    end

    it "handles missing credentials gracefully" do
      hash_no_creds = double("auth_hash",
        provider:    "apple",
        uid:         "apple_no_creds",
        credentials: nil
      )
      identity = described_class.find_or_create_from_auth_hash(hash_no_creds, user: user)

      expect(identity).to be_persisted
      expect(identity.access_token).to be_nil
    end
  end

  # =========================================================================
  # #token_expired?
  # =========================================================================
  describe "#token_expired?" do
    it "returns false when expires_at is nil" do
      identity = build(:identity, :no_expiry)
      expect(identity.token_expired?).to be false
    end

    it "returns true when expires_at is in the past" do
      identity = build(:identity, :expired)
      expect(identity.token_expired?).to be true
    end

    it "returns false when expires_at is in the future" do
      identity = build(:identity, expires_at: 30.minutes.from_now)
      expect(identity.token_expired?).to be false
    end
  end

  # =========================================================================
  # LOCKING / UNLOCKING (Account Takeover Protection)
  # =========================================================================
  describe "#locked?" do
    it "returns false when locked_at is nil" do
      identity = build(:identity)
      expect(identity.locked?).to be false
    end

    it "returns true when locked_at is set" do
      identity = build(:identity, :locked)
      expect(identity.locked?).to be true
    end
  end

  describe "#lock!" do
    it "sets locked_at to current time" do
      identity = create(:identity)
      expect(identity.locked?).to be false

      freeze_time do
        identity.lock!
        expect(identity.locked?).to be true
        expect(identity.locked_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe "#unlock!" do
    it "clears locked_at" do
      identity = create(:identity, :locked)
      expect(identity.locked?).to be true

      identity.unlock!
      expect(identity.locked?).to be false
      expect(identity.locked_at).to be_nil
    end
  end

  # =========================================================================
  # PRIMARY IDENTITY
  # =========================================================================
  describe "#make_primary!" do
    it "sets the identity as primary" do
      identity = create(:identity)
      identity.make_primary!
      expect(identity.reload.primary?).to be true
    end

    it "unsets other identities for the same user as non-primary" do
      user = create(:user)
      first = create(:identity, user: user, primary: true)
      second = create(:identity, :facebook, user: user, primary: false)

      second.make_primary!

      expect(second.reload.primary?).to be true
      expect(first.reload.primary?).to be false
    end
  end
end
