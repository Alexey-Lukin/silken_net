# frozen_string_literal: true

require "socket"
require "uri"
require "timeout"

class CoapClient
  MAX_PACKET_SIZE = 2048
  DEFAULT_TIMEOUT = 7

  # --- ГІБРИДНІ ВИКЛЮЧЕННЯ (The Hierarchy of Truth) ---
  class Error < StandardError; end
  class ClientError < Error; end # 4.xx: Помилка в нашому запиті
  class ServerError < Error; end # 5.xx: Помилка на стороні STM32/Gateway
  class NetworkError < Error; end # Проблеми з UDP/Timeout

  Response = Struct.new(:success?, :code, :payload, :class_string, keyword_init: true)

  def self.put(url, payload, timeout: DEFAULT_TIMEOUT)
    uri = URI.parse(url)
    host = uri.host
    port = uri.port || 5683
    socket = UDPSocket.new

    message_id = rand(1..65535)
    header = [ 0x40, 0x03, message_id ].pack("CCn")

    options_payload = "".b
    current_opt_number = 0

    # Uri-Path (11)
    uri.path.split("/").reject(&:empty?).each do |segment|
      options_payload += encode_option(11 - current_opt_number, segment)
      current_opt_number = 11
    end

    # Uri-Query (15)
    if uri.query
      uri.query.split("&").each do |q|
        options_payload += encode_option(15 - current_opt_number, q)
        current_opt_number = 15
      end
    end

    packet = header + options_payload + "\xFF".b + payload.b

    begin
      socket.send(packet, 0, host, port)
      
      if IO.select([ socket ], nil, nil, timeout)
        response_data, _sender = socket.recvfrom(MAX_PACKET_SIZE)
        parse_response(response_data, message_id)
      else
        raise NetworkError, "Шлюз #{host} не відповів (ACK timeout)"
      end
    rescue StandardError => e
      Rails.logger.error "🛑 [CoapClient] Провал зв'язку: #{e.message}"
      raise e
    ensure
      socket&.close
    end
  end

  private

  def self.parse_response(data, expected_message_id)
    header = data.unpack("CCn")
    return nil unless header

    _type = (header[0] >> 4) & 0x03
    code = header[1]
    msg_id = header[2]

    raise NetworkError, "MID mismatch" unless msg_id == expected_message_id

    # Класифікація CoAP-коду
    class_code = code >> 5
    detail_code = code & 0x1F
    class_string = "#{class_code}.#{detail_code.to_s.rjust(2, '0')}"

    case class_code
    when 2 # Success (Created, Deleted, Valid, Changed, Content)
      Response.new(success?: true, code: code, class_string: class_string, payload: extract_payload(data))
    when 4 # Client Error (Bad Request, Unauthorized, Not Found, etc.)
      Rails.logger.warn "❌ [CoapClient] Client Error #{class_string}"
      raise ClientError, "CoAP Client Error: #{class_string}"
    when 5 # Server Error (Internal Server Error, Not Implemented, Gateway Timeout)
      Rails.logger.error "🔥 [CoapClient] Server Error #{class_string}"
      raise ServerError, "CoAP Server Error: #{class_string}"
    else
      Response.new(success?: false, code: code, class_string: class_string, payload: nil)
    end
  end

  def self.encode_option(delta, value)
    buffer = "".b
    val_len = value.bytesize
    d_header = delta < 13 ? delta : 13
    l_header = val_len < 13 ? val_len : 13
    buffer += [ (d_header << 4) | l_header ].pack("C")
    buffer += [ delta - 13 ].pack("C") if delta >= 13
    buffer += [ val_len - 13 ].pack("C") if val_len >= 13
    buffer + value.b
  end

  def self.extract_payload(data)
    marker_idx = data.index("\xFF".b)
    marker_idx ? data[(marker_idx + 1)..-1] : nil
  end
end
