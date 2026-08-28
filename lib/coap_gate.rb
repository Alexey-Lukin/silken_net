# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "base64"

# [FW.56] CoAP-датаграма → вердикт + side-effect'и, ВИНЕСЕНІ з демона
# lib/daemons/coap_listener у тестований модуль. Money-path-інваріант
# «enqueue ПЕРЕД ACK 2.04» (Королева чистить CIFO [FW.51] лише коли батч
# справді у черзі) тепер СТРУКТУРНИЙ: enqueue живе тут, перед `return reply`,
# а демон робить `socket.send(reply)` уже ПІСЛЯ повернення — ACK фізично не
# може випередити `perform_async`. Раніше інваріант тримався лише порядком
# рядків у лупі + `raise` у rescue (демон редаговано PERF.1 без guard-тесту).
module CoapGate
  MAX_PACKET_SIZE = 2048

  # [FW.60] Дедуп ДУБЛЬОВАНОЇ датаграми poll'а: якщо той самий запит фізично
  # приходить двічі (мережеве дублювання UDP), без кешу деривація відпрацювала б
  # удруге і спалила б НАСТУПНУ pending-команду у відповідь, яку Королева вже не
  # прочитає. Один слот на uid достатній — Queen шле строго послідовно; демон
  # однопроцесний і однопотоковий → без mutex.
  #
  # 🔴 [FW.63] ЧОГО цей кеш НЕ закриває — і що тут стверджувалось помилково:
  # втрату самої 2.05. Poll-тракт Королеви ретрансміту НЕ має — `Queen_Poll_Downlink`
  # робить `coap_mid++` на кожну спробу і виходить при порожній відповіді, а
  # `Sim7070_Udp_Fetch` — одна розмова без внутрішніх ретраїв. Same-MID retry
  # справді існує, але в uplink-**PUT** (`COAP_MAX_RETRIES` навколо незмінного
  # `coap_mid`), і саме звідти твердження про «CON-ретрансміт poll'а» помилково
  # перенесли сюди. Тож загублена 2.05 з CMD губить наказ назавжди: він уже
  # `acknowledged`, поза `.pending`, і жоден наступний poll його не перевидасть.
  REPLY_CACHE = {} # uid => [message_id, reply_bytes]

  # Обробляє одну датаграму. Повертає CoAP-reply (String) для відправки, або
  # nil = мовчазний дроп (oversized/truncate — FW.51 Королева тримає кеш і
  # ретраїть). Кидає далі, якщо enqueue впав (Redis) — демон-rescue логне,
  # `reply` не повернеться → `socket.send` НЕ станеться → Королева повторить.
  def self.handle_datagram(data:, gateway_ip:, timestamp: Time.current)
    # Ядро мовчки тне UDP понад буфер: обрізаний батч лишається валідним CoAP
    # і у воркері впав би на MIC як «fraud» (P0-алерт полює на атаку, якої нема).
    # bytesize == буфер — прагматичний proxy трункейта; дроп без відповіді →
    # Королева тримає кеш і ретраїть (FW.51-семантика).
    if data.bytesize >= MAX_PACKET_SIZE
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "oversized" })
      puts "⚠️  [#{timestamp.strftime('%T')}] Датаграма ≥#{MAX_PACKET_SIZE}б від #{gateway_ip} — обрізана ядром, дроп"
      return nil
    end

    result = CoapServerPdu.handle_telemetry_datagram(data)

    # Лічильники межі: enqueued (тут) ↔ success (у воркері) — дельта між ними =
    # втрати Redis→обробка; malformed/unknown_route видимі ЛИШЕ звідси.
    case result.status
    when :telemetry_batch
      encoded_payload = Base64.strict_encode64(result.payload)
      begin
        # [FW.51] enqueue ПЕРЕД ACK: reply повертається лише ПІСЛЯ успішного
        # perform_async, тож Королева не почує 2.04 (і не почистить CIFO),
        # якщо батч не став у чергу.
        # [ARCH.41] Мітка прийому ставиться ТУТ — у демоні, що першим побачив
        # датаграму. Вона їде job-аргументом, тож переживає Sidekiq-ретрай і
        # лишається тією самою добою для cold-start деривації Лоренца.
        UnpackTelemetryWorker.perform_async(encoded_payload, gateway_ip, result.gateway_uid,
                                            Time.now.utc.iso8601)
      rescue StandardError
        # [PERF.1] Redis-enqueue-fail був невидимий: generic-rescue демона
        # ковтав без метрики → тихий drop пакетів під навантаженням.
        SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "enqueue_error" })
        raise
      end
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "enqueued" })
      puts "📥 [#{timestamp.strftime('%T')}] Пакет від #{result.gateway_uid || gateway_ip} прийнято (#{result.payload.bytesize}б)"
    when :device_event
      # [SEC.21] той самий транспорт-шлях, що телеметрія: enqueue → ACK
      encoded = Base64.strict_encode64(result.payload)
      DeviceEventWorker.perform_async(encoded, result.gateway_uid)
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "device_event" })
    when :downlink_poll, :ota_chunk_fetch
      # [FW.60] Queen-ініційований downlink (poll-після-флашу). Derivation
      # синхронна в демоні (кілька DB-читань на poll) — свідома стеля
      # single-loop'а: на TRL-3 одна Королева, ~1 poll/flush; масштаб-відповідь
      # (окремий потік/процес) — коли Королев стане багато, не зараз.
      return handle_queen_pull(result, timestamp)
    when :unknown_route
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "unknown_route" })
      puts "⚠️  [#{timestamp.strftime('%T')}] Відхилено (4.04): невідомий маршрут від #{gateway_ip}"
    when :malformed
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "malformed" })
      puts "⚠️  [#{timestamp.strftime('%T')}] Нечитабельний датаграм від #{gateway_ip} (#{data.bytesize}б) — RST"
    end

    result.reply
  end

  # [FW.60] Спільна обробка обох Queen-pull маршрутів (poll + ota chunk-server).
  def self.handle_queen_pull(result, timestamp)
    request = result.request
    # Контракт = CON (Королевин білдер завжди CON; NON не ретраїться нею,
    # тож мовчазний дроп чесніший за неретрансльовану відповідь).
    return nil unless request.type == CoapServerPdu::TYPE_CON

    cached_mid, cached_reply = REPLY_CACHE[result.gateway_uid]
    if cached_mid == request.message_id
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "poll_retransmit" })
      return cached_reply
    end

    gateway = Gateway.find_by(uid: result.gateway_uid)
    unless gateway
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "poll_unknown_uid" })
      return CoapServerPdu.build_ack(request, code: CoapServerPdu::CODE_NOT_FOUND)
    end

    envelope =
      if result.status == :downlink_poll
        Downlink::PendingQueueService.poll_reply(gateway: gateway, query: result.query)
      else
        Downlink::PendingQueueService.ota_chunk_reply(gateway: gateway, query: result.query)
      end

    reply =
      if envelope
        CoapServerPdu.build_content(request, payload: envelope)
      else
        # Нема ключа / чужа-завершена OTA-версія / ch поза межами → 4.04:
        # Королева бачить не-2.05 і не почне decrypt (poll) або перечитає
        # hint наступним poll'ом (ota).
        CoapServerPdu.build_ack(request, code: CoapServerPdu::CODE_NOT_FOUND)
      end

    REPLY_CACHE[result.gateway_uid] = [ request.message_id, reply ]
    SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(
      labels: { status: result.status == :downlink_poll ? "downlink_poll" : "ota_chunk" }
    )
    puts "📤 [#{timestamp.strftime('%T')}] #{result.status == :downlink_poll ? 'Poll' : 'OTA-чанк'} " \
         "#{result.gateway_uid}: відповідь #{reply.bytesize}б"
    reply
  end
  private_class_method :handle_queen_pull
end
