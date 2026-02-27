# frozen_string_literal: true

class HardwareKey < ApplicationRecord
  # device_uid: HEX-рядок (напр. "8F2A91C3" для Солдата або UID Королеви)
  # aes_key_hex: 64-символьний рядок (256-бітний ключ у HEX форматі)

  validates :device_uid, presence: true, uniqueness: true
  validates :aes_key_hex, presence: true, length: { is: 64 } # Строго 32 байти (64 HEX символи)

  # Метод для перетворення HEX-рядка з бази на бінарний ключ для OpenSSL
  def binary_key
    [ aes_key_hex ].pack("H*")
  end

  # [НОВЕ]: Метод для генерації нового ключа прямо в Rails
  def self.generate_for(device_uid)
    create!(
      device_uid: device_uid.to_s.upcase,
      aes_key_hex: SecureRandom.hex(32).upcase
    )
  end
end
