# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.3] Factory Flashing — append-only audit trail writer.
#
# Closes the "physically flashed ↔ DB-registered" loop required by
# docs/03_06 §5 C. Each successful (or failed) provisioning session
# materializes:
#
#   1. AuditLog(action: "factory_flash", auditable: hardware_key, ...)
#      — chain-hashed by AuditLog before_create callback. Metadata carries
#        operator_id, supervisor_id, batch_id, flash_addr, rdp_level,
#        atecc_serial (Гілка B), firmware_version, command transcript count.
#        Raw key bytes are NEVER persisted.
#   2. MaintenanceRecord(action_type: :installation, maintainable: device, ...)
#      — keeps the device-history view consistent with the new monitor;
#        system_generated: true because the bench has no camera.
#
# Both writes occur inside the surrounding ActiveRecord::Base.transaction
# opened by Session, so a HardwareKey row that fails to materialize also
# rolls back the audit entries. AuditLog#chain_hash is computed on
# before_create; the chain stays intact because rolled-back rows never
# reach the chain.
module FactoryFlashing
  class AuditTrail
    Result = Struct.new(:audit_log, :maintenance_record, keyword_init: true)

    # @param session       [ProvisioningSession]
    # @param device        [Tree|Gateway]
    # @param hardware_key  [HardwareKey]
    # @param transcript    [Array<FactoryFlashing::Executor::Result>]
    def initialize(session:, device:, hardware_key:, transcript:)
      @session = session
      @device = device
      @hardware_key = hardware_key
      @transcript = transcript
    end

    def record!
      Result.new(
        audit_log:          create_audit_log,
        maintenance_record: create_maintenance_record
      )
    end

    private

    def create_audit_log
      AuditLog.create!(
        user:           @session.operator,
        organization:   @session.operator.organization,
        action:         "factory_flash",
        auditable:      @hardware_key,
        metadata:       audit_metadata
      )
    end

    def audit_metadata
      {
        session_id:        @session.id,
        device_uid:        @session.device_uid,
        device_type:       @device.class.name,
        silicon_uid_hex:   (@device.silicon_uid_hex if @device.is_a?(Tree)),
        gilka:             @session.gilka,
        operator_id:       @session.operator_id,
        supervisor_id:     @session.supervisor_id,
        batch_id:          @session.batch_id,
        flash_addr:        @session.flash_addr,
        rdp_level:         @session.rdp_level,
        se_serial_hex:  @session.se_serial_hex,
        firmware_version:  @session.firmware_version,
        command_count:     @transcript.size,
        dry_run:           @transcript.all? { |r| r.status.nil? }
      }.compact
    end

    def create_maintenance_record
      MaintenanceRecord.create!(
        maintainable: @device,
        user:         @session.operator,
        action_type:  :installation,
        performed_at: Time.current,
        notes:        notes_text,
        system_generated: true,
        hardware_verified: true
      )
    end

    def notes_text
      lines = [
        "Factory Flash session ##{@session.id}",
        "Batch: #{@session.batch_id}",
        "Gilka: #{@session.gilka}",
        "RDP Level: #{@session.rdp_level}",
        "Firmware: #{@session.firmware_version}"
      ]
      lines << "ATECC serial: #{@session.se_serial_hex}" if @session.se_serial_hex.present?
      lines.join(" | ")
    end
  end
end
