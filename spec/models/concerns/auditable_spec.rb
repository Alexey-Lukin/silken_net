# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.57] Контракт концерну: актор-резолюція (людський → системний → WARN-skip),
# auditable-обробка (AR-сутність або nil для безсуб'єктних дій), archive-флаг.
RSpec.describe Auditable do
  let(:host) do
    Class.new do
      include Auditable
    end.new
  end

  let!(:oracle) do
    create(:user, :super_admin, email_address: "oracle.executioner@system.silken.net",
                                first_name: "Oracle", last_name: "Executioner")
  end

  describe "#record_audit_trail!" do
    it "uses the explicit human initiator when given" do
      human = create(:user)

      host.record_audit_trail!(action: "probe", organization_id: nil,
                               auditable: nil, user_id: human.id)

      attrs = AuditLogWorker.jobs.last["args"].first
      expect(attrs["user_id"]).to eq(human.id)
      expect(attrs["auditable_type"]).to be_nil
    end

    it "falls back to the system actor (oracle_executioner)" do
      host.record_audit_trail!(action: "probe", organization_id: nil, auditable: nil)

      expect(AuditLogWorker.jobs.last["args"].first["user_id"]).to eq(oracle.id)
    end

    it "records the auditable entity when given" do
      org = create(:organization)

      host.record_audit_trail!(action: "probe", organization_id: org.id, auditable: org)

      attrs = AuditLogWorker.jobs.last["args"].first
      expect(attrs["auditable_type"]).to eq("Organization")
      expect(attrs["auditable_id"]).to eq(org.id)
    end

    it "skips with a WARN when no actor is resolvable (chain requires a user)" do
      oracle.sessions.destroy_all
      oracle.destroy!
      allow(Rails.logger).to receive(:warn)

      expect { host.record_audit_trail!(action: "probe", organization_id: nil, auditable: nil) }
        .not_to change { AuditLogWorker.jobs.size }

      expect(Rails.logger).to have_received(:warn).with(/AuditLog skip probe/)
    end
  end
end
