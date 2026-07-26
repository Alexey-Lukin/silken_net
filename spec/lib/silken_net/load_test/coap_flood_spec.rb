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

  # Авторитетний drop-лічильник на Linux-CI (staging = Linux) — pure-парсер /proc/net/snmp,
  # тестований прямо (на Darwin-хості kernel_udp_drops бере netstat-гілку, тож ця не виконалась би).
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
  end

  describe ".drops_delta" do
    it "returns nil when the before-count was unavailable (platform without a counter)" do
      expect(described_class.drops_delta(nil)).to be_nil
    end
  end
end
