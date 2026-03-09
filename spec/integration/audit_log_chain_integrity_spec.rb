# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Audit log chain integrity and reporting" do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, :admin, organization: organization) }

  # ---------------------------------------------------------------------------
  # AuditLog model — chain hash integrity
  # ---------------------------------------------------------------------------
  describe "AuditLog chain integrity" do
    it "computes chain hash on create forming a hash chain" do
      log1 = AuditLog.create!(
        user: user,
        organization: organization,
        action: "login",
        metadata: { ip: "1.2.3.4" }
      )
      expect(log1.chain_hash).to be_present

      log2 = AuditLog.create!(
        user: user,
        organization: organization,
        action: "update_settings",
        metadata: { field: "name" }
      )
      expect(log2.chain_hash).to be_present
      expect(log2.chain_hash).not_to eq(log1.chain_hash)
    end

    it "verifies chain integrity successfully" do
      3.times do |i|
        AuditLog.create!(
          user: user,
          organization: organization,
          action: "action_#{i}",
          metadata: { step: i }
        )
      end

      result = AuditLog.verify_chain_integrity(organization.id)
      expect(result[:valid]).to be true
      expect(result[:verified_count]).to eq(3)
    end

    it "detects tampered chain" do
      log1 = AuditLog.create!(user: user, organization: organization, action: "first")
      AuditLog.create!(user: user, organization: organization, action: "second")

      # Tamper with first record
      log1.update_column(:chain_hash, "tampered_hash")

      result = AuditLog.verify_chain_integrity(organization.id)
      expect(result[:valid]).to be false
      expect(result[:broken_at]).to be_present
    end

    it "records async via Sidekiq" do
      expect(AuditLogWorker).to receive(:perform_async)
      AuditLog.record_async!(
        user_id: user.id,
        organization_id: organization.id,
        action: "async_test"
      )
    end

    it "bulk records with chain hashes" do
      entries = 3.times.map do |i|
        {
          user_id: user.id,
          organization_id: organization.id,
          action: "bulk_#{i}",
          metadata: { index: i }
        }
      end

      expect {
        AuditLog.bulk_record!(entries)
      }.to change(AuditLog, :count).by(3)

      logs = AuditLog.where(organization: organization).order(:id)
      logs.each { |log| expect(log.chain_hash).to be_present }

      result = AuditLog.verify_chain_integrity(organization.id)
      expect(result[:valid]).to be true
    end

    it "handles empty bulk record gracefully" do
      expect { AuditLog.bulk_record!([]) }.not_to change(AuditLog, :count)
    end

    it "maintains separate chains per organization" do
      org2 = create(:organization)
      user2 = create(:user, :admin, organization: org2)

      AuditLog.create!(user: user, organization: organization, action: "org1_action")
      AuditLog.create!(user: user2, organization: org2, action: "org2_action")

      result1 = AuditLog.verify_chain_integrity(organization.id)
      result2 = AuditLog.verify_chain_integrity(org2.id)

      expect(result1[:valid]).to be true
      expect(result2[:valid]).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # AuditLog scopes
  # ---------------------------------------------------------------------------
  describe "AuditLog scopes" do
    before do
      create(:audit_log, user: user, organization: organization, action: "login",
             ip_address: "192.168.1.1", created_at: 2.days.ago)
      create(:audit_log, user: user, organization: organization, action: "update_settings",
             ip_address: "10.0.0.1", created_at: 1.day.ago)
    end

    it "filters by action" do
      expect(AuditLog.by_action("login").count).to eq(1)
    end

    it "filters by user" do
      expect(AuditLog.by_user(user.id).count).to eq(2)
    end

    it "filters by IP" do
      expect(AuditLog.by_ip("192.168.1.1").count).to eq(1)
    end

    it "filters by period" do
      expect(AuditLog.for_period(3.days.ago, Time.current).count).to eq(2)
      expect(AuditLog.for_period(1.5.days.ago, Time.current).count).to eq(1)
    end
  end
end
