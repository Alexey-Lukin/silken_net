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
      expect(build(:audit_log, auditable: nil)).to be_valid
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

    describe ".archived" do
      it "returns only logs with ipfs_cid" do
        archived_log = create(:audit_log)
        archived_log.update_column(:ipfs_cid, "QmTestCid")
        unarchived_log = create(:audit_log)

        expect(described_class.archived).to include(archived_log)
        expect(described_class.archived).not_to include(unarchived_log)
      end
    end

    describe ".not_archived" do
      it "returns only logs without ipfs_cid" do
        archived_log = create(:audit_log)
        archived_log.update_column(:ipfs_cid, "QmTestCid")
        unarchived_log = create(:audit_log)

        expect(described_class.not_archived).to include(unarchived_log)
        expect(described_class.not_archived).not_to include(archived_log)
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

    it "computes chain_hash for each entry in bulk" do
      user = create(:user)
      entries = 3.times.map do |i|
        {
          user_id: user.id,
          organization_id: user.organization_id,
          action: "bulk_action_#{i}"
        }
      end

      described_class.bulk_record!(entries)

      logs = described_class.where(action: "bulk_action_0".."bulk_action_2").order(:id)
      expect(logs.all? { |l| l.chain_hash.present? }).to be true
      expect(logs.map(&:chain_hash).uniq.size).to eq(3) # all hashes are unique
    end
  end

  # =========================================================================
  # CHAIN HASH (Immutable Integrity)
  # =========================================================================
  describe "chain_hash" do
    it "computes chain_hash on create" do
      log = create(:audit_log)
      expect(log.chain_hash).to be_present
      expect(log.chain_hash.length).to eq(64) # SHA-256 hex
    end

    it "chains hashes sequentially per organization" do
      user = create(:user)
      log1 = create(:audit_log, user: user, organization: user.organization, action: "first")
      log2 = create(:audit_log, user: user, organization: user.organization, action: "second")

      expect(log1.chain_hash).not_to eq(log2.chain_hash)

      # Verify that log2's hash depends on log1's hash
      expected_payload = log2.chain_payload
      expected_hash = Digest::SHA256.hexdigest("#{log1.chain_hash}|#{expected_payload}")
      expect(log2.chain_hash).to eq(expected_hash)
    end

    it "uses GENESIS as previous hash for first record in organization" do
      log = create(:audit_log)
      expected = Digest::SHA256.hexdigest("#{AuditLog::GENESIS_HASH}|#{log.chain_payload}")
      expect(log.chain_hash).to eq(expected)
    end

    it "maintains separate chains per organization" do
      user_a = create(:user)
      user_b = create(:user)

      log_a = create(:audit_log, user: user_a, organization: user_a.organization)
      log_b = create(:audit_log, user: user_b, organization: user_b.organization)

      # Both are first in their org → both use GENESIS
      expected_a = Digest::SHA256.hexdigest("#{AuditLog::GENESIS_HASH}|#{log_a.chain_payload}")
      expected_b = Digest::SHA256.hexdigest("#{AuditLog::GENESIS_HASH}|#{log_b.chain_payload}")

      expect(log_a.chain_hash).to eq(expected_a)
      expect(log_b.chain_hash).to eq(expected_b)
    end
  end

  # =========================================================================
  # CHAIN INTEGRITY VERIFICATION
  # =========================================================================
  describe ".verify_chain_integrity" do
    it "returns valid for a correct chain" do
      user = create(:user)
      3.times { |i| create(:audit_log, user: user, organization: user.organization, action: "action_#{i}") }

      result = described_class.verify_chain_integrity(user.organization_id)
      expect(result[:valid]).to be true
      expect(result[:verified_count]).to eq(3)
    end

    it "detects tampering (modified record)" do
      user = create(:user)
      log1 = create(:audit_log, user: user, organization: user.organization, action: "original")
      create(:audit_log, user: user, organization: user.organization, action: "second")

      # Tamper with first record
      log1.update_column(:chain_hash, "tampered_hash_value")

      result = described_class.verify_chain_integrity(user.organization_id)
      expect(result[:valid]).to be false
      expect(result[:broken_at]).to eq(log1.id)
    end

    it "returns valid with zero records" do
      result = described_class.verify_chain_integrity(999_999)
      expect(result[:valid]).to be true
      expect(result[:verified_count]).to eq(0)
    end
  end
end
