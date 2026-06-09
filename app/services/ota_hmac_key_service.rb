# frozen_string_literal: true

require "openssl"

# [FW.23] OTA HMAC-SHA256 key service.
#
# Per-cluster K_ota deriviation для аутентифікації OTA bytecode перед запуском
# на Soldier (dual-gate: magic 0x45544952 "RITE" + HMAC-SHA256 verify).
# Backend і Soldier (pure-C silken_sha256.h) обоє деривують один
# і той самий K_ota з PROVISIONING_MASTER_KEY через HKDF-SHA256.
#
# Формула:
#   K_ota = HKDF-SHA256(
#     ikm:  PROVISIONING_MASTER_KEY,
#     salt: "cluster:#{cluster_id}",
#     info: "silken-ota-hmac-v1",
#     length: 32 bytes
#   )
#
# Domain separation від HardwareKeyService AES device-keys — після ARCH.42
# (2026-05-23) їх два, з різними info-strings:
#   • "silken-aes-128-lora-key"   — Tree LoRa AES-128 (16 bytes)
#   • "silken-aes-256-device-key" — Gateway CoAP AES-256 (32 bytes)
# Це гарантує, що навіть при компрометації одного К-вектора, інші ключі
# (включно з цим OTA HMAC) залишаються непохитними.
#
# Шифрові виклики (HKDF) тут слідують тому самому патерну, що й
# HardwareKeyService: `SecurityError` без master key (SEC.11 hard cutover,
# no SecureRandom fallback in production).
#
# Див. docs/03_05 §3.4б для повного протоколу.
class OtaHmacKeyService
  KEY_SIZE_BYTES = 32
  HKDF_INFO      = "silken-ota-hmac-v1"

  # Повертає K_ota як 64-символьний HEX-рядок (32 байти, верхній регістр).
  def self.fetch_for(cluster_id)
    raise ArgumentError, "cluster_id is required" if cluster_id.blank?

    master_key = ENV["PROVISIONING_MASTER_KEY"]

    if master_key.blank?
      raise SecurityError,
            "PROVISIONING_MASTER_KEY ENV is required. Backend cannot derive " \
            "OTA HMAC key without it (would silently diverge from firmware " \
            "K_ota deriviation). See SEC.11 in docs/00_07_Action_Plan_Tracker.md."
    end

    derived = OpenSSL::KDF.hkdf(
      master_key,
      salt: "cluster:#{cluster_id}",
      info: HKDF_INFO,
      length: KEY_SIZE_BYTES,
      hash: "SHA256"
    )

    derived.unpack1("H*").upcase
  end

  # Той самий ключ, але як binary-string (32 байти) — для прямого використання
  # у `OpenSSL::HMAC.digest("SHA256", binary_key, message)`.
  def self.fetch_binary_for(cluster_id)
    [ fetch_for(cluster_id) ].pack("H*")
  end
end
