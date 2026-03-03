# frozen_string_literal: true

require "zlib"

class OtaPackagerService
  # Стандартні розміри для різних типів ефіру
  LORA_MTU = 11  # Для 16-байтних LoRa-пакетів (5 байтів заголовок: 1 маркер + 2 index + 2 total)
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
    payload_bytes = @payload.b

    Enumerator.new do |yielder|
      payload_bytes.scan(/.{1,#{@chunk_size}}/m).each_with_index do |chunk, index|
        # Формуємо заголовок загартованого пакета (16-bit index/total для підтримки >255 чанків)
        header = [
          0x99,          # OTA Marker
          index,         # Chunk Index   (uint16 big-endian)
          total          # Total Chunks  (uint16 big-endian)
        ].pack("Cnn")

        # Додаємо CRC16 для кожного чанка для Zero-Lag валідації на рівні заліза
        package_payload = header + chunk
        crc = crc16_ccitt(package_payload)
        yielder.yield(package_payload + [crc].pack("n"))
      end
    end
  end

  def crc16_ccitt(data)
    crc = 0xFFFF
    data.each_byte do |byte|
      crc ^= byte << 8
      8.times do
        crc = (crc & 0x8000).nonzero? ? (crc << 1) ^ 0x1021 : crc << 1
        crc &= 0xFFFF
      end
    end
    crc
  end
end
