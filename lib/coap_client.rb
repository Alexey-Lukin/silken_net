# frozen_string_literal: true

require "socket"
require "uri"

class CoapClient
  # Відправляє CoAP PUT запит через UDP без блокування основного потоку Rails.
  # Підтримує автоматичне кодування Uri-Path та Uri-Query опцій.
  def self.put(url, payload)
    uri = URI.parse(url)
    host = uri.host
    port = uri.port || 5683

    socket = UDPSocket.new

    # 1. Формуємо базовий CoAP заголовок (4 байти)
    # Version: 1, Type: Non-Confirmable (1), Token Length: 0 => 0x50
    # Code: 3 (PUT) => 0x03
    # Message ID: випадкові 16 біт для ідентифікації пакета в ефірі
    message_id = rand(1..65535)
    header = [ 0x50, 0x03, message_id ].pack("CCn")

    # 2. МАРШРУТИЗАЦІЯ (Uri-Options)
    # Згідно RFC 7252, опції мають йти в пакеті за зростанням їхніх номерів (Delta encoding).
    options_payload = "".b
    prev_opt = 0

    # Опція 11: Uri-Path (Наприклад: 'actuator', 'ota', 'tinyml')
    paths = uri.path.split('/').reject(&:empty?)
    paths.each do |segment|
      delta = 11 - prev_opt
      options_payload += encode_option(delta, segment)
      prev_opt = 11
    end

    # Опція 15: Uri-Query (Наприклад: 'chunk=1', 'total=50', 'final=true')
    if uri.query
      queries = uri.query.split('&')
      queries.each do |q|
        delta = 15 - prev_opt
        options_payload += encode_option(delta, q)
        prev_opt = 15
      end
    end

    # 3. МАРКЕР ТА ТІЛО ПАКЕТА
    # Маркер 0xFF відокремлює заголовок/опції від корисного навантаження (payload).
    payload_marker = "\xFF".b

    # Збираємо фінальний бінарний кристал.
    # Використовуємо .b (ASCII-8BIT), щоб уникнути корупції байтів при шифруванні AES.
    packet = header + options_payload + payload_marker + payload.b

    socket.send(packet, 0, host, port)
    
    Rails.logger.info "📡 [CoapClient] Downlink відправлено на #{host}:#{port} (#{uri.path}), розмір: #{packet.bytesize} байт"

  rescue StandardError => e
    Rails.logger.error "🚨 [CoapClient] Помилка відправки на #{host}: #{e.message}"
    raise e
  ensure
    socket&.close
  end

  private

  # Допоміжний метод для кодування CoAP опцій.
  # Підтримує розширені поля довжини та дельти (до 268 байт), що необхідно для довгих URL.
  def self.encode_option(delta, value)
    buffer = "".b
    val_len = value.bytesize
    
    # Розрахунок початкових значень заголовка (нібблів)
    d_header = delta < 13 ? delta : 13
    l_header = val_len < 13 ? val_len : 13
    
    # Перший байт: [Delta 4-bit][Length 4-bit]
    buffer += [(d_header << 4) | l_header].pack("C")
    
    # Додатковий байт для дельти (якщо дельта >= 13)
    buffer += [delta - 13].pack("C") if delta >= 13
    
    # Додатковий байт для довжини (якщо довжина >= 13)
    buffer += [val_len - 13].pack("C") if val_len >= 13
    
    buffer + value.b
  end
end
