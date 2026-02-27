# frozen_string_literal: true

require "openssl"

class TelemetryUnpackerService
  # Наш ключ з C-коду: {0x2B7E1516, 0x28AED2A6, 0xABF71588, ...}
  # Перетворюємо масив 32-бітних чисел на суцільний 32-байтний рядок
  RAW_AES_KEY = [
    0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
    0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D
  ].pack("N8").freeze

  def self.call(binary_batch)
    new(binary_batch).perform
  end

  def initialize(binary_batch)
    @binary_batch = binary_batch

    # Ініціалізуємо AES-256 у режимі ECB (Electronic Codebook)
    @cipher = OpenSSL::Cipher.new("aes-256-ecb")
    @cipher.decrypt
    @cipher.key = RAW_AES_KEY
    @cipher.padding = 0 # ВАЖЛИВО! C-код не використовує PKCS7 відступи
  end

  def perform
    # Розрізаємо масив на шматки рівно по 21 байту
    chunks = @binary_batch.scan(/.{1,21}/m)

    chunks.each do |chunk|
      next if chunk.bytesize < 21 # Ігноруємо "биті" залишки ефіру

      process_chunk(chunk)
    end
  end

  private

  def process_chunk(chunk)
    # 1. Читаємо метадані від Королеви (перші 5 байтів)
    # 'N' - 32-бітне ціле без знаку (UID), 'C' - 8-бітне ціле без знаку (RSSI)
    queen_uid, inverted_rssi = chunk[0..4].unpack("NC")
    actual_rssi = -inverted_rssi # Відновлюємо від'ємний RSSI

    # 2. Витягуємо зашифрований пакет від Солдата (наступні 16 байтів)
    encrypted_payload = chunk[5..20]

    # 3. Розшифровуємо (Нульова довіра / Zero-Trust)
    begin
      # УВАГА: Для безпечного використання одного екземпляра cipher у циклі,
      # необхідно викликати reset перед кожною розшифровкою.
      @cipher.reset 
      decrypted = @cipher.update(encrypted_payload) + @cipher.final
    rescue OpenSSL::Cipher::CipherError => e
      Rails.logger.error "🛑 Помилка розшифровки пакета від Королеви #{queen_uid.to_s(16)}: #{e.message}"
      return
    end

    # 4. Розбираємо розшифровані 16 байтів згідно з нашою C-структурою
    # N  - DID (32-бітне без знаку, Big-Endian)
    # n  - Напруга Vcap (16-бітне без знаку, Big-Endian)
    # c  - Температура (8-бітне ЗІ ЗНАКОМ)
    # C  - Акустика (8-бітне без знаку)
    # n  - Delta T (16-бітне без знаку, Big-Endian)
    # C  - Біо-контракт (8-бітне без знаку)
    # C  - TTL (8-бітне без знаку)
    # a4 - Padding (4 байти сміття/резерву)
    parsed_data = decrypted.unpack("N n c C n C C a4")

    did            = parsed_data[0]
    vcap_voltage   = parsed_data[1]
    temp_celsius   = parsed_data[2]
    acoustic       = parsed_data[3]
    delta_t        = parsed_data[4]
    bio_contract   = parsed_data[5]
    ttl            = parsed_data[6]

    # 5. Хірургія Біо-Контракту (Витягуємо статус і бали з одного байта)
    # Зсуваємо вправо на 6 бітів для статусу
    status_code = bio_contract >> 6

    # Накладаємо маску 00111111 (0x3F), щоб ізолювати 6 молодших бітів росту
    growth_points = bio_contract & 0x3F

    # 6. Валідація та Збереження (Тут запис у БД)
    hex_did = did.to_s(16).upcase
    hex_queen_uid = queen_uid.to_s(16).upcase

    Rails.logger.info(
      "🌲 Дерево [DID: #{hex_did}] | " \
      "Сигнал: #{actual_rssi}dBm (Від: #{hex_queen_uid}) | " \
      "Temp: #{temp_celsius}°C | Vcap: #{vcap_voltage}mV | " \
      "Метаболізм: #{delta_t}s | Акустика: #{acoustic} | " \
      "Статус: #{status_name(status_code)} | Бали: #{growth_points}"
    )

    # Знаходимо дерево за його криптографічним ідентифікатором
    tree = Tree.find_by(did: hex_did)

    unless tree
      Rails.logger.warn("⚠️ [СИСТЕМНИЙ ШУМ] Дерево з DID #{hex_did} не знайдено в базі. Телеметрія проігнорована.")
      return
    end

    begin
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

      # Фізично додаємо зароблені бали на баланс гаманця дерева
      tree.wallet.increment!(:balance, growth_points) if growth_points > 0

      # Далі йде виклик AlertDispatchService...
      # ВЕСЬ аналіз делегуємо спеціалізованому сервісу:
      AlertDispatchService.analyze_and_trigger!(log)

    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("🛑 Помилка збереження телеметрії: #{e.message}")
    end
  end

  # Допоміжний метод для перекладу цифрового статусу в людську мову
  def status_name(code)
    case code
    when 0 then "Гомеостаз"
    when 1 then "Посуха (Стрес)"
    when 2 then "Аномалія (Критично)"
    else "Невідомо"
    end
  end
end
