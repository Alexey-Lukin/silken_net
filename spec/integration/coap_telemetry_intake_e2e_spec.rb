# frozen_string_literal: true

require "rails_helper"
require "coap_client"

# [FW.56 e2e] Queen-PDU ↔ Rails CoAP-intake: доводимо граматику end-to-end
# софтом. PDU будується wire-дзеркалом firmware Coap_Build_Put
# (golden-parity: spec/lib/coap_server_pdu_spec.rb ↔ test_at_engine.c),
# проходить вердикт Брами (CoapServerPdu = pure-ядро lib/daemons/coap_listener)
# і РЕАЛЬНИЙ конвеєр UnpackTelemetryWorker → AES-256-CBC decrypt →
# TelemetryUnpackerService → route_queen_health. MID = 0x00FF навмисно:
# пін-кейс бага старого парсера (data.index маркера ловив 0xFF у заголовку).
RSpec.describe "CoAP intake e2e: Queen PDU grammar → Rails pipeline", type: :integration do
  let(:cluster)    { create(:cluster) }
  let(:gateway)    { create(:gateway, cluster: cluster, ip_address: "10.7.0.7") }
  let(:key_record) { create(:hardware_key, device_uid: gateway.uid) }

  # Queen-Sentinel батч (DID=0, RSSI=0 — локальний; 03_02 §4.4): канонічний
  # wire-білдер TelemetryChunkHelper (auto-include за *telemetry*-шляхом).
  let(:sentinel_chunk) { build_chunk("00000000", 0, 4_100, 25, 22, 3_600, 7, 0) }

  # AES-256-CBC конверт Королеви: [IV:16][ct], zero-padding до блоку —
  # точний flush-формат firmware (03_02 §3).
  let(:encrypted_batch) do
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = key_record.binary_key
    iv = cipher.random_iv
    cipher.padding = 0

    pad = (16 - (sentinel_chunk.bytesize % 16)) % 16
    iv + cipher.update(sentinel_chunk + ("\x00".b * pad)) + cipher.final
  end

  before do
    key_record
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(ActionCable.server).to receive(:broadcast)
  end

  it "проводить батч від байтів C-граматики до GatewayTelemetryWorker" do
    pdu = CoapClient.build_put(
      message_id: 0x00FF,
      path: "/telemetry/batch/#{gateway.uid}",
      payload: encrypted_batch
    )

    # 1. Брама: парсинг + маршрутизація (те, що демон робить між recvfrom
    #    і perform_async) — payload мусить пережити wire байт-у-байт.
    result = CoapServerPdu.handle_telemetry_datagram(pdu)

    expect(result.status).to eq(:telemetry_batch)
    expect(result.gateway_uid).to eq(gateway.uid)
    expect(result.payload).to eq(encrypted_batch)

    # 2. ACK 2.04 з нашим MID — рівно ті байти, що firmware
    #    Coap_Reply_Confirms зараховує як доставку (test_at_engine.c:
    #    "604400FF") і лише після яких Королева чистить CIFO (FW.51).
    expect(result.reply.unpack1("H*").upcase).to eq("604400FF")

    # 3. Реальний конвеєр: decrypt → unpack → sentinel-маршрут.
    worker_args = [ Base64.strict_encode64(result.payload),
                    "10.7.0.7", result.gateway_uid ]
    expect do
      UnpackTelemetryWorker.new.perform(*worker_args)
    end.to change { GatewayTelemetryWorker.jobs.size }.by(1)

    job_args = GatewayTelemetryWorker.jobs.last["args"]
    expect(job_args[0]).to eq(gateway.uid)
    expect(job_args[1]).to include(
      "voltage_mv" => 4_100, "temperature_c" => 25, "cellular_signal_csq" => 22
    )
  end

  it "не пускає в конвеєр сміття: RST замість ACK → Королева тримає кеш" do
    truncated = CoapClient.build_put(
      message_id: 0x00FF,
      path: "/telemetry/batch/#{gateway.uid}",
      payload: encrypted_batch
    ).byteslice(0, 6) # обірваний посеред опційного заголовка

    result = CoapServerPdu.handle_telemetry_datagram(truncated)

    expect(result.status).to eq(:malformed)
    expect(result.reply.getbyte(0) >> 4 & 0x03).to eq(CoapServerPdu::TYPE_RST)
  end
end
