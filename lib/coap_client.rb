# frozen_string_literal: true

require "socket"
require "uri"
require "timeout"

class CoapClient
  MAX_PACKET_SIZE = 2048
  DEFAULT_TIMEOUT = 7 # Збільшено до 7с для врахування затримок супутникового зв'язку

  # Структура відповіді (Легка та швидка)
  Response = Struct.new(:success?, :code, :payload, keyword_init: true)

  def self.put(url, payload, timeout: DEFAULT_TIMEOUT)
    uri = URI.parse(url)
    host = uri.host
    port = uri.port || 5683

    socket = UDPSocket.new

    # 1. ФОРМУВАННЯ ЗАГОЛОВКА (Confirmable PUT)
    # Ver: 1, Type: CON (0), TKL: 0 => 0x40
    # Code: 0.03 (PUT) => 0x03
    message_id = rand(1..65535)
    header = [0x40, 0x03, message_id].pack("CCn")

    # 2. МАРШРУТИЗАЦІЯ (Uri-Options)
    # Опції МАЮТЬ бути відсортовані за номером
    options_payload = "".b
    current_opt_number = 0

    # Uri-Path (Опція №11)
    paths = uri.path.split('/').reject(&:empty?)
    paths.each do |segment|
      options_payload += encode_option(11 - current_opt_number, segment)
      current_opt_number = 11
    end

    # Uri-Query (Опція №15)
    if uri.query
      queries = uri.query.split('&')
      queries.each do |q|
        options_payload += encode_option(15 - current_opt_number, q)
        current_opt_number = 15
      end
    end

    # 3. ФОРМУВАННЯ ПАКЕТА
    payload_marker = "\xFF".b
    packet = header + options_payload + payload_marker + payload.b

    # 4. ВІДПРАВКА
    begin
      socket.send(packet, 0, host, port)
      Rails.logger.debug "📡 [CoapClient] CON PUT #{uri.path} -> #{host} [MID: #{message_id}]"

      # 5. ОЧІКУВАННЯ ACK (Confirmable Loop)
      if IO.select([socket], nil, nil, timeout)
        response_data, _sender = socket.recvfrom(MAX_PACKET_SIZE)
        parse_response(response_data, message_id)
      else
        raise Timeout::Error, "Шлюз #{host} не відповів (ACK timeout)"
      end
    rescue StandardError => e
      Rails.logger.error "🛑 [CoapClient] Провал зв'язку з #{host}: #{e.message}"
      raise e
    ensure
      socket&.close
    end
  end

  private

  def self.encode_option(delta, value)
    buffer = "".b
    val_len = value.bytesize
    
    # Спрощена логіка для невеликих дельт та довжин (до 12 байт)
    # Coap використовує 4 біти для дельти та 4 біти для довжини
    d_header = delta < 13 ? delta : 13
    l_header = val_len < 13 ? val_len : 13
    
    buffer += [(d_header << 4) | l_header].pack("C")
    
    # Додаткові байти для розширених дельт/довжин (якщо потрібно)
    buffer += [delta - 13].pack("C") if delta >= 13
    buffer += [val_len - 13].pack("C") if val_len >= 13
    
    buffer + value.b
  end

  def self.parse_response(data, expected_message_id)
    header = data.unpack("CCn")
    return nil unless header

    type = (header[0] >> 4) & 0x03
    code = header[1]
    msg_id = header[2]

    # Ми очікуємо ACK (Type 2) з тим самим Message ID
    if type == 2 && msg_id == expected_message_id
      # Коди успіху 2.xx (від 64 до 95)
      success = code >= 64 && code < 96
      
      Response.new(
        success?: success,
        code: code,
        payload: extract_payload(data)
      )
    else
      Rails.logger.warn "⚠️ [CoapClient] Отримано неочікуваний пакет (Type: #{type}, MID: #{msg_id})"
      Response.new(success?: false, code: code, payload: nil)
    end
  end

  def self.extract_payload(data)
    marker_idx = data.index("\xFF".b)
    marker_idx ? data[(marker_idx + 1)..-1] : nil
  end
end
