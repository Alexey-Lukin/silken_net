# frozen_string_literal: true

require "rails_helper"

RSpec.describe Session, type: :model do
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
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:session)).to be_valid
    end

    it "requires ip_address" do
      expect(build(:session, ip_address: nil)).not_to be_valid
    end

    it "requires user_agent" do
      expect(build(:session, user_agent: nil)).not_to be_valid
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".stale" do
      it "returns sessions not updated in more than 30 days" do
        stale   = create(:session, :stale)
        current = create(:session)

        expect(described_class.stale).to include(stale)
        expect(described_class.stale).not_to include(current)
      end
    end

    describe ".active_in_field" do
      it "returns sessions for foresters updated within the last 24 hours" do
        forester = create(:user, :forester)
        active   = create(:session, :forester_session, user: forester, updated_at: 1.hour.ago)
        _investor_session = create(:session)

        expect(described_class.active_in_field).to include(active)
        expect(described_class.active_in_field).not_to include(_investor_session)
      end

      it "excludes forester sessions older than 24 hours" do
        forester = create(:user, :forester)
        old_session = create(:session, :forester_session, user: forester)
        old_session.update_column(:updated_at, 25.hours.ago)

        expect(described_class.active_in_field).not_to include(old_session)
      end
    end
  end

  # =========================================================================
  # INSTANCE METHODS
  # =========================================================================
  describe "#mobile_app?" do
    it "returns true when user_agent contains SilkenNetMobile (case-insensitive)" do
      session = build(:session, :mobile)
      expect(session.mobile_app?).to be true
    end

    it "returns true for mixed case" do
      session = build(:session, user_agent: "silkennetmobile/1.0")
      expect(session.mobile_app?).to be true
    end

    it "returns false for a browser user agent" do
      session = build(:session, user_agent: "Mozilla/5.0 (Macintosh)")
      expect(session.mobile_app?).to be false
    end

    it "returns false for nil user_agent" do
      session = build(:session)
      allow(session).to receive(:user_agent).and_return(nil)
      expect(session.mobile_app?).to be false
    end
  end

  describe "#touch_activity!" do
    it "updates the user's last_seen_at via the after_touch callback" do
      session = create(:session)
      session.user.update_column(:last_seen_at, nil)

      freeze_time do
        session.touch_activity!
        expect(session.user.reload.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  # =========================================================================
  # CALLBACKS
  # =========================================================================
  describe "after_create callback" do
    it "updates user last_seen_at on creation" do
      user = create(:user)
      user.update_column(:last_seen_at, nil)

      freeze_time do
        create(:session, user: user)
        expect(user.reload.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end
  end
end
