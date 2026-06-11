# frozen_string_literal: true

# [FW.17] Hash-Ratchet версія LoRa-ключа Tree-пристрою. 0 = заводський K0
# (Factory Flashing, FW.1); кожна ратчет-ротація інкрементує — firmware
# дзеркало живе у Flash-KV 0x13 і доганяє K_current = ratchet^v(K0).
# Gateway-ключі (CoAP AES-256) ротуються випадково й version не використовують.
class AddKeyVersionToHardwareKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :hardware_keys, :key_version, :integer, default: 0, null: false
  end
end
