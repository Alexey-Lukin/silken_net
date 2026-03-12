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
# - Формат вихідних даних: [IV:16 байт][Шифротекст:N*16 байт]
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

  # Шифрує payload для передачі через CoAP на STM32 пристрій.
  # Використовує AES-256-CBC з випадковим IV та нульовим padding.
  #
  # @param payload [String] сирі дані для шифрування
  # @param binary_key [String] 32-байтовий AES-256 ключ у бінарному форматі
  # @return [String] зашифрований пакет: [IV:16][Ciphertext:N*16]
  def coap_encrypt(payload, binary_key)
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = binary_key
    iv = cipher.random_iv
    cipher.padding = 0

    padding_length = (AES_BLOCK_SIZE - (payload.bytesize % AES_BLOCK_SIZE)) % AES_BLOCK_SIZE
    padded_payload = payload + ("\x00" * padding_length)

    iv + cipher.update(padded_payload) + cipher.final
  end
end
