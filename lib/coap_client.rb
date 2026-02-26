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

    # Формуємо базовий CoAP заголовок
    # Version: 1, Type: Non-Confirmable (1), Token Length: 0 => 0x50
    # Code: 3 (PUT) => 0x03
    # Message ID: випадкові 16 біт
    message_id = rand(1..65535)
    header = [ 0x50, 0x03, message_id ].pack("CCn")

    # Маркер початку payload
    payload_marker = "\xFF".b

    packet = header + payload_marker + payload.to_s

    socket.send(packet, 0, host, port)
    Rails.logger.info "📡 [CoapClient] Downlink відправлено на #{host}:#{port}, розмір: #{packet.bytesize} байт"
  rescue StandardError => e
    Rails.logger.error "🚨 [CoapClient] Помилка відправки на #{host}: #{e.message}"
    raise e
  ensure
    socket&.close
  end
end
