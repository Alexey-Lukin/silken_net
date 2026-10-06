# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.3 + SEC.6] Factory Flashing — Гілка B Secure Element provisioning skeleton.
#
# ⚠️ SE = NXP SE050 (2026-06-07, true-DePIN — docs/03_05 §3.7 SEC.6; supersedes
# ATECC608B). This class is the LEGACY ATECC `atcab_*` / 16-slot skeleton, kept as
# the audit provisioning-sequence placeholder. Class-rename (ATECC→SE05x) + DB column
# se_serial_hex ✅ done (SE050-MIGRATION A). The real-I²C rewrite — object-model
# instead of slots, on-chip Ed25519 keygen for the tree-voice, `atcab_*`→`Se05x`/`sss`
# emit — is bundled with the eval-kit work (00_07 SE050-MIGRATION B).
#
# Гілка B = Гілка A + identity-chip (SEC.14 provisioning-only): every runtime key
# (KEYL · LSED · KEYB · KPUB) goes to STM32 Protected Flash through the SAME SWD
# writes as Гілка A (CommandBuilder), because each has an MCU consumer — this class
# adds only the identity objects. Slot map (canonical SSOT — docs/03_05 §3.7):
#
#   Slot 0 → reserved (urban per-packet variant) — ⛔ NOT written: the LoRa session
#            key is KEYL in Protected Flash (⚖️ delegated 2026-09-27, 00_07
#            SE050-MIGRATION); this was the only emitted row with no SE05x
#            counterpart — it disappears, it does not migrate
#   Slot 1 → Ed25519 private key        (32B, tree-voice L2 + peaq/Solana; SE05x on-chip keygen)
#   Slot 2 → X.509 device certificate   (≤64B, DER)
#   Slot 3 → OTA seal public key       (32B, Ed25519 — FW.23; a copy, the MCU verifies with KPUB)
#
# Emit-only (textual `atcab_*` — LEGACY ATECC API). Real cryptoauthlib/SE05x I²C
# transport intentionally **not** implemented — firmware does the actual writes at
# factory power-up self-test (docs/03_06 §1 Гілка B). Emitted strings → AuditLog
# transcript for verbatim audit reproduction. Post-TRL 7: swap emit-only → real
# SE05x I²C (public API unchanged).
module FactoryFlashing
  class SecureElementProvisioner
    Result = Struct.new(:statements, :se_serial_hex, keyword_init: true)

    # Raised when callers feed Гілка B inputs that violate the slot map.
    class InputError < StandardError; end

    # @param session   [ProvisioningSession] must have gilka == "B"
    # @param ota_seal_pub_hex [String] 64 hex (32B for Slot 3, the cluster OTA seal
    #   public key — a copy for the open post-TRL-7 migration; the MCU verifies OTA with
    #   its Protected-Flash KPUB copy)
    # @param ecc_priv_hex    [String, nil] 64 hex (32B for Slot 1) — optional in MVP
    # @param cert_der_hex    [String, nil] ≤128 hex (≤64B for Slot 2) — optional in MVP
    def initialize(session:, ota_seal_pub_hex:, ecc_priv_hex: nil, cert_der_hex: nil)
      raise InputError, "SecureElementProvisioner is Гілка B only (got #{session.gilka.inspect})" unless session.gilka == "B"

      @session       = session
      @ota_seal_pub_hex = ota_seal_pub_hex.to_s.upcase
      @ecc_priv_hex  = ecc_priv_hex&.upcase
      @cert_der_hex  = cert_der_hex&.upcase
      validate_lengths!
    end

    # Returns Result with statements + (mocked) se_serial_hex. Real provisioner
    # would call atcab_read_serial_number() here.
    def provision
      Result.new(
        statements: emit_statements,
        se_serial_hex: @session.se_serial_hex
      )
    end

    private

    def validate_lengths!
      raise InputError, "Slot 3 OTA seal pubkey must be 64 hex (32 bytes), got #{@ota_seal_pub_hex.length}" if @ota_seal_pub_hex.length != 64
      raise InputError, "Slot 1 ECC priv must be 64 hex (32 bytes)" if @ecc_priv_hex && @ecc_priv_hex.length != 64
      raise InputError, "Slot 2 cert DER must be ≤128 hex (64 bytes)" if @cert_der_hex && @cert_der_hex.length > 128
      raise InputError, "OTA seal pubkey must be hexadecimal" unless @ota_seal_pub_hex.match?(/\A[0-9A-F]+\z/)
    end

    def emit_statements
      out = []
      out << "atcab_init(&cfg_ateccx08a_i2c)"
      out << "atcab_read_serial_number(&serial[0])  # expect == #{@session.se_serial_hex}"
      out << "# Slot 0 — reserved (urban per-packet variant); the LoRa session key is KEYL in Protected Flash"

      if @ecc_priv_hex
        out << "atcab_write_zone(ATCA_ZONE_DATA, 1, 0, 0, #{wrap(@ecc_priv_hex)}, 32) # Slot 1 Ed25519 priv (LEGACY write; SE050 → on-chip keygen)"
      else
        out << "# Slot 1 Ed25519 priv — TODO SE050 on-chip keygen (tree-voice L2 + peaq/Solana; key never exported)"
      end

      if @cert_der_hex
        out << "atcab_write_zone(ATCA_ZONE_DATA, 2, 0, 0, #{wrap(@cert_der_hex)}, #{@cert_der_hex.length / 2}) # Slot 2 X.509 cert DER"
      else
        out << "# Slot 2 cert — TODO populate before mTLS field rollout"
      end

      out << "atcab_write_zone(ATCA_ZONE_DATA, 3, 0, 0, #{wrap(@ota_seal_pub_hex)}, 32) # Slot 3 OTA seal pubkey (FW.23)"
      out << "atcab_lock_config_zone()  # irreversible: slot policies frozen"
      out << "atcab_lock_data_zone()    # irreversible: all slot writes forbidden forever"
      out
    end

    def wrap(hex)
      "/* #{hex.length / 2}B hex elided from log */"
    end
  end
end
