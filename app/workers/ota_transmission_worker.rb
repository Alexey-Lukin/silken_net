# frozen_string_literal: true

require "openssl"
require "timeout"

class OtaTransmissionWorker
  include Sidekiq::Job
  sidekiq_options queue: "downlink", retry: 3

  # Розмір чанка. 512 байт - ідеально для CoAP та кратно 16 (вимога AES блоку)
  CHUNK_SIZE = 512

  def perform(queen_uid, firmware_type, record_id)
    gateway = Gateway.find_by!(uid: queen_uid)

    # 1. Збираємо бінарний payload (TinyML або mruby)
    payload = case firmware_type
              when "mruby"
                BioContractFirmware.find(record_id).binary_payload
              when "tinyml"
                TinyMlModel.find(record_id).binary_weights_payload
              else
                raise ArgumentError, "Невідомий тип прошивки: #{firmware_type}"
              end

    # 2. БІНАРНА БЕЗПЕКА (Кенозис Даних)
    # Використовуємо .b для жорсткого переведення в ASCII-8BIT (сирі байти).
    # scan розрізає бінарник на шматки без спроб декодування символів.
    chunks = payload.b.scan(/.{1,#{CHUNK_SIZE}}/m)
    total_chunks = chunks.size

    chunks.each_with_index do |chunk, index|
      # 3. ШИФРУВАННЯ КОЖНОГО ЧАНКА (Zero-Trust)
      encrypted_chunk = encrypt_payload(chunk)

      begin
        # 4. Тайм-аут мережі
        Timeout.timeout(10) do
          # Передаємо index та total, щоб C-код Королеви знав, коли збирати прошивку докупи
          url = "coap://#{gateway.ip_address}/ota/#{firmware_type}?chunk=#{index}&total=#{total_chunks}"
          CoapClient.put(url, encrypted_chunk)
        end

        # 5. Фізичний пейсинг (Pacing)
        # Даємо STM32 час записати ці 512 байт у Flash-пам'ять (MRUBY_CONTRACT_FLASH_ADDR)
        # та звільнити UART буфер модему SIM7070G.
        sleep 0.5 

      rescue Timeout::Error, StandardError => e
        Rails.logger.error "🛑 [OTA Error] Збій передачі чанка #{index}/#{total_chunks} на Королеву #{queen_uid}: #{e.message}"
        raise e # Прокидаємо помилку, щоб Sidekiq зробив retry всього процесу
      end
    end

    Rails.logger.info "📡 [OTA] Прошивку #{firmware_type} (#{total_chunks} чанків) успішно відправлено на Шлюз #{queen_uid}"
  end

  private

  # Метод симетричного шифрування, ідентичний до ActuatorCommandWorker
  def encrypt_payload(payload)
    cipher = OpenSSL::Cipher.new("aes-256-ecb")
    cipher.encrypt
    cipher.key = TelemetryUnpackerService::RAW_AES_KEY
    cipher.padding = 0

    # Доповнюємо нулями до кратності 16 байт
    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)

    cipher.update(padded_payload) + cipher.final
  end
end
