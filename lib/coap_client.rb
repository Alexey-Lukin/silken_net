# frozen_string_literal: true

require "socket"
require "uri"
require "ostruct"
require "timeout"

class CoapClient
  MAX_PACKET_SIZE = 2048
  DEFAULT_TIMEOUT = 5 # Секунд на очікування ACK від Королеви

  # Відправляє CoAP PUT запит (Confirmable) і чекає на відповідь.
  def self.put(url, payload, timeout: DEFAULT_TIMEOUT)
    uri = URI.parse(url)
    host = uri.host
    port = uri.port || 5683

    socket = UDPSocket.new

    # 1. ФОРМУВАННЯ ЗАГОЛОВКА (Confirmable)
    # Version: 1 (01), Type: Confirmable (00), Token Length: 0 (0000) => 0x40
    # Code: 3 (PUT) => 0x03
    message_id = rand(1..65535)
    header = [ 0x40, 0x03, message_id ].pack("CCn")

    # 2. МАРШРУТИЗАЦІЯ (Uri-Options)
    options_payload = "".b
    prev_opt = 0

    paths = uri.path.split('/').reject(&:empty?)
    paths.each do |segment|
      delta = 11 - prev_opt
      options_payload += encode_option(delta, segment)
      prev_opt = 11
    end

    if uri.query
      queries = uri.query.split('&')
      queries.each do |q|
        delta = 15 - prev_opt
        options_payload += encode_option(delta, q)
        prev_opt = 15
      end
    end

    # 3. МАРКЕР ТА ТІЛО
    payload_marker = "\xFF".b
    packet = header + options_payload + payload_marker + payload.b

    # 4. ВІДПРАВКА
    socket.send(packet, 0, host, port)
    Rails.logger.info "📡 [CoapClient] PUT #{uri.path} на #{host}:#{port} [MsgID: #{message_id}]"

    # 5. ОЧІКУВАННЯ ПІДТВЕРДЖЕННЯ (The Zero-Lag Sync)
    # Використовуємо IO.select, щоб не заблокувати потік назавжди, якщо шлюз офлайн
    if IO.select([socket], nil, nil, timeout)
      response_data, _sender = socket.recvfrom(MAX_PACKET_SIZE)
      parse_response(response_data, message_id)
    else
      raise Timeout::Error, "Шлюз #{host} не надіслав CoAP ACK протягом #{timeout}с."
    end

  rescue StandardError => e
    Rails.logger.error "🚨 [CoapClient] Помилка: #{e.message}"
    raise e
  ensure
    socket&.close
  end

  private

  def self.encode_option(delta, value)
    buffer = "".b
    val_len = value.bytesize
    
    d_header = delta < 13 ? delta : 13
    l_header = val_len < 13 ? val_len : 13
    
    buffer += [(d_header << 4) | l_header].pack("C")
    buffer += [delta - 13].pack("C") if delta >= 13
    buffer += [val_len - 13].pack("C") if val_len >= 13
    
    buffer + value.b
  end

  # Розбираємо відповідь від шлюзу
  def self.parse_response(data, expected_message_id)
    header = data.unpack("CCn")
    type = (header[0] >> 4) & 0x03
    code = header[1]
    msg_id = header[2]

    # Перевіряємо, чи це ACK (Type 2) на наш Message ID
    if type == 2 && msg_id == expected_message_id
      # Коди успіху в CoAP: 2.01 (65), 2.03 (67), 2.04 (68)
      is_success = (code >= 64 && code < 96)
      
      OpenStruct.new(
        success?: is_success,
        code: code,
        payload: extract_payload(data)
      )
    else
      # Якщо прийшов Reset (Type 3) або інший пакет
      OpenStruct.new(success?: false, code: code, payload: nil)
    end
  end

  def self.extract_payload(data)
    marker_idx = data.index("\xFF".b)
    marker_idx ? data[(marker_idx + 1)..-1] : nil
  end
end
