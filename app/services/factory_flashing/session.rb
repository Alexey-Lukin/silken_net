# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.3] Factory Flashing — orchestrator wiring all sub-services.
#
# Public entry-point invoked by Rake tasks (lib/tasks/factory.rake) once a
# `ProvisioningSession` has been pre-created and approved by a supervisor.
# Responsibilities (in execution order):
#
#   1. Fetch master key (MasterKeySource) and refuse to proceed if the
#      WeakKeyDetector flags it; the fetched key is then threaded into
#      every HKDF derivation below (SEC.3 DI — so a non-ENV adapter is
#      honoured, not bypassed).
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
      :session, :device, :hardware_key, :transcript, :se_transcript, :audit_log,
      keyword_init: true
    )

    # Raised when the prerequisites (session state, device, master key) are not met.
    class PreflightError < StandardError; end

    # [FW.54] Live wrong-board guard: кремнієвий паспорт плати на джизі
    # не збігається з деревом сесії — жоден -w32 не виконується.
    class WrongBoardError < StandardError; end

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
        # [FW.54] Wrong-board guard ПЕРЕД будь-якою деривацією/записом:
        # connect + SWD-read UID → live-звірка паспорта плати (dry-run: skip).
        # Чужа плата → навіть HardwareKey-рядок не матеріалізується.
        @executor.run(CommandBuilder.preflight_commands)
        verify_silicon_uid!
        hw_key = ensure_hardware_key
        se_transcript = run_secure_element_if_needed(hw_key)
        @executor.run(build_commands(hw_key))
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
          se_transcript: se_transcript,
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
      # the transaction with a missing or rejected master key. The result is
      # retained and threaded into every derivation below — the point of the
      # adapter (SEC.3 DI): vault-sourced keys must actually feed HKDF.
      @master_key = @master_key_source.fetch_master_key
    end

    def locate_device!
      Tree.find_by(did: @session.device_uid) || Gateway.find_by(uid: @session.device_uid)
    end

    def ensure_hardware_key
      # HardwareKeyService.provision raises if the master key is blank
      # (тут @master_key — уже провалідований адаптером; SEC.11 hard
      # cutover). Re-fetching the row is safe because provision creates
      # a new HardwareKey atomically.
      HardwareKey.find_by(device_uid: @session.device_uid) || begin
        HardwareKeyService.provision(@device, master_key: @master_key)
        HardwareKey.find_by!(device_uid: @session.device_uid)
      end
    end

    def build_commands(hw_key)
      CommandBuilder.new(
        session:          @session,
        device:           @device,
        aes_key_hex:      hw_key.aes_key_hex,
        lorenz_seed_hex:  hw_key.lorenz_seed_hex,
        ota_hmac_hex:     tree_ota_hmac,
        ed25519_seed_hex: gateway_voice_seed(hw_key),
        bcast_key_hex:    cluster_broadcast_key
      ).flash_commands
    end

    # [FW.54] Live wrong-board guard. Порівнюємо сирі UID (не деривовані
    # DID) — ловить навіть теоретичну DID-колізію двох чипів. Skip: dry-run
    # (заліза нема) та пристрої без паспорта (Gateway, legacy-Tree — нові
    # Tree-потоки rake вже не пускає без UID). Парс-відмова = теж відмова
    # записом: якщо мали що звіряти і не змогли — не пишемо наосліп.
    def verify_silicon_uid!
      return if @executor.dry_run?
      return unless @device.is_a?(Tree) && @device.silicon_uid_hex.present?

      stdout = @executor.results.last&.stdout
      words  = UidReadout.words(stdout)
      if words.nil?
        raise WrongBoardError,
              "UID-read не розпарсився — запис заборонено (bench: звір формат " \
              "`-r32`-виводу, RUNBOOK 1.3): #{stdout.to_s.strip.truncate(120)}"
      end

      board_uid = UidReadout.uid_hex(words)
      return if board_uid == @device.silicon_uid_hex

      raise WrongBoardError,
            "На джизі чип #{board_uid} (DID #{SilkenNet::DidDerivation.wire_did(*words)}), " \
            "сесія для #{@session.device_uid} (#{@device.silicon_uid_hex}) — " \
            "чужа плата, жоден -w32 не виконано"
    end

    # [FW.23] Per-cluster K_ota для OTA dual-gate — Гілка A пише його у
    # Protected Flash 0x0803E800 (до 2026-06-11 емітувала лише superseded
    # ATECC-гілка B → реальні дерева лишались із вічно fail-closed OTA).
    def tree_ota_hmac
      return nil unless @device.is_a?(Tree)
      OtaHmacKeyService.fetch_for(@device.cluster_id, master_key: @master_key)
    end

    # [FW.2 гейт (в)] Cluster control-plane ключ (KEYB) — ОБИДВА типи:
    # Tree отримує його в KEYB-слот, Gateway — у свій KEYL (Королева живе
    # ним як єдиним LoRa-ключем). Той самий salt-домен, що K_ota.
    def cluster_broadcast_key
      HardwareKeyService.derive_broadcast_key(@device.cluster_id, master_key: @master_key)
    end

    # [L1 QATT] Сім'я голосу Королеви (Gateway, Гілка A). КРИТИЧНО: НЕ
    # HKDF-від-master — інакше backend-compromise міг би вивести сім'ю і
    # підробити підпис, тобто L1 не захищав би від того, від чого заявлений
    # (канон: 05_02 ladder). Генерується тут (фабричний хост) на кожен flash;
    # у БД персиститься ЛИШЕ pubkey (AuditTrail сирих байтів не пише — 03_06 §5),
    # сама сім'я живе тільки у транскрипті процесу → Protected Flash.
    # Re-flash → нова сім'я → pubkey ротується разом із нею (коректно).
    # Гілка B (SE050) — on-chip keygen, інший механізм (SE050-MIGRATION).
    def gateway_voice_seed(hw_key)
      return nil unless @device.is_a?(Gateway)
      return nil unless @session.gilka == "A"

      seed_hex = SecureRandom.hex(32)
      hw_key.update!(ed25519_public_key_hex: Ed25519Crypto::SigningService.public_key_from_seed(seed_hex))
      seed_hex
    end

    def run_secure_element_if_needed(hw_key)
      return nil unless @session.gilka == "B"
      return nil unless @device.is_a?(Tree)

      ota_hmac_hex = OtaHmacKeyService.fetch_for(@device.cluster_id, master_key: @master_key)
      SecureElementProvisioner.new(
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
