# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLog, type: :model do
  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "belongs to user" do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it "belongs to organization" do
      assoc = described_class.reflect_on_association(:organization)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it "belongs to auditable polymorphically (optional)" do
      assoc = described_class.reflect_on_association(:auditable)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:polymorphic]).to be true
      expect(assoc.options[:optional]).to be true
    end
  end

  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:audit_log)).to be_valid
    end

    it "requires action" do
      log = build(:audit_log, action: nil)
      expect(log).not_to be_valid
      expect(log.errors[:action]).to be_present
    end

    it "is valid without an auditable target (action log without a subject)" do
      expect(build(:audit_log)).to be_valid
    end

    it "is valid with an auditable target" do
      expect(build(:audit_log, :with_auditable)).to be_valid
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".recent" do
      it "orders by created_at descending" do
        old_log = create(:audit_log, created_at: 2.hours.ago)
        new_log = create(:audit_log, created_at: 1.minute.ago)

        result = described_class.recent
        expect(result.first).to eq(new_log)
        expect(result.last).to eq(old_log)
      end
    end

    describe ".by_action" do
      it "filters logs by the given action" do
        login_log  = create(:audit_log, action: "login")
        update_log = create(:audit_log, action: "update_settings")

        expect(described_class.by_action("login")).to include(login_log)
        expect(described_class.by_action("login")).not_to include(update_log)
      end

      it "returns all logs when action is blank" do
        log = create(:audit_log, action: "login")

        expect(described_class.by_action(nil)).to include(log)
        expect(described_class.by_action("")).to include(log)
      end
    end

    describe ".by_user" do
      it "filters logs by user_id" do
        user_a    = create(:user)
        user_b    = create(:user)
        log_a = create(:audit_log, user: user_a, organization: user_a.organization)
        log_b = create(:audit_log, user: user_b, organization: user_b.organization)

        expect(described_class.by_user(user_a.id)).to include(log_a)
        expect(described_class.by_user(user_a.id)).not_to include(log_b)
      end

      it "returns all logs when user_id is blank" do
        log = create(:audit_log)

        expect(described_class.by_user(nil)).to include(log)
        expect(described_class.by_user("")).to include(log)
      end
    end
  end
end
