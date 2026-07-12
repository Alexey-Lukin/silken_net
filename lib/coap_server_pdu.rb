# frozen_string_literal: true

# = =====================================================================
# 🛡️ CoapServerPdu — pure серверний CoAP-парсер вхідної Брами (RFC 7252)
# = =====================================================================
#
# Дзеркало firmware/queen/coap_pdu.h [FW.56]: Королева будує CON PUT
# /telemetry/batch/<uid> власноруч (SIM7070G — UDP-труба), цей модуль той
# самий wire розбирає на боці Rails. Жодних сокетів і side-effect'ів —
# lib/daemons/coap_listener лишає собі тільки UDP-клей, тож граматика
# доводиться e2e софтом: golden-вектори C-білдера заморожені в обох тестах
# (firmware/test/test_at_engine.c ↔ spec/lib/coap_server_pdu_spec.rb).
#
# Чому НЕ data.index("\xFF"): глобальний пошук маркера знаходив 0xFF у
# заголовку (MID = coap_mid++ → кожен 256-й flush) чи опціях → опції не
# парсились, батч падав «невідомим маршрутом», але ACK 2.04 уже був
# відправлений ДО парсингу → Coap_Reply_Confirms → Королева чистила CIFO
# [FW.51] → тиха втрата години телеметрії лісу. Маркер легітимний лише на
# МЕЖІ опцій — тому тут покроковий парсер, а ACK тепер ПІСЛЯ маршрутизації:
# 2.04 = «ліс почуто», 4.04/RST = «кеш не чисти, повтори».
#
# Канон: docs/03_02_Queen_Gateway_Firmware §4 (wire-розмова + e2e parity).
class CoapServerPdu
  TYPE_CON = 0
  TYPE_NON = 1
  TYPE_ACK = 2
  TYPE_RST = 3

  CODE_GET         = 0x01 # 0.01 — [FW.60] Queen-ініційований downlink-poll
  CODE_PUT         = 0x03 # 0.03
  CODE_CHANGED     = 0x44 # 2.04 — єдиний код, що Coap_Reply_Confirms зарахує
  CODE_CONTENT     = 0x45 # 2.05 — [FW.60] piggyback-відповідь poll із payload
  CODE_NOT_FOUND   = 0x84 # 4.04 — клас 4 → Королева тримає кеш і повторює

  OPT_URI_PATH    = 11
  OPT_URI_QUERY   = 15
  PAYLOAD_MARKER  = 0xFF
  HEADER_SIZE     = 4
  MAX_TKL         = 8 # RFC 7252 §3: TKL 9..15 зарезервовано → format error

  Request = Struct.new(:version, :type, :tkl, :code, :message_id, :token,
                       :uri_path, :uri_query, :payload, keyword_init: true)

  # Вердикт обробки датаграми. reply — байти відповіді (nil = мовчимо:
  # NON-запит або сміття без читабельного заголовка). Для :downlink_poll
  # reply будує CoapGate ПІСЛЯ derivation черги (build_content на request).
  Intake = Struct.new(:status, :reply, :gateway_uid, :payload, :request, :query,
                      keyword_init: true)

  class << self
    # Датаграма → Request або nil (malformed). Опції проходяться послідовно:
    # payload починається лише з маркера 0xFF на межі опцій (RFC 7252 §3).
    def parse_request(data)
      return nil if data.nil? || data.bytesize < HEADER_SIZE

      first = data.getbyte(0)
      version = first >> 6
      tkl     = first & 0x0F
      return nil unless version == 1 && tkl <= MAX_TKL
      return nil if HEADER_SIZE + tkl > data.bytesize

      request = Request.new(
        version: version,
        type: (first >> 4) & 0x03,
        tkl: tkl,
        code: data.getbyte(1),
        message_id: data.byteslice(2, 2).unpack1("n"),
        token: data.byteslice(HEADER_SIZE, tkl),
        uri_path: [],
        uri_query: [],
        payload: nil
      )

      parse_options(data, HEADER_SIZE + tkl, request) ? request : nil
    end

    # ACK-заголовок: ver=1, type=ACK, TKL + токен луною, код piggyback-відповіді,
    # MID нашого CON — рівно те, що firmware Coap_Reply_Confirms звіряє.
    def build_ack(request, code:)
      [ (1 << 6) | (TYPE_ACK << 4) | request.tkl, code, request.message_id ]
        .pack("CCn") + request.token
    end

    # RST на нечитабельне тіло при читабельному заголовку (RFC 7252 §4.2):
    # клас не-2.xx → Королева кеш НЕ чистить. На <4 байти відповісти нічим.
    def build_rst(data)
      return nil if data.nil? || data.bytesize < HEADER_SIZE

      [ (1 << 6) | (TYPE_RST << 4), 0x00, data.byteslice(2, 2).unpack1("n") ].pack("CCn")
    end

    # [FW.60] 2.05 Content piggyback з payload — відповідь на downlink-poll.
    # Порожній payload легальний RFC-ом лише без маркера, але наш контракт
    # завжди несе конверт (мінімум time-only, 32 Б) → маркер завжди присутній.
    def build_content(request, payload:)
      build_ack(request, code: CODE_CONTENT) + PAYLOAD_MARKER.chr(Encoding::BINARY) + payload.b
    end

    # Повний вердикт Брами для одного UDP-датаграма — те, що демон робить
    # між recvfrom і perform_async, без сокетів.
    def handle_telemetry_datagram(data)
      request = parse_request(data)
      return Intake.new(status: :malformed, reply: build_rst(data)) if request.nil?

      # Piggyback-відповідь шлемо лише на CON; NON обробляємо мовчки.
      reply = ->(code) { request.type == TYPE_CON ? build_ack(request, code: code) : nil }

      segments = request.uri_path
      if request.code == CODE_PUT && segments.first(2) == %w[telemetry batch] &&
         request.payload
        Intake.new(status: :telemetry_batch, reply: reply.call(CODE_CHANGED),
                   gateway_uid: segments[2], payload: request.payload)
      elsif request.code == CODE_PUT && segments.first(2) == %w[device event] &&
            request.payload
        # [SEC.21 L1] Device-event 0x57: підписаний cleartext-конверт від
        # Королеви ([ver|ts|count|records|sig:64], тег SLKN-QEVT1) —
        # DeviceEventWorker верифікує gateway-origin (LoRa-ключа не торкається).
        Intake.new(status: :device_event, reply: reply.call(CODE_CHANGED),
                   gateway_uid: segments[2], payload: request.payload)
      elsif request.code == CODE_GET && segments.first == "poll" && segments[1]
        # [FW.60] Downlink-poll (Queen питає pending одразу після флашу,
        # LwM2M Queue-Mode). reply тут НЕ будується: CoapGate спершу derive'ить
        # чергу (Downlink::PendingQueueService), тоді build_content(request).
        # NON-GET легальний парсеру, але контракту не відповідає → мовчання
        # вирішує CoapGate (poll без CON не ретраїться Королевою — дроп чесніший).
        Intake.new(status: :downlink_poll, gateway_uid: segments[1],
                   request: request, query: parse_query(request.uri_query))
      elsif request.code == CODE_GET && segments.first == "ota" && segments[1]
        # [FW.60] Stateless chunk-server: Queen-driven fetch відсутніх чанків
        # (?v=<firmware_id>&ch=<n>) — вона єдина знає свій bitmap.
        Intake.new(status: :ota_chunk_fetch, gateway_uid: segments[1],
                   request: request, query: parse_query(request.uri_query))
      else
        Intake.new(status: :unknown_route, reply: reply.call(CODE_NOT_FOUND))
      end
    end

    private

    # [FW.60] Uri-Query опції → {"fw" => "123", ...}. RFC 7252: кожна пара =
    # окрема опція 15; &-склейку в одній опції теж розкладаємо (стійкість до
    # не-RFC-чистих клієнтів, вона ж вкусила перший драфт цієї ж спеки).
    def parse_query(pairs)
      pairs.flat_map { |p| p.split("&") }
           .to_h { |pair| k, v = pair.split("=", 2); [ k, v.to_s ] }
    end

    # Опційний цикл: на межі кожної опції або маркер+payload, або
    # delta/length-нібли (13 → +1 ext-байт, 14 → +2 BE, 15 → reserved).
    # false = format error (обірвані ext-байти, перебіг, порожній payload).
    def parse_options(data, cursor, request)
      option_number = 0

      while cursor < data.bytesize
        byte = data.getbyte(cursor)

        if byte == PAYLOAD_MARKER
          payload = data.byteslice(cursor + 1, data.bytesize - cursor - 1)
          return false if payload.empty? # маркер без payload — format error

          request.payload = payload
          return true
        end

        cursor += 1
        delta, cursor  = read_extended(data, byte >> 4,   cursor)
        return false unless cursor
        length, cursor = read_extended(data, byte & 0x0F, cursor)
        return false unless cursor
        return false if cursor + length > data.bytesize

        option_number += delta
        value = data.byteslice(cursor, length)
        cursor += length

        request.uri_path << value if option_number == OPT_URI_PATH
        request.uri_query << value if option_number == OPT_URI_QUERY
      end

      true # запит без payload — синтаксично валідний (маршрут вирішить)
    end

    def read_extended(data, nibble, cursor)
      case nibble
      when 0..12 then [ nibble, cursor ]
      when 13
        return [ nil, nil ] if cursor >= data.bytesize

        [ data.getbyte(cursor) + 13, cursor + 1 ]
      when 14
        return [ nil, nil ] if cursor + 2 > data.bytesize

        [ data.byteslice(cursor, 2).unpack1("n") + 269, cursor + 2 ]
      else
        [ nil, nil ] # 15 — reserved (RFC 7252 §3.1)
      end
    end
  end
end
