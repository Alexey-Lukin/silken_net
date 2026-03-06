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

    it "allows blank ip_address" do
      expect(build(:audit_log, ip_address: nil)).to be_valid
      expect(build(:audit_log, ip_address: "")).to be_valid
    end

    it "rejects ip_address longer than 45 characters" do
      log = build(:audit_log, ip_address: "a" * 46)
      expect(log).not_to be_valid
      expect(log.errors[:ip_address]).to be_present
    end

    it "accepts valid IPv4 and IPv6 addresses" do
      expect(build(:audit_log, ip_address: "192.168.1.1")).to be_valid
      expect(build(:audit_log, ip_address: "::ffff:192.168.1.1")).to be_valid
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

    describe ".by_ip" do
      it "filters logs by ip_address" do
        log_a = create(:audit_log, ip_address: "10.0.0.1")
        log_b = create(:audit_log, ip_address: "10.0.0.2")

        expect(described_class.by_ip("10.0.0.1")).to include(log_a)
        expect(described_class.by_ip("10.0.0.1")).not_to include(log_b)
      end

      it "returns all logs when ip is blank" do
        log = create(:audit_log)
        expect(described_class.by_ip(nil)).to include(log)
        expect(described_class.by_ip("")).to include(log)
      end
    end

    describe ".for_period" do
      it "filters logs within a time range" do
        old_log = create(:audit_log, created_at: 10.days.ago)
        recent_log = create(:audit_log, created_at: 1.day.ago)

        result = described_class.for_period(3.days.ago, Time.current)
        expect(result).to include(recent_log)
        expect(result).not_to include(old_log)
      end

      it "returns all logs when period boundaries are blank" do
        log = create(:audit_log)
        expect(described_class.for_period(nil, nil)).to include(log)
        expect(described_class.for_period("", "")).to include(log)
      end
    end
  end

  # =========================================================================
  # SECURITY CONTEXT
  # =========================================================================
  describe "security context" do
    it "stores ip_address and user_agent" do
      log = create(:audit_log, ip_address: "203.0.113.42", user_agent: "curl/7.88.1")
      log.reload

      expect(log.ip_address).to eq("203.0.113.42")
      expect(log.user_agent).to eq("curl/7.88.1")
    end
  end

  # =========================================================================
  # METADATA (changeset)
  # =========================================================================
  describe "metadata" do
    it "stores changeset data as JSONB" do
      log = create(:audit_log, metadata: { old: "idle", new: "active" })
      log.reload

      expect(log.metadata).to eq("old" => "idle", "new" => "active")
    end
  end

  # =========================================================================
  # HOT-PATH: ASYNC & BULK WRITING
  # =========================================================================
  describe ".record_async!" do
    it "enqueues an AuditLogWorker job" do
      user = create(:user)
      attrs = {
        user_id: user.id,
        organization_id: user.organization_id,
        action: "login",
        ip_address: "10.0.0.1"
      }

      expect { described_class.record_async!(attrs) }
        .to change(AuditLogWorker.jobs, :size).by(1)
    end
  end

  describe ".bulk_record!" do
    it "creates multiple records with a single INSERT" do
      user = create(:user)
      entries = 3.times.map do |i|
        {
          user_id: user.id,
          organization_id: user.organization_id,
          action: "bulk_action_#{i}"
        }
      end

      expect { described_class.bulk_record!(entries) }
        .to change(described_class, :count).by(3)
    end

    it "does nothing when entries are blank" do
      expect { described_class.bulk_record!([]) }.not_to change(described_class, :count)
      expect { described_class.bulk_record!(nil) }.not_to change(described_class, :count)
    end
  end
end
