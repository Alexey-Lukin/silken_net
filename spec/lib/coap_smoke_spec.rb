# frozen_string_literal: true

require "rails_helper"
require "coap_client"
require "coap_smoke"

# [FW.56/INF.6] Smoke-зонди доводяться через РЕАЛЬНИЙ loopback-UDP: сервер
# нижче — той самий вердикт CoapServerPdu + send-семантика демона
# (lib/daemons/coap_listener = recvfrom → вердикт → reply, якщо є). Регресія
# фантомної доставки пінується legacy-сервером, що ACK'ає до парсингу.
RSpec.describe CoapSmoke do
  def with_loopback_server(handler)
    server = UDPSocket.new
    server.bind("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      loop do
        data, sender = server.recvfrom(2048)
        reply = handler.call(data)
        server.send(reply, 0, sender[3], sender[1]) if reply
      end
    end
    yield port
  ensure
    thread&.kill
    server&.close
  end

  let(:io) { StringIO.new }

  it "проти чесної Брами всі три зонди зелені (точні байти freeze-contract)" do
    honest = ->(data) { CoapServerPdu.handle_telemetry_datagram(data).reply }

    with_loopback_server(honest) do |port|
      expect(described_class.run(host: "127.0.0.1", port: port,
                                 timeout: 2.0, retries: 2, io: io)).to be(true)
    end

    expect(io.string.scan("✅").size).to eq(3)
    expect(io.string).to include("7000ABCD", "608400FF", "604400FF")
  end

  it "валить legacy-сервер фантомної доставки (ACK 2.04 до парсингу — всім)" do
    phantom = ->(data) { ("\x60\x44".b + data.byteslice(2, 2)) if data.bytesize >= 4 }

    with_loopback_server(phantom) do |port|
      expect(described_class.run(host: "127.0.0.1", port: port,
                                 timeout: 2.0, retries: 1, io: io)).to be(false)
    end

    # Фантом «доставив» сміття і невідомий маршрут — рівно ті зонди й валяться.
    expect(io.string).to include("очікував 7000ABCD, прийшло 6044ABCD")
    expect(io.string).to include("очікував 608400FF, прийшло 604400FF")
  end

  it "тиша (порт без Брами) = чесний фейл, не вічне очікування" do
    throwaway = UDPSocket.new
    throwaway.bind("127.0.0.1", 0)
    dead_port = throwaway.addr[1]
    throwaway.close

    expect(described_class.run(host: "127.0.0.1", port: dead_port,
                               timeout: 0.2, retries: 1, io: io)).to be(false)
    expect(io.string).to include("тиша", "UDP-шлях мертвий")
  end

  it "зонд 2.04 несе SMOKE_UID, який worker гасить як unknown_device" do
    batch = described_class.probes.last
    request = CoapServerPdu.parse_request(batch.datagram)

    expect(request.uri_path).to eq([ "telemetry", "batch", described_class::SMOKE_UID ])
    # не-hex суфікс → ніколи не збіжиться з flashed Queen ("SNET-Q-[8 HEX]")
    expect(described_class::SMOKE_UID).not_to match(/\ASNET-Q-\h{8}\z/)
  end

  it ".shoot пропускає оригінальну помилку сокета, а не NoMethodError на nil-сокеті" do
    # UDPSocket.new падає ДО присвоєння — ensure все одно виконується
    # (method-level ensure огортає весь shoot, включно з самим new). Guard
    # `socket&.close` захищає рівно цей кейс: без нього тут була б замаскована
    # NoMethodError замість справжньої мережевої помилки.
    allow(UDPSocket).to receive(:new).and_raise(Errno::EMFILE.new("too many open files"))

    expect {
      described_class.shoot("127.0.0.1", 5683, "x".b, timeout: 0.1)
    }.to raise_error(Errno::EMFILE)
  end

  it "трактує ECONNREFUSED як тишу — closed-port ICMP не спливає голим Errno" do
    # [TEST.6] Закритий loopback-порт віддає ICMP port-unreachable: IO.select
    # бачить сокет readable, а recvfrom кидає ECONNREFUSED. Без rescue воно
    # спливало б крізь run_probe і валило зонд замість чесного «тиша». macOS
    # цей ICMP на non-connected UDP не доставляє — тому flake був лише в CI.
    socket = instance_double(UDPSocket, send: nil, close: nil)
    allow(UDPSocket).to receive(:new).and_return(socket)
    allow(IO).to receive(:select).and_return([ [ socket ], [], [] ])
    allow(socket).to receive(:recvfrom).and_raise(Errno::ECONNREFUSED)

    expect(described_class.shoot("127.0.0.1", 5683, "x".b, timeout: 0.1)).to be_nil
  end
end
