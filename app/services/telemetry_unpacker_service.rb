# frozen_string_literal: true

require "openssl"

class TelemetryUnpackerService
  # Наш ключ з C-коду STM32: {0x2B7E1516, 0x28AED2A6, ...}
  # Перетворюємо масив 32-бітних чисел на суцільний 32-байтний рядок (256 біт)
  RAW_AES_KEY = [
    0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
    0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D
  ].pack("N8").freeze

  # Розмір одного логічного запису в батчі від Королеви: 
  # 4 (Queen UID) + 1 (RSSI) + 16 (Encrypted Payload від Солдата) = 21 байт
  CHUNK_SIZE = 21

  def self.call(binary_batch)
    new(binary_batch).perform
  end

  def initialize(binary_batch)
    @binary_batch = binary_batch

    # Ініціалізуємо AES-256 у режимі ECB (дзеркало апаратного модуля STM32)
    @cipher = OpenSSL::Cipher.new("aes-256-ecb")
    @cipher.decrypt
    @cipher.key = RAW_AES_KEY
    @cipher.padding = 0 # C-код не використовує PKCS7 відступи
  end

  def perform
    # Розрізаємо масив на шматки рівно по 21 байту
    # .b (ASCII-8BIT) захищає від помилок кодування при зустрічі невалідних UTF-8 символів
    chunks = @binary_batch.b.scan(/.{1,#{CHUNK_SIZE}}/m)

    chunks.each do |chunk|
      next if chunk.bytesize < CHUNK_SIZE # Фільтруємо "сміття" ефіру

      process_chunk(chunk)
    end
  end

  private

  def process_chunk(chunk)
    # 1. МЕТАДАНІ КОРОЛЕВИ (Шлюзу)
    # 'N' - 32-бітне ціле (UID), 'C' - 8-бітне без знаку (RSSI)
    queen_uid, inverted_rssi = chunk[0..4].unpack("NC")
    actual_rssi = -inverted_rssi # Відновлюємо негативне значення децибел-міліват

    # 2. ШИФРОВАНИЙ ВАНТАЖ (Пакет Солдата)
    encrypted_payload = chunk[5..20]

    # 3. РОЗШИФРОВКА (Zero-Trust)
    begin
      @cipher.reset # Обов'язково скидаємо стан для коректної роботи в циклі
      decrypted = @cipher.update(encrypted_payload) + @cipher.final
    rescue OpenSSL::Cipher::CipherError => e
      Rails.logger.error "🛑 [AES] Помилка розшифровки для Королеви #{queen_uid.to_s(16).upcase}: #{e.message}"
      return
    end

    # 4. ДЕКОДУВАННЯ БІО-МЕТРИК (16 байтів)
    # Відповідає структурі в main.c: [DID:4] [Vcap:2] [Temp:1] [Acoustic:1] [Time:2] [Bio:1] [TTL:1] [Pad:4]
    parsed_data = decrypted.unpack("N n c C n C C a4")

    did            = parsed_data[0]
    vcap_voltage   = parsed_data[1]
    temp_celsius   = parsed_data[2]
    acoustic       = parsed_data[3]
    delta_t        = parsed_data[4]
    bio_contract   = parsed_data[5]
    ttl            = parsed_data[6]

    # 5. ХІРУРГІЯ БІО-КОНТРАКТУ (1 байт)
    # [Статус: 2 біти] [Бали: 6 бітів]
    status_code = bio_contract >> 6
    growth_points = bio_contract & 0x3F

    hex_did = did.to_s(16).upcase
    hex_queen_uid = queen_uid.to_s(16).upcase

    # Пошук цифрового двійника в БД
    tree = Tree.find_by(did: hex_did)

    unless tree
      Rails.logger.warn("⚠️ [СИСТЕМНИЙ ШУМ] DID #{hex_did} не знайдено. Пакет відхилено.")
      return
    end

    # 6. АТОМАРНЕ ЗБЕРЕЖЕННЯ ТА ТРИГЕРИ
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

      # Нарахування балів у Wallet дерева
      tree.wallet.increment!(:balance, growth_points) if growth_points > 0

      # Передача даних у систему раннього попередження (EWS)
      AlertDispatchService.analyze_and_trigger!(log)
    end

    Rails.logger.info "🌲 [S-NET] Tree #{hex_did} | +#{growth_points} pts | #{status_name(status_code)}"

  rescue StandardError => e
    Rails.logger.error "🛑 [Telemetry Error] #{e.message}"
  end

  def status_name(code)
    case code
    when 0 then "Гомеостаз"
    when 1 then "Посуха (Стрес)"
    when 2 then "Аномалія (Критично)"
    when 3 then "Втручання (Вандалізм)"
    else "Невідомо"
    end
  end
end
