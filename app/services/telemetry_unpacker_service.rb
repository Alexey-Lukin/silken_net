# frozen_string_literal: true

require "openssl"

class TelemetryUnpackerService
  # Наш ключ з C-коду STM32: {0x2B7E1516, 0x28AED2A6, ...}
  # Перетворюємо масив 32-бітних чисел на суцільний 32-байтний рядок
  RAW_AES_KEY = [
    0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
    0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D
  ].pack("N8").freeze

  # Розмір одного логічного запису в батчі від Королеви: 
  # 4 (Queen UID) + 1 (RSSI) + 16 (Encrypted Payload) = 21 байт
  CHUNK_SIZE = 21

  def self.call(binary_batch)
    new(binary_batch).perform
  end

  def initialize(binary_batch)
    @binary_batch = binary_batch

    # Ініціалізуємо AES-256 у режимі ECB (як у апаратному модулі STM32)
    @cipher = OpenSSL::Cipher.new("aes-256-ecb")
    @cipher.decrypt
    @cipher.key = RAW_AES_KEY
    @cipher.padding = 0 
  end

  def perform
    # Розрізаємо масив на шматки рівно по 21 байту
    # Використовуємо .b (ASCII-8BIT), щоб уникнути проблем з кодуванням
    chunks = @binary_batch.b.scan(/.{1,#{CHUNK_SIZE}}/m)

    chunks.each do |chunk|
      next if chunk.bytesize < CHUNK_SIZE # Ігноруємо неповні пакети

      process_chunk(chunk)
    end
  end

  private

  def process_chunk(chunk)
    # 1. Читаємо метадані від Королеви
    queen_uid, inverted_rssi = chunk[0..4].unpack("NC")
    actual_rssi = -inverted_rssi

    # 2. Витягуємо зашифрований пакет (16 байтів)
    encrypted_payload = chunk[5..20]

    # 3. Розшифровуємо
    begin
      @cipher.reset 
      decrypted = @cipher.update(encrypted_payload) + @cipher.final
    rescue OpenSSL::Cipher::CipherError => e
      Rails.logger.error "🛑 [AES] Помилка розшифровки для Королеви #{queen_uid.to_s(16).upcase}: #{e.message}"
      return
    end

    # 4. Розбираємо 16 байтів згідно з C-структурою Солдата
    # N - DID, n - Vcap, c - Temp, C - Acoustic, n - Time, C - Bio, C - TTL, a4 - Pad
    parsed_data = decrypted.unpack("N n c C n C C a4")

    did            = parsed_data[0]
    vcap_voltage   = parsed_data[1]
    temp_celsius   = parsed_data[2]
    acoustic       = parsed_data[3]
    delta_t        = parsed_data[4]
    bio_contract   = parsed_data[5]
    ttl            = parsed_data[6]

    # 5. Хірургія Біо-Контракту
    status_code = bio_contract >> 6
    growth_points = bio_contract & 0x3F

    hex_did = did.to_s(16).upcase
    hex_queen_uid = queen_uid.to_s(16).upcase

    # Пошук дерева в БД (Якір системи)
    tree = Tree.find_by(did: hex_did)

    unless tree
      Rails.logger.warn("⚠️ [СИСТЕМНИЙ ШУМ] DID #{hex_did} не знайдено. Пакет відхилено.")
      return
    end

    # 6. ТРАНЗАКЦІЙНЕ ЗБЕРЕЖЕННЯ ТА НАСЛІДКИ
    ActiveRecord::Base.transaction do
      log = TelemetryLog.create!(
        tree: tree,
        queen_uid: hex_queen_uid,
        rssi: actual_rssi,
        temperature: temp_celsius,
        vcap_voltage: vcap_voltage,
        acoustic: acoustic,
        delta_t: delta_t,
        status_code: status_code,
        growth_points: growth_points,
        ttl: ttl
      )

      # Миттєве нарахування балів у гаманець
      tree.wallet.increment!(:balance, growth_points) if growth_points > 0

      # Запуск ланцюга тривог (Мозок системи)
      AlertDispatchService.analyze_and_trigger!(log)
    end

    Rails.logger.info "🌲 [S-NET] Оброблено: Tree #{hex_did} | Points: +#{growth_points} | Status: #{status_name(status_code)}"

  rescue StandardError => e
    Rails.logger.error "🛑 [Telemetry Error] #{e.message}"
  end

  def status_name(code)
    case code
    when 0 then "Гомеостаз"
    when 1 then "Посуха (Стрес)"
    when 2 then "Аномалія (Критично)"
    when 3 then "Втручання (Вандалізм)" # Додав статус 3 з AlertDispatchService
    else "Невідомо"
    end
  end
end
