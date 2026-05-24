# frozen_string_literal: true

require "rails_helper"

RSpec.describe FactoryFlashing::AuditTrail do
  subject(:trail) do
    described_class.new(session: session, device: tree, hardware_key: hw_key, transcript: transcript)
  end

  let(:operator)   { create(:user, :super_admin) }
  let(:supervisor) { create(:user, :admin, organization: operator.organization) }
  let(:tree)       { create(:tree) }
  let(:hw_key)     { create(:hardware_key, :for_tree, device_uid: tree.did) }
  let(:session) do
    create(:provisioning_session,
           operator: operator, supervisor: supervisor,
           device_uid: tree.did, gilka: "A", rdp_level: 1,
           firmware_version: "fw-1.2.3", batch_id: "BATCH-001")
  end
  let(:transcript) do
    [
      FactoryFlashing::Executor::Result.new(command: "cmd1", stdout: "", stderr: "", status: nil),
      FactoryFlashing::Executor::Result.new(command: "cmd2", stdout: "", stderr: "", status: nil)
    ]
  end

  describe "#record!" do
    it "creates an AuditLog with factory_flash action and chain_hash populated" do
      result = trail.record!
      expect(result.audit_log).to be_persisted
      expect(result.audit_log.action).to eq("factory_flash")
      expect(result.audit_log.auditable).to eq(hw_key)
      expect(result.audit_log.chain_hash).to be_present
    end

    it "populates audit metadata without leaking key bytes" do
      meta = trail.record!.audit_log.metadata
      expect(meta).to include(
        "session_id"        => session.id,
        "device_uid"        => tree.did,
        "device_type"       => "Tree",
        "gilka"             => "A",
        "operator_id"       => operator.id,
        "supervisor_id"     => supervisor.id,
        "batch_id"          => "BATCH-001",
        "flash_addr"        => "0x0803E000",
        "rdp_level"         => 1,
        "firmware_version"  => "fw-1.2.3",
        "command_count"     => 2,
        "dry_run"           => true
      )
      expect(meta.to_s).not_to include(hw_key.aes_key_hex)
    end

    it "creates a MaintenanceRecord(installation) tied to the device" do
      result = trail.record!
      expect(result.maintenance_record).to be_persisted
      expect(result.maintenance_record).to be_action_type_installation
      expect(result.maintenance_record.maintainable).to eq(tree)
      expect(result.maintenance_record.user).to eq(operator)
      expect(result.maintenance_record.notes).to include("Factory Flash session ##{session.id}")
      expect(result.maintenance_record.notes).to include("Batch: BATCH-001")
      expect(result.maintenance_record.notes).to include("Gilka: A")
    end

    it "skips photo validation (factory bench has no camera)" do
      result = trail.record!
      expect(result.maintenance_record).to be_valid
      expect(result.maintenance_record.photos).to be_empty
    end

    it "marks dry_run: false when transcript carries exit statuses" do
      live_transcript = [
        FactoryFlashing::Executor::Result.new(command: "cmd1", stdout: "OK", stderr: "", status: 0)
      ]
      trail = described_class.new(session: session, device: tree, hardware_key: hw_key, transcript: live_transcript)
      expect(trail.record!.audit_log.metadata["dry_run"]).to be false
    end
  end

  describe "Гілка B metadata" do
    let(:session) do
      create(:provisioning_session, :gilka_b,
             operator: operator, supervisor: supervisor,
             device_uid: tree.did, atecc_serial_hex: "0123456789ABCDEF01",
             firmware_version: "fw-1.2.3")
    end

    it "records atecc_serial_hex in audit metadata and notes" do
      result = trail.record!
      expect(result.audit_log.metadata["gilka"]).to eq("B")
      expect(result.audit_log.metadata["atecc_serial_hex"]).to eq("0123456789ABCDEF01")
      expect(result.maintenance_record.notes).to include("ATECC serial: 0123456789ABCDEF01")
    end
  end
end
