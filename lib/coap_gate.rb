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
        UnpackTelemetryWorker.perform_async(encoded_payload, gateway_ip, result.gateway_uid)
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
    when :unknown_route
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "unknown_route" })
      puts "⚠️  [#{timestamp.strftime('%T')}] Відхилено (4.04): невідомий маршрут від #{gateway_ip}"
    when :malformed
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "malformed" })
      puts "⚠️  [#{timestamp.strftime('%T')}] Нечитабельний датаграм від #{gateway_ip} (#{data.bytesize}б) — RST"
    end

    result.reply
  end
end
