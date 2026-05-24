# frozen_string_literal: true

# [SEC.3] Factory Flashing — orchestrator wiring all sub-services.
#
# Public entry-point invoked by Rake tasks (lib/tasks/factory.rake) once a
# `ProvisioningSession` has been pre-created and approved by a supervisor.
# Responsibilities (in execution order):
#
#   1. Fetch master key (MasterKeySource) and refuse to proceed if the
#      WeakKeyDetector flags it.
#   2. Materialize the HardwareKey row through HardwareKeyService.provision
#      (single source of truth for HKDF — same derivation firmware will run).
#   3. Generate the STM32CubeProgrammer command sequence (CommandBuilder).
#   4. For Гілка B — also emit the ATCA write-zone transcript.
#   5. Execute (dry-run or live subprocess via Executor).
#   6. Persist AuditLog + MaintenanceRecord through AuditTrail.
#   7. Move the session AASM to :completed (or :failed on raise).
#
# Everything runs inside one ActiveRecord::Base.transaction so a downstream
# failure rolls back the HardwareKey + audit rows together. The chain-hashed
# AuditLog stays intact because rolled-back rows never enter the chain.
module FactoryFlashing
  class Session
    Outcome = Struct.new(
      :session, :device, :hardware_key, :transcript, :atecc_transcript, :audit_log,
      keyword_init: true
    )

    # Raised when the prerequisites (session state, device, master key) are not met.
    class PreflightError < StandardError; end

    def self.run(session:, device: nil, executor: nil, master_key_source: MasterKeySource.default)
      new(
        session: session,
        device: device,
        executor: executor || Executor.new,
        master_key_source: master_key_source
      ).run
    end

    def initialize(session:, device:, executor:, master_key_source:)
      @session = session
      @device = device || locate_device!
      @executor = executor
      @master_key_source = master_key_source
    end

    def run
      preflight!

      ActiveRecord::Base.transaction do
        @session.start!
        hw_key = ensure_hardware_key
        atecc_transcript = run_atecc_if_needed(hw_key)
        commands = build_commands(hw_key)
        @executor.run(commands)
        audit = AuditTrail.new(
          session:      @session,
          device:       @device,
          hardware_key: hw_key,
          transcript:   @executor.results
        ).record!
        @session.complete!

        Outcome.new(
          session:          @session,
          device:           @device,
          hardware_key:     hw_key,
          transcript:       @executor.results,
          atecc_transcript: atecc_transcript,
          audit_log:        audit.audit_log
        )
      end
    rescue StandardError => e
      capture_failure(e)
      raise
    end

    private

    def preflight!
      raise PreflightError, "session must be supervisor_approved (got #{@session.state})" unless @session.may_start?
      raise PreflightError, "device #{@session.device_uid} not found" if @device.nil?
      # Surface UnavailableError / NotImplementedError early so we never enter
      # the transaction with a missing or rejected master key.
      @master_key_source.fetch_master_key
    end

    def locate_device!
      Tree.find_by(did: @session.device_uid) || Gateway.find_by(uid: @session.device_uid)
    end

    def ensure_hardware_key
      # HardwareKeyService.provision raises if PROVISIONING_MASTER_KEY is
      # blank (SEC.11 hard cutover). Re-fetching the row is safe because
      # provision creates a new HardwareKey atomically.
      HardwareKey.find_by(device_uid: @session.device_uid) || begin
        HardwareKeyService.provision(@device)
        HardwareKey.find_by!(device_uid: @session.device_uid)
      end
    end

    def build_commands(hw_key)
      CommandBuilder.new(
        session:        @session,
        device:         @device,
        aes_key_hex:    hw_key.aes_key_hex,
        lorenz_seed_hex: hw_key.lorenz_seed_hex
      ).commands
    end

    def run_atecc_if_needed(hw_key)
      return nil unless @session.gilka == "B"
      return nil unless @device.is_a?(Tree)

      ota_hmac_hex = OtaHmacKeyService.fetch_for(@device.cluster_id)
      AteccProvisioner.new(
        session:      @session,
        aes_key_hex:  hw_key.aes_key_hex,
        ota_hmac_hex: ota_hmac_hex
      ).provision
    end

    def capture_failure(error)
      return if @session.failed?
      reason = "#{error.class}: #{error.message}".truncate(1000)
      @session.fail_with!(reason) if @session.may_fail_with?
    rescue StandardError => persist_error
      Rails.logger.error "🚨 [SEC.3] Could not record session failure: #{persist_error.message}"
    end
  end
end
