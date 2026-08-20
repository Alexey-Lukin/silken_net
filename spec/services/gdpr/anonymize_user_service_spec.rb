# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Gdpr::AnonymizeUserService do
  let(:organization) { create(:organization) }
  let!(:user) do
    create(:user, :forester,
           organization: organization,
           first_name: "Тарас", last_name: "Мельник",
           phone_number: "+380509998877",
           telegram_chat_id: "tg-42",
           password: "Sup3r!Passw0rd12", password_confirmation: "Sup3r!Passw0rd12")
  end

  describe "#perform" do
    it "scrubs every PII field of the user row to a tombstone" do
      described_class.call(user)
      user.reload

      expect(user.email_address).to eq("erased-#{user.id}@anonymized.invalid")
      expect(user.first_name).to be_nil
      expect(user.last_name).to be_nil
      expect(user.phone_number).to be_blank
      expect(user.telegram_chat_id).to be_nil
      expect(user.push_token).to be_nil
      expect(user.organization_id).to be_nil
    end

    it "destroys sessions and identities together with their encrypted secrets" do
      user.sessions.create!(ip_address: "203.0.113.7", user_agent: "FieldTablet/1.0")
      user.identities.create!(provider: "google_oauth2", uid: "g-9", access_token: "tok")

      expect { described_class.call(user) }
        .to change { user.sessions.count }.from(1).to(0)
        .and change { user.identities.count }.from(1).to(0)
    end

    # Анонімізація і Є ефективним offboarding-ом: вхід далі неможливий за
    # побудовою, окремого механізму деактивації не потрібно (SEC.16 🔗).
    it "makes login impossible afterwards" do
      described_class.call(user)
      user.reload

      expect(user.password_digest).to be_nil
      expect(user.authenticate("Sup3r!Passw0rd12")).to be(false)
      expect(user.mfa_enabled?).to be(false)
    end

    it "persists an audit trail BEFORE the mutation, with zero PII in metadata" do
      user.sessions.create!(ip_address: "203.0.113.7", user_agent: "FieldTablet/1.0")

      expect { described_class.call(user) }.to change(AuditLog, :count).by(1)

      trail = AuditLog.order(:id).last
      expect(trail.action).to eq("user_anonymized")
      expect(trail.auditable_id).to eq(user.id)
      expect(trail.metadata["sessions_destroyed"]).to eq(1)
      expect(JSON.generate(trail.metadata)).not_to include("Тарас", "203.0.113.7")
    end

    # 🔴 КЛЮЧОВИЙ пін половини: append-only ланцюг журналу ПЕРЕЖИВАЄ анонімізацію
    # неушкодженим — бо ip/user_agent старих рядків ця половина свідомо НЕ чіпає
    # (їхня доля — окремий ⚖️, докблок сервісу). Без цього піна «безсуперечна
    # половина» не мала б доказу власної безсуперечності.
    it "leaves the audit chain integrity intact" do
      AuditLog.create!(
        user_id: user.id, organization_id: organization.id,
        action: "acting_organization_switched",
        auditable_type: "Organization", auditable_id: organization.id,
        ip_address: "198.51.100.4", user_agent: "Chrome", metadata: {}
      )

      described_class.call(user)

      expect(AuditLog.verify_chain_integrity(organization.id)).to include(valid: true)
    end

    it "does not touch evidence-backed maintenance records" do
      cluster = create(:cluster, organization: organization)
      tree = create(:tree, cluster: cluster)
      record = create(:maintenance_record, maintainable: tree, user: user,
                                           action_type: :inspection, performed_at: 1.day.ago,
                                           notes: "Інспекція перед анонімізацією автора.")

      described_class.call(user)

      expect(record.reload.notes).to include("Інспекція")
      expect(record.user_id).to eq(user.id)
    end

    it "rolls back atomically when the user row cannot be scrubbed" do
      user.sessions.create!(ip_address: "203.0.113.7", user_agent: "FieldTablet/1.0")
      allow(user).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

      begin
        described_class.call(user)
      rescue ActiveRecord::RecordInvalid
        nil
      end

      expect(user.sessions.count).to eq(1)
      expect(AuditLog.where(action: "user_anonymized")).to be_empty
    end
  end
end
