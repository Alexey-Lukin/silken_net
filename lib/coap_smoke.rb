# frozen_string_literal: true

require "socket"

# = =====================================================================
# 🔥 CoapSmoke — freeze-contract зонди Брами через реальний UDP-шлях
# = =====================================================================
#
# [FW.56/INF.6] Generic liveness («хоч щось відповіло») не ловить регресію
# фантомної доставки: старий сервер слав ACK 2.04 ДО парсингу — будь-якому
# читабельному датаграму. Тому кожен зонд звіряє відповідь БАЙТ-У-БАЙТ з
# тим самим freeze-contract, що C-білдер ↔ Rails-парсер
# (firmware/test/test_at_engine.c ↔ spec/lib/coap_server_pdu_spec.rb):
#
#   RST   сміття в опціях (delta-нібл 15)                       → 7000ABCD
#   4.04  невідомий маршрут, MID=0x00FF + 0xFF у payload —
#         пін фантомного бага (старий сервер тут давав 2.04)    → 608400FF
#   2.04  справжній batch-PUT: Брама ставить у чергу; SMOKE_UID
#         не-hex → ніколи не зіткнеться з flashed Queen, worker
#         гасить його як unknown_device без сліду в БД           → 604400FF
#
# Зонди ретраяться (UDP lossy) — кожен на свіжому сокеті, тож пізня
# відповідь попереднього зонда не переплутається з наступним. Логіку ганяє
# через реальний loopback-UDP spec/lib/coap_smoke_spec.rb; CLI-клей —
# bin/coap_smoke (workflow coap_smoke.yml). Канон: docs/03_02 §4.
module CoapSmoke
  SMOKE_UID = "SNET-Q-SMOKETEST"
  MAX_REPLY = 2048

  Probe = Struct.new(:name, :datagram, :expect_hex, keyword_init: true)

  # Мережеві коди «шлях не дав відповіді»: закритий порт на loopback віддає
  # ICMP port-unreachable, який ядро кладе на сокет як async-помилку — і
  # наступний recvfrom (після того, як IO.select показав сокет readable)
  # спливає Errno::ECONNREFUSED замість тиші. Для зонда це те саме, що
  # мовчання: ретрай і зрештою чесний «UDP-шлях мертвий», а не голий Errno.
  UNREACHABLE = [ Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::EHOSTUNREACH ].freeze

  module_function

  def probes
    pin_payload = "\xFF\x01\xFF".b
    [
      Probe.new(name: "RST на сміття в опціях",
                datagram: [ "4003ABCDF0" ].pack("H*"),
                expect_hex: "7000ABCD"),
      Probe.new(name: "4.04 на невідомий маршрут (пін 0xFF-MID фантомної доставки)",
                datagram: CoapClient.build_put(message_id: 0x00FF,
                                               path: "/smoke/freeze-contract",
                                               payload: pin_payload),
                expect_hex: "608400FF"),
      Probe.new(name: "2.04 після enqueue (batch-PUT #{SMOKE_UID})",
                datagram: CoapClient.build_put(message_id: 0x00FF,
                                               path: "/telemetry/batch/#{SMOKE_UID}",
                                               payload: pin_payload),
                expect_hex: "604400FF")
    ]
  end

  # Одна спроба: свіжий сокет → датаграма → відповідь або nil (тиша).
  # ECONNREFUSED/недосяжність трактуємо як тишу (див. UNREACHABLE) — інші
  # помилки сокета (напр. EMFILE при UDPSocket.new) спливають чесно.
  def shoot(host, port, datagram, timeout:)
    socket = UDPSocket.new
    socket.send(datagram, 0, host, port)
    reply, _sender = socket.recvfrom(MAX_REPLY) if IO.select([ socket ], nil, nil, timeout)
    reply
  rescue *UNREACHABLE
    nil
  ensure
    socket&.close
  end

  # true = всі зонди відповіли точними байтами; false — вердикт у io.
  def run(host:, port: 5683, timeout: 10.0, retries: 3, io: $stdout)
    probes.map { |probe| run_probe(probe, host, port, timeout, retries, io) }.all?
  end

  def run_probe(probe, host, port, timeout, retries, io)
    attempt = 0
    reply = nil
    while reply.nil? && attempt < retries
      attempt += 1
      reply = shoot(host, port, probe.datagram, timeout: timeout)
    end

    if reply.nil?
      io.puts "❌ #{probe.name}: тиша після #{retries} спроб по #{timeout}с — UDP-шлях мертвий"
      false
    elsif (got = reply.unpack1("H*").upcase) == probe.expect_hex
      io.puts "✅ #{probe.name}: #{got} (спроба #{attempt})"
      true
    else
      io.puts "❌ #{probe.name}: очікував #{probe.expect_hex}, прийшло #{got} — " \
              "wire-граматика Брами розійшлась із freeze-contract"
      false
    end
  end
end
