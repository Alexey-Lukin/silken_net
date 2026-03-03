# frozen_string_literal: true

require "openssl"
require "timeout"

class OtaTransmissionWorker
  include Sidekiq::Job
  # Використовуємо окрему чергу для низхідного зв'язку, щоб не блокувати телеметрію
  sidekiq_options queue: "downlink", retry: false

  CHUNK_SIZE = 512
  MAX_CHUNK_RETRIES = 5

  def perform(queen_uid, firmware_type, record_id, chunk_index = 0, retry_count = 0)
    gateway = Gateway.find_by!(uid: queen_uid)
    key_record = HardwareKey.find_by!(device_uid: queen_uid)

    # 1. ОТРИМАННЯ ОБ'ЄКТА ПРОШИВКИ
    firmware_obj = fetch_firmware_record(firmware_type, record_id)

    # 2. ПАКУВАННЯ (Hardware-Aligned Packaging)
    # Отримуємо нарізані пакети з заголовками [0x99][Index][Total]
    ota_data = OtaPackagerService.prepare(firmware_obj, chunk_size: CHUNK_SIZE)
    packages = ota_data[:packages]
    total_chunks = ota_data[:manifest][:total_chunks]

    # Переводимо Королеву в режим оновлення тільки при першому чанку
    gateway.update!(state: :updating) if chunk_index.zero?

    # ⚡ [СИНХРОНІЗАЦІЯ]: Звітуємо Архітектору через Turbo Stream
    broadcast_progress(queen_uid, chunk_index, total_chunks)

    # 🔐 КРИПТОГРАФІЧНИЙ ЗАХИСТ (AES-256-CBC з випадковим IV)
    encrypted_package = encrypt_payload(packages[chunk_index], key_record.binary_key)

    begin
      # Збільшений таймаут для супутникових стрибків Starlink
      Timeout.timeout(25) do
        # Формуємо шлях CoAP з метаданими для Queen-реле
        url = "coap://#{gateway.ip_address}/ota/#{firmware_type}?ch=#{chunk_index}&ttl=#{total_chunks}"

        response = CoapClient.put(url, encrypted_package)

        raise "NACK: Шлюз відхилив чанк #{chunk_index} [Code: #{response&.code}]" unless response&.success?
      end
    rescue Timeout::Error, StandardError => e
      handle_chunk_failure(queen_uid, firmware_type, record_id, chunk_index, retry_count, e.message)
      return
    end

    next_index = chunk_index + 1

    if next_index < total_chunks
      # Pacing: звільняємо потік Sidekiq між чанками замість блокуючого sleep.
      # HAL_FLASH_Program на STM32 потребує ~400 мс на запис у Flash.
      self.class.perform_in(0.4.seconds, queen_uid, firmware_type, record_id, next_index, 0)
    else
      # 4. ЗАВЕРШЕННЯ ЕВОЛЮЦІЇ
      gateway.update!(state: :idle, firmware_version: firmware_obj.version)
      broadcast_progress(queen_uid, total_chunks, total_chunks, status: "COMPLETE")

      Rails.logger.info "✅ [OTA] Еволюція завершена для #{queen_uid}. Версія: #{firmware_obj.version}"
    end
  end

  private

  # Вибір правильної моделі на основі типу OTA
  def fetch_firmware_record(type, id)
    case type.to_s
    when "mruby", "firmware" then BioContractFirmware.find(id)
    when "tinyml", "weights" then TinyMlModel.find(id)
    else raise ArgumentError, "🚨 Невідомий тип прошивки: #{type}"
    end
  end

  def broadcast_progress(uid, current, total, status: "TRANSMITTING")
    percent = ((current.to_f / total) * 100).to_i

    # Трансляція в персональний канал пристрою
    Turbo::StreamsChannel.broadcast_replace_to(
      "ota_channel_#{uid}",
      target: "ota_progress_#{uid}",
      html: Views::Components::Firmwares::OtaProgressBar.new(
        uid: uid,
        percent: percent,
        current: current,
        total: total,
        status: status
      ).call
    )
  end

  def encrypt_payload(payload, key)
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = key
    iv = cipher.random_iv  # Унікальний IV для кожного пакета; CBC потребує непередбачуваного IV для семантичної безпеки

    # Ручне доповнення (Padding) до блоку 16 байт
    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)

    # Передаємо IV разом із шифротекстом: перші 16 байт — IV, решта — дані
    iv + cipher.update(padded_payload) + cipher.final
  end

  def handle_chunk_failure(uid, type, record_id, index, retry_count, error)
    Rails.logger.error "⚠️ [OTA Failure] #{uid} чанк #{index}: #{error}"

    if retry_count < MAX_CHUNK_RETRIES
      # Експоненціальна затримка перед повтором
      wait_time = (retry_count + 1) * 15
      self.class.perform_in(wait_time.seconds, uid, type, record_id, index, retry_count + 1)
      broadcast_progress(uid, index, 100, status: "RETRYING_IN_#{wait_time}S")
    else
      Gateway.find_by(uid: uid)&.update!(state: :faulty)
      broadcast_progress(uid, index, 100, status: "FAILED")
      # Тут можна ініціювати Emergency Alert
    end
  end
end
