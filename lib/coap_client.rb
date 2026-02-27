# frozen_string_literal: true

require "socket"
require "uri"

class CoapClient
  # Відправляє CoAP PUT запит через UDP без блокування потоку
  def self.put(url, payload)
    uri = URI.parse(url)
    host = uri.host
    port = uri.port || 5683

    socket = UDPSocket.new

    # 1. Формуємо базовий CoAP заголовок
    # Version: 1, Type: Non-Confirmable (1), Token Length: 0 => 0x50
    # Code: 3 (PUT) => 0x03
    # Message ID: випадкові 16 біт
    message_id = rand(1..65535)
    header = [ 0x50, 0x03, message_id ].pack("CCn")

    # 2. МІКРО-КОМПІЛЯТОР ОПЦІЙ (Вбудовуємо шлях та параметри в пакет)
    options_payload = "".b
    prev_opt = 0

    # Опція 11: Uri-Path (Наприклад: 'actuator', 'ota', 'tinyml')
    paths = uri.path.split('/').reject(&:empty?)
    paths.each do |segment|
      delta = 11 - prev_opt
      len = segment.bytesize
      
      raise "URI Segment too long for minimal parser" if len > 12 || delta > 12
      
      options_payload += [(delta << 4) | len].pack("C") + segment.b
      prev_opt = 11
    end

    # Опція 15: Uri-Query (Наприклад: 'chunk=1', 'total=10')
    if uri.query
      queries = uri.query.split('&')
      queries.each do |q|
        delta = 15 - prev_opt
        len = q.bytesize
        
        raise "URI Query too long for minimal parser" if len > 12 || delta > 12
        
        options_payload += [(delta << 4) | len].pack("C") + q.b
        prev_opt = 15
      end
    end

    # 3. Маркер початку payload (Обов'язковий у CoAP)
    payload_marker = "\xFF".b

    # 4. Збираємо ідеальний кристал: Заголовок + Опції + Маркер + Бінарне тіло
    # Використовуємо .b (ASCII-8BIT), щоб AES зашифрований текст не пошкодився
    packet = header + options_payload + payload_marker + payload.b

    socket.send(packet, 0, host, port)
    Rails.logger.info "📡 [CoapClient] Downlink відправлено на #{host}:#{port} (#{uri.path}), розмір: #{packet.bytesize} байт"
  rescue StandardError => e
    Rails.logger.error "🚨 [CoapClient] Помилка відправки на #{host}: #{e.message}"
    raise e
  ensure
    socket&.close
  end
end
