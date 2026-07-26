# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.20 Rails-half + FW.60] Шов-тест deploy-тракту poll-ерою: HTTP deploy →
# Ota::DeploymentDispatcherService (pending_firmware_id-таргет) → Queen-poll
# крізь РЕАЛЬНИЙ CoapGate/CoapServerPdu → OTA-hint → stateless chunk-server →
# спостережене підтвердження доставки (fw= у наступному poll'і).
#
# Клас бага, який цей файл вбиває назавжди: «два зелені кінці, мертвий шов» —
# тут немає жодного мока derivation-ланцюга: PDU парситься реальним парсером,
# конверт шифрується реальним CoapEncryption, чанки — реальним
# OtaPackagerService (включно з FW.23 HMAC-трейлером). Мокнуто лише Turbo.
RSpec.describe "OTA deploy tract (FW.60 poll-ера)", type: :request do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }
  let(:cluster) { create(:cluster, organization: organization) }
  let!(:gateway) { create(:gateway, cluster: cluster, state: :idle) }
  let!(:key_record) { create(:hardware_key, device_uid: gateway.uid) }
  let!(:firmware) { create(:bio_contract_firmware, bytecode_payload: "AB" * 64) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    CoapGate::REPLY_CACHE.clear
    Rails.cache.clear
  end

  # Незалежний GET-білдер (не реюзить CoapServerPdu/CoapClient — спека мусить
  # ловити регресію нашого ж парсера чужими байтами, дзеркало coap_smoke).
  def coap_get(segments, query: nil, mid: 0x2211)
    pdu = [ 0x40, 0x01, mid ].pack("CCn") # ver=1 CON, code 0.01 GET, TKL=0
    option_number = 0
    emit = lambda do |number, value|
      delta = number - option_number
      option_number = number
      d_nib, d_ext = delta > 12 ? [ 13, [ delta - 13 ].pack("C") ] : [ delta, "" ]
      l_nib, l_ext = value.bytesize > 12 ? [ 13, [ value.bytesize - 13 ].pack("C") ] : [ value.bytesize, "" ]
      pdu << [ (d_nib << 4) | l_nib ].pack("C") << d_ext << l_ext << value
    end
    segments.each { |seg| emit.call(11, seg) }                    # Uri-Path
    Array(query).each { |pair| emit.call(15, pair) } if query     # Uri-Query: RFC — опція на пару
    pdu
  end

  # Розпаковка poll-відповіді: 2.05 → [IV:16][CBC] → strip [0x9C][ts:4] → inner.
  def unwrap(reply)
    expect(reply.getbyte(1)).to eq(0x45) # 2.05 Content
    marker = reply.index("\xFF".b)
    envelope = reply.byteslice(marker + 1, reply.bytesize)
    cipher = OpenSSL::Cipher.new("aes-256-cbc").decrypt
    cipher.key = key_record.binary_key
    cipher.iv = envelope.byteslice(0, 16)
    cipher.padding = 0
    plain = cipher.update(envelope.byteslice(16, envelope.bytesize)) + cipher.final
    expect(plain.getbyte(0)).to eq(0x9C) # time-sync конверт у КОЖНІЙ відповіді
    plain.byteslice(5, plain.bytesize)   # inner (+ zero-pad хвіст)
  end

  def poll(fw:, mid:)
    CoapGate.handle_datagram(
      data: coap_get([ "poll", gateway.uid ], query: "fw=#{fw}", mid: mid),
      gateway_ip: "10.0.0.9"
    )
  end

  def deploy!
    post "/api/v1/firmwares/#{firmware.id}/deploy",
         params: { cluster_id: cluster.id }, headers: headers, as: :json
  end

  def packages
    @packages ||= OtaPackagerService.prepare(
      firmware, chunk_size: OtaTransmissionWorker::CHUNK_SIZE, cluster_id: cluster.id
    )[:packages].to_a
  end

  def fetch_chunk(ch, mid: 0x2000 + ch)
    CoapGate.handle_datagram(
      data: coap_get([ "ota", gateway.uid ], query: [ "v=#{firmware.id}", "ch=#{ch}" ], mid: mid),
      gateway_ip: "10.0.0.9"
    )
  end

  it "deploy targets the gateway; first poll (fw=0, ребут) answers an OTA-hint and arms ARCH.59" do
    deploy!

    expect(response).to have_http_status(:accepted)
    expect(gateway.reload.pending_firmware_id).to eq(firmware.id)
    expect(cluster.reload.ota_version_hiwater).to eq(firmware.id)

    inner = unwrap(poll(fw: 0, mid: 0x1001))
    expect(inner.getbyte(0)).to eq(0x9F)
    expect(inner.byteslice(1, 6).unpack("Nn")).to eq([ firmware.id, packages.size ])
    expect(gateway.reload.state).to eq("updating")
    expect(gateway.ota_started_at).to be_present
  end

  it "chunk-server serves every package byte-identical to the real packager, 4.04 out of range" do
    deploy!
    poll(fw: 0, mid: 0x1001) # hint → updating

    # Prosopite-пауза: N однакових lookup'ів = N окремих датаграм-обробок
    # в одному спек-прикладі, не реальний N+1.
    begin
      Prosopite.pause if defined?(Prosopite)
      packages.each_with_index do |package, ch|
        fetched = unwrap(fetch_chunk(ch))
        expect(fetched.byteslice(0, package.bytesize)).to eq(package)
      end
      # ch поза межами → 4.04 (Queen перечитає hint, не отримає сміття)
      expect(fetch_chunk(packages.size, mid: 0x2FFF).getbyte(1)).to eq(0x84)
    ensure
      Prosopite.resume if defined?(Prosopite)
    end
  end

  it "observed confirmation: poll with fw=<id> retires the campaign and answers time-only" do
    deploy!
    poll(fw: 0, mid: 0x1001)

    inner = unwrap(poll(fw: firmware.id, mid: 0x1002))

    expect(inner.bytes).to all(eq(0)) # порожній inner = лише time-sync
    gateway.reload
    expect(gateway.pending_firmware_id).to be_nil
    expect(gateway.state).to eq("idle")
    expect(gateway.firmware_version).to eq(firmware.version)
  end

  it "answers a CON retransmit (same MID) with byte-identical reply without re-derivation" do
    post "/api/v1/firmwares/#{firmware.id}/deploy",
         params: { cluster_id: cluster.id }, headers: headers, as: :json

    first  = poll(fw: 0, mid: 0x3333)
    replay = poll(fw: 0, mid: 0x3333)

    expect(replay).to eq(first)
  end

  it "replaying the same campaign after completion is rejected by the hiwater guard" do
    post "/api/v1/firmwares/#{firmware.id}/deploy",
         params: { cluster_id: cluster.id }, headers: headers, as: :json
    poll(fw: 0, mid: 0x4001)               # hint → updating
    poll(fw: firmware.id, mid: 0x4002)     # зібрано → confirmed

    post "/api/v1/firmwares/#{firmware.id}/deploy",
         params: { cluster_id: cluster.id }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(gateway.reload.pending_firmware_id).to be_nil
  end
end
