# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "coap_client"
require "coap_smoke"

# [ARCH.81] Доти стан «інтейк живий» не спостерігався в сюїті НІКОДИ інакше, ніж
# через підроблений `TCPSocket` — бо проба відкривала TCP на UDP-порт і `false`
# був у ній конструкцією, а не вимірюванням. Тут кожен із чотирьох станів
# доводиться реальним loopback-UDP, тим самим шляхом, яким ходить Королева.
RSpec.describe SilkenNet::HealthProbes do
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

  def with_coap_env(host:, port: CoapSmoke::DEFAULT_PORT)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("COAP_HOST").and_return(host)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("COAP_PORT", CoapSmoke::DEFAULT_PORT).and_return(port)
  end

  describe ".coap_listener" do
    it "звітує alive, коли Брама відповіла байтами freeze-contract" do
      honest = ->(data) { CoapServerPdu.handle_telemetry_datagram(data).reply }

      with_loopback_server(honest) do |port|
        with_coap_env(host: "127.0.0.1", port: port)

        expect(described_class.coap_listener(timeout: 2.0))
          .to include(status: "alive", host: "127.0.0.1", port: port)
      end
    end

    # «Порт відкритий» для connectionless-сокета не доводить нічого: відповісти
    # може будь-хто. Розрізняє саме байт-точна звірка.
    it "звітує wire_mismatch, коли на порту відповідає хтось інший" do
      impostor = ->(_data) { "definitely-not-coap".b }

      with_loopback_server(impostor) do |port|
        with_coap_env(host: "127.0.0.1", port: port)

        expect(described_class.coap_listener(timeout: 2.0)[:status]).to eq("wire_mismatch")
      end
    end

    it "звітує unreachable, коли на адресі мовчать" do
      # Порт, звільнений одразу після біндингу: ядро віддає ICMP
      # port-unreachable, тож вердикт приходить із мережі, а не з конструкції.
      throwaway = UDPSocket.new
      throwaway.bind("127.0.0.1", 0)
      dead_port = throwaway.addr[1]
      throwaway.close

      with_coap_env(host: "127.0.0.1", port: dead_port)

      expect(described_class.coap_listener(timeout: 1.0)[:status]).to eq("unreachable")
    end

    # Несуче розрізнення пункту: мовчазний дефолт на loopback зробив би ці два
    # стани невідрізнимими — і саме він тримав панель вічно червоною.
    it "звітує not_configured, а не unreachable, коли адреси немає" do
      with_coap_env(host: nil)

      result = described_class.coap_listener
      expect(result[:status]).to eq("not_configured")
      expect(result).not_to have_key(:host)
    end

    it "не пропускає сирий текст винятку назовні" do
      with_coap_env(host: "127.0.0.1")
      allow(CoapSmoke).to receive(:shoot).and_raise(StandardError, "socket internals")

      result = described_class.coap_listener
      expect(result[:status]).to eq("check_failed")
      expect(result.to_s).not_to include("socket internals")
    end
  end

  describe ".database_reachable?" do
    it "робить раунд-тріп, а не питає обʼєкт зʼєднання про нього самого" do
      allow(ActiveRecord::Base.connection).to receive(:execute).with("SELECT 1").and_call_original

      expect(described_class.database_reachable?).to be(true)
      expect(ActiveRecord::Base.connection).to have_received(:execute).with("SELECT 1")
    end

    it "віддає false, коли база не відповідає" do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(StandardError, "gone")

      expect(described_class.database_reachable?).to be(false)
    end
  end

  describe ".redis_reachable?" do
    it "вимагає PONG від ОБОХ баз — черг Sidekiq і Kredis" do
      allow(Kredis).to receive(:redis).and_raise(StandardError, "kredis down")

      expect(described_class.redis_reachable?).to be(false)
    end
  end
end
