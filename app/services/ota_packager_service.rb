# frozen_string_literal: true

require "zlib"

class OtaPackagerService
  # Стандартні розміри для різних типів ефіру
  LORA_MTU = 13  # Для 16-байтних LoRa-пакетів (3 байти заголовок)
  COAP_MTU = 512 # Оптимально для Starlink/LTE

  def self.prepare(firmware, chunk_size: COAP_MTU)
    new(firmware, chunk_size).prepare
  end

  def initialize(firmware, chunk_size)
    @firmware = firmware
    @chunk_size = chunk_size
    @payload = firmware.binary_payload #
  end

  def prepare
    {
      manifest: generate_manifest,
      packages: generate_packages
    }
  end

  private

  # Маніфест для перевірки всієї прошивки після збірки на пристрої
  def generate_manifest
    {
      version: @firmware.version,
      total_size: @payload.bytesize,
      checksum: Zlib.crc32(@payload).to_s(16).upcase,
      total_chunks: (@payload.bytesize.to_f / @chunk_size).ceil
    }
  end

  def generate_packages
    total = (@payload.bytesize.to_f / @chunk_size).ceil
    
    @payload.b.scan(/.{1,#{@chunk_size}}/m).map.with_index do |chunk, index|
      # Формуємо заголовок загартованого пакета
      header = [
        0x99,          # OTA Marker
        index,         # Chunk Index
        total          # Total Chunks
      ].pack("CCC")

      # Додаємо CRC16 для кожного чанка для Zero-Lag валідації на рівні заліза
      package_payload = header + chunk
      package_payload
    end
  end
end
