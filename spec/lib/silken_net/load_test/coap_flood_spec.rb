# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::LoadTest::CoapFlood do
  # loopback UDP-sink рахує датаграми (house-style with_loopback_server).
  def with_udp_sink
    server = UDPSocket.new
    server.bind("127.0.0.1", 0)
    port  = server.addr[1]
    count = Concurrent::AtomicFixnum.new(0)
    thread = Thread.new do
      loop do
        server.recvfrom(2048)
        count.increment
      end
    end
    yield port, count
  ensure
    thread&.kill
    server&.close
  end

  it "pre-generує валідні CoAP-датаграми з монотонним MID" do
    datagrams = described_class.pregenerate("SNET-Q-DEADBEEF", 100)
    expect(datagrams.size).to eq(described_class::POOL_SIZE)

    request = CoapServerPdu.parse_request(datagrams.first)
    expect(request.uri_path).to eq([ "telemetry", "batch", "SNET-Q-DEADBEEF" ])
    expect(request.message_id).to eq(1) # монотонний старт
    expect(CoapServerPdu.parse_request(datagrams[9]).message_id).to eq(10)
  end

  it "флудить listener і звітує offered окремо від achieved" do
    with_udp_sink do |port, count|
      report = described_class.run(
        host: "127.0.0.1", port: port, gateway_uid: "SNET-Q-DEADBEEF",
        offered_rps: 400, duration_s: 0.3, workers: 2
      )

      expect(report[:sent]).to be > 0
      expect(report[:achieved_rps]).to be > 0
      expect(report[:offered_rps]).to eq(400)
      expect(report[:workers]).to eq(2)

      sleep 0.1 # дати sink дочитати
      expect(count.value).to be > 0
    end
  end

  # [INF.23] Пейсер НЕ спить, коли вже відстає: інакше `achieved_rps` тихо
  # занижував би генератор, і гарнес брехав би саме про те, заради чого існує —
  # яка зі сторін вузьке місце. Темп задано свідомо недосяжним (інтервал коротший
  # за один syscall), тож гілка «slack не додатний» береться за побудовою.
  it "не приховує sender-stall: недосяжний темп дає achieved нижче offered" do
    with_udp_sink do |port, _count|
      report = described_class.run(
        host: "127.0.0.1", port: port, gateway_uid: "SNET-Q-DEADBEEF",
        offered_rps: 200_000, duration_s: 0.05, workers: 1
      )

      expect(report[:achieved_rps]).to be < report[:offered_rps]
      expect(report[:sent]).to be > 0
    end
  end

  it "відмовляє на непозитивному offered_rps, а не дає ділення на нуль" do
    expect { described_class.run(host: "127.0.0.1", gateway_uid: "SNET-Q-DEADBEEF", offered_rps: 0, duration_s: 0.01) }
      .to raise_error(ArgumentError, /offered_rps/)
  end

  # Авторитетний drop-лічильник на Linux-CI (staging = Linux) — pure-парсер /proc/net/snmp.
  describe ".parse_linux_udp_rcvbuf_errors" do
    it "extracts the RcvbufErrors column from a /proc/net/snmp Udp block" do
      snmp = <<~SNMP
        Udp: InDatagrams NoPorts InErrors OutDatagrams RcvbufErrors SndbufErrors InCsumErrors
        Udp: 100000 5 0 90000 4242 0 0
      SNMP
      expect(described_class.parse_linux_udp_rcvbuf_errors(snmp)).to eq(4242)
    end

    it "returns nil for nil or a block without the Udp counters" do
      expect(described_class.parse_linux_udp_rcvbuf_errors(nil)).to be_nil
      expect(described_class.parse_linux_udp_rcvbuf_errors("Tcp: 1 2 3\n")).to be_nil
    end

    it "returns nil for a Udp block that has counters but no RcvbufErrors column" do
      snmp = "Udp: InDatagrams NoPorts\nUdp: 7 1\n"
      expect(described_class.parse_linux_udp_rcvbuf_errors(snmp)).to be_nil
    end
  end

  # [TEST.9] Платформний DISPATCH пінується HOST-INDEPENDENT — і це не гігієна, а
  # причина того, що метрика покриття була недетермінованою між платформами:
  # непокрита гілка тут — це гілка, НЕДОСЯЖНА на хості, що міряє, тож Linux-CI і
  # macOS давали різні числа на однаковому коді й білд червонів на 0.01% при нулі
  # падінь. Стабуючи `host_os`, обидві половини виконуються всюди — розбіжність
  # зникає в КОРЕНІ, а не ховається виведенням файлу зі скоупу SimpleCov (той
  # фільтр ширший за проблему: разом із нею він зняв би нагляд і з INF.23
  # honesty-детекторів, які канон тримає в скоупі свідомо — `04_06 §B.1.3`).
  # Заразом це перший пін на darwin-регекс: доти жоден тест не тримав фразу
  # netstat, тобто «авторитетний лічильник» міг тихо осліпнути на nil.
  describe ".kernel_udp_drops" do
    def stub_host_os(value)
      allow(RbConfig::CONFIG).to receive(:[]).and_call_original
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return(value)
    end

    it "reads the netstat buffer-drop counter on darwin" do
      stub_host_os("darwin24")
      allow(described_class).to receive(:`).and_return("\t3210 dropped due to full socket buffers\n")

      expect(described_class.kernel_udp_drops).to eq(3210)
    end

    it "returns nil on darwin when netstat does not report that counter" do
      stub_host_os("darwin24")
      allow(described_class).to receive(:`).and_return("udp:\n\t42 datagrams received\n")

      expect(described_class.kernel_udp_drops).to be_nil
    end

    it "reads RcvbufErrors from /proc/net/snmp on linux" do
      stub_host_os("linux-gnu")
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("/proc/net/snmp")
                                   .and_return("Udp: InDatagrams RcvbufErrors\nUdp: 100 99\n")

      expect(described_class.kernel_udp_drops).to eq(99)
    end

    it "returns nil on a platform with no known counter" do
      stub_host_os("mswin64")

      expect(described_class.kernel_udp_drops).to be_nil
    end
  end

  describe ".drops_delta" do
    it "returns nil when the before-count was unavailable (platform without a counter)" do
      expect(described_class.drops_delta(nil)).to be_nil
    end
  end
end
