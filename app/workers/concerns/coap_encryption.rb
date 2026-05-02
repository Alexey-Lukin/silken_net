# frozen_string_literal: true

require "openssl"

# = ===================================================================
# 🔐 COAP ENCRYPTION (Shared AES-256-CBC for IoT Downlink Workers)
# = ===================================================================
# Централізована логіка шифрування для всіх воркерів, що передають
# дані через CoAP на Queen-шлюзи та Soldier-пристрої STM32.
#
# Забезпечує:
# - AES-256-CBC шифрування з випадковим IV (семантична безпека)
# - Нульове доповнення (padding) до 16-байтових блоків (сумісне з firmware)
# - [FW.20] 5-байтний CMD_TIME_SYNC envelope ([0x9C][ts_be:4]) перед payload —
#   крок до ARCH.26 TDMA. Queen скидає RTC за timestamp і потім обробляє inner payload.
# - Формат вихідних даних: [IV:16][AES-CBC ciphertext_of([0x9C][ts:4][payload]):N*16]
#
# Використання:
#   class MyWorker
#     include Sidekiq::Job
#     include CoapEncryption
#
#     def perform(...)
#       encrypted = coap_encrypt(raw_payload, binary_key)
#       CoapClient.put(url, encrypted)
#     end
#   end
module CoapEncryption
  extend ActiveSupport::Concern

  AES_BLOCK_SIZE = 16

  # [FW.20] CMD_TIME_SYNC marker (per docs/05_02 §4а.1).
  # Inserted at the start of every downlink plaintext so Queen can synchronise
  # RTC from server-authoritative UTC before routing the inner payload.
  CMD_TIME_SYNC = 0x9C
  TIME_SYNC_HEADER_SIZE = 5 # [marker:1][unix_seconds_be:4]

  # Шифрує payload для передачі через CoAP на STM32 пристрій.
  # Використовує AES-256-CBC з випадковим IV та нульовим padding.
  #
  # [FW.20]: Перед payload додаємо CMD_TIME_SYNC envelope (5 байт):
  #   - byte 0:    0x9C marker (відрізняє від CMD_OTA_BYTECODE=0x99 та "CMD:" prefix)
  #   - bytes 1-4: server UTC Unix timestamp у seconds, big-endian uint32
  # Queen firmware (FW.20 imple) перевіряє marker, оновлює RTC, потім обробляє
  # bytes 5..end як inner payload (наприклад, "CMD:..." або 0x99 OTA chunk).
  #
  # @param payload [String] сирі дані для шифрування (без timestamp envelope)
  # @param binary_key [String] 32-байтовий AES-256 ключ у бінарному форматі
  # @param timestamp [Integer, nil] явний UTC unix-час (для тестів). Default: Time.now.utc.to_i
  # @return [String] зашифрований пакет: [IV:16][Ciphertext:N*16]
  def coap_encrypt(payload, binary_key, timestamp: nil)
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = binary_key
    iv = cipher.random_iv
    cipher.padding = 0

    wrapped_payload = wrap_with_time_sync(payload, timestamp)

    padding_length = (AES_BLOCK_SIZE - (wrapped_payload.bytesize % AES_BLOCK_SIZE)) % AES_BLOCK_SIZE
    padded_payload = wrapped_payload + ("\x00" * padding_length)

    iv + cipher.update(padded_payload) + cipher.final
  end

  private

  # [FW.20] Build CMD_TIME_SYNC envelope: [0x9C][ts_be_u32][payload].
  # Uses Time.now.utc unless an explicit timestamp is provided (test injection).
  # Clamps timestamp to uint32 range; the year-2106 rollover is acceptable for
  # MCU firmware that uses uint32 RTC seconds.
  def wrap_with_time_sync(payload, timestamp)
    ts = (timestamp || Time.now.utc.to_i).to_i & 0xFFFFFFFF
    [ CMD_TIME_SYNC, ts ].pack("CN") + payload.b
  end
end
