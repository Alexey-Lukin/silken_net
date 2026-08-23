# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "coap_client"

# [FW.56 e2e] Грамматична парність C-білдер ↔ Rails-парсер: golden-вектори
# нижче ДОСЛІВНО заморожені у firmware/test/test_at_engine.c
# (test_coap_build_golden_layout / test_coap_build_golden_mid_ff) — це
# крос-імпл freeze-contract. Зміна будь-якого байта мусить впасти ОБАБІЧ.
RSpec.describe CoapServerPdu do
  # Coap_Build_Put(MID=0xBEEF, /telemetry/batch/SNET-Q-AABBCCDD, [DE AD])
  let(:golden_put_hex) do
    "4003BEEF" \
      "B974656C656D65747279" \
      "056261746368" \
      "0D02534E45542D512D4141424243434444" \
      "FF" \
      "DEAD"
  end

  # Пін-кейс бага Брами: 0xFF у MID (coap_mid++ → кожен 256-й flush) і в
  # payload. Старий data.index("\xFF") знаходив маркер у заголовку → батч
  # падав «невідомим маршрутом» ПІСЛЯ відправленого ACK 2.04 → Королева
  # чистила CIFO (FW.51) → тиха втрата години телеметрії.
  let(:golden_mid_ff_hex) do
    "400300FF" \
      "B974656C656D65747279" \
      "056261746368" \
      "0D02534E45542D512D3030464630304646" \
      "FF" \
      "FF01FF"
  end

  def bin(hex) = [ hex ].pack("H*")

  describe "golden-parity з firmware Coap_Build_Put" do
    it "парсить golden PDU C-білдера (MID=0xBEEF)" do
      request = described_class.parse_request(bin(golden_put_hex))

      expect(request.version).to eq(1)
      expect(request.type).to eq(described_class::TYPE_CON)
      expect(request.code).to eq(described_class::CODE_PUT)
      expect(request.message_id).to eq(0xBEEF)
      expect(request.uri_path).to eq([ "telemetry", "batch", "SNET-Q-AABBCCDD" ])
      expect(request.payload).to eq("\xDE\xAD".b)
    end

    it "парсить PDU з 0xFF у MID та payload (регресія data.index маркера)" do
      request = described_class.parse_request(bin(golden_mid_ff_hex))

      expect(request.message_id).to eq(0x00FF)
      expect(request.uri_path).to eq([ "telemetry", "batch", "SNET-Q-00FF00FF" ])
      expect(request.payload).to eq("\xFF\x01\xFF".b)
    end

    it "CoapClient.build_put емітить байт-у-байт той самий wire, що C-білдер" do
      packet = CoapClient.build_put(
        message_id: 0xBEEF,
        path: "/telemetry/batch/SNET-Q-AABBCCDD",
        payload: "\xDE\xAD".b
      )

      expect(packet.unpack1("H*").upcase).to eq(golden_put_hex)
    end
  end

  describe ".handle_telemetry_datagram" do
    it "приймає батч і відповідає ACK 2.04, який Coap_Reply_Confirms зарахує" do
      result = described_class.handle_telemetry_datagram(bin(golden_mid_ff_hex))

      expect(result.status).to eq(:telemetry_batch)
      expect(result.gateway_uid).to eq("SNET-Q-00FF00FF")
      expect(result.payload).to eq("\xFF\x01\xFF".b)
      # Рівно ці байти test_at_engine.c згодовує Coap_Reply_Confirms → 1.
      expect(result.reply.unpack1("H*").upcase).to eq("604400FF")
    end

    it "[SEC.21] приймає device/event маршрут як окремий статус" do
      # L1-конверт [ver:1][ts:4][count:1][record:7][sig:64] = 77B (роутинг
      # payload-агностичний; DeviceEventWorker верифікує підпис далі).
      pdu = CoapClient.build_put(message_id: 0x1357,
                                 path: "/device/event/SNET-Q-00FF00FF",
                                 payload: "\x01".b * 77)
      result = described_class.handle_telemetry_datagram(pdu)

      expect(result.status).to eq(:device_event)
      expect(result.gateway_uid).to eq("SNET-Q-00FF00FF")
      expect(result.payload.bytesize).to eq(77)
      # 2.04 CHANGED — той самий доставку-код, що телеметрія (клас 2.xx).
      expect(result.reply.unpack1("H*").upcase).to eq("60441357")
    end

    it "відповідає 4.04 на невідомий маршрут — Королева тримає кеш і повторить" do
      pdu = CoapClient.build_put(message_id: 0x1234, path: "/firmware/upload",
                                 payload: "x".b)
      result = described_class.handle_telemetry_datagram(pdu)

      expect(result.status).to eq(:unknown_route)
      # Клас 4.xx → firmware test_coap_reply_rejects: НЕ доставка.
      expect(result.reply.unpack1("H*").upcase).to eq("60841234")
    end

    it "відповідає 4.04 на /telemetry/batch без payload" do
      pdu = bin(golden_put_hex).byteslice(0, bin(golden_put_hex).bytesize - 3)
      result = described_class.handle_telemetry_datagram(pdu)

      expect(result.status).to eq(:unknown_route)
      expect(result.reply.unpack1("H*").upcase).to eq("6084BEEF")
    end

    it "відповідає 4.04 на не-PUT код" do
      get_pdu = bin(golden_put_hex)
      get_pdu.setbyte(1, 0x01) # GET
      result = described_class.handle_telemetry_datagram(get_pdu)

      expect(result.status).to eq(:unknown_route)
    end

    it "мовчить на NON-запит (piggyback лише для CON)" do
      non_pdu = bin(golden_put_hex)
      non_pdu.setbyte(0, 0x50) # ver=1, type=NON, TKL=0
      result = described_class.handle_telemetry_datagram(non_pdu)

      expect(result.status).to eq(:telemetry_batch)
      expect(result.reply).to be_nil
    end

    it "шле RST на читабельний заголовок зі сміттям в опціях" do
      garbage = bin("4003ABCD") + "\xF0".b # delta-нібл 15 — reserved
      result = described_class.handle_telemetry_datagram(garbage)

      expect(result.status).to eq(:malformed)
      # type=RST → firmware Coap_Reply_Confirms поверне 0 (кеш живий).
      expect(result.reply.unpack1("H*").upcase).to eq("7000ABCD")
    end

    it "мовчить на датаграм, коротший за CoAP-заголовок" do
      result = described_class.handle_telemetry_datagram("\x40\x03".b)

      expect(result.status).to eq(:malformed)
      expect(result.reply).to be_nil
    end
  end

  describe ".parse_request — межі формату (RFC 7252 §3)" do
    it "відкидає версію ≠ 1" do
      expect(described_class.parse_request(bin("8003BEEF"))).to be_nil
    end

    it "відкидає зарезервований TKL > 8" do
      expect(described_class.parse_request(bin("4903BEEF"))).to be_nil
    end

    it "відкидає маркер payload без самого payload" do
      expect(described_class.parse_request(bin("4003BEEFFF"))).to be_nil
    end

    it "відкидає обірваний ext-байт довжини опції" do
      # len-нібл 13 обіцяє ext-байт, якого нема
      expect(described_class.parse_request(bin("4003BEEF0D"))).to be_nil
    end

    it "відкидає опцію, що обіцяє більше байтів, ніж є в датаграмі" do
      expect(described_class.parse_request(bin("4003BEEFB9AA"))).to be_nil
    end

    it "відкидає PDU, де заявлений TKL перевищує розмір датаграми (обірваний токен)" do
      # ver=1, type=CON, tkl=5 (0x45) — але датаграма закінчується рівно на
      # 4-байтовому заголовку, самих 5 байтів токена в датаграмі нема.
      expect(described_class.parse_request(bin("4503BEEF"))).to be_nil
    end

    it "відкидає обірваний 2-байтовий ext (нібл 14) delta/length опції" do
      # Опційний байт 0xE0: delta-нібл 14 обіцяє 2 ext-БЕ-байти, яких нема
      # (датаграма закінчується рівно на самому опційному байті).
      expect(described_class.parse_request(bin("4003BEEFE0"))).to be_nil
    end

    it "луною повертає токен у ACK (TKL > 0)" do
      pdu = bin("42031111") + "\xAB\xCD".b + bin(golden_put_hex)[4..]
      request = described_class.parse_request(pdu)

      expect(request.token).to eq("\xAB\xCD".b)
      ack = described_class.build_ack(request, code: described_class::CODE_CHANGED)
      expect(ack.unpack1("H*").upcase).to eq("62441111ABCD")
    end

    it "читає 2-байтовий ext (нібл 14) для довгих опцій" do
      value = "a" * 300
      option = [ (11 << 4) | 14, value.bytesize - 269 ].pack("Cn") + value
      request = described_class.parse_request(bin("40031234") + option)

      expect(request.uri_path).to eq([ value ])
    end

    it "ігнорує опції поза Uri-Path (номер ≠ 11 — значення не пушиться, запит валідний)" do
      # Опційний байт 0x10: delta=1 (option 1, If-Match), length=0 — валідна
      # опція, яку сервер не розуміє й свідомо пропускає (не лише Uri-Path).
      request = described_class.parse_request(bin("4003123410"))

      expect(request).not_to be_nil
      expect(request.uri_path).to eq([])
    end
  end

  # [FW.60] Downlink-poll маршрути + 2.05-білдер
  describe "downlink poll routing (FW.60)" do
    def get_pdu(segments, query: [], mid: 0x1234)
      pdu = [ 0x40, 0x01, mid ].pack("CCn")
      number = 0
      (segments.map { |s| [ 11, s ] } + query.map { |q| [ 15, q ] }).each do |(opt, value)|
        delta = opt - number
        number = opt
        d_nib, d_ext = delta > 12 ? [ 13, [ delta - 13 ].pack("C") ] : [ delta, "" ]
        l_nib, l_ext = value.bytesize > 12 ? [ 13, [ value.bytesize - 13 ].pack("C") ] : [ value.bytesize, "" ]
        pdu << [ (d_nib << 4) | l_nib ].pack("C") << d_ext << l_ext << value
      end
      pdu
    end

    it "GET poll/<uid> → :downlink_poll з request і розібраним query" do
      intake = described_class.handle_telemetry_datagram(
        get_pdu(%w[poll SNET-Q-00000001], query: [ "fw=42" ])
      )

      expect(intake.status).to eq(:downlink_poll)
      expect(intake.gateway_uid).to eq("SNET-Q-00000001")
      expect(intake.query).to eq({ "fw" => "42" })
      expect(intake.reply).to be_nil # 2.05 будує CoapGate після derivation
      expect(intake.request.message_id).to eq(0x1234)
    end

    it "GET ota/<uid> → :ota_chunk_fetch; &-склейка в одній опції теж розкладається" do
      intake = described_class.handle_telemetry_datagram(
        get_pdu(%w[ota SNET-Q-00000001], query: [ "v=7&ch=3" ])
      )

      expect(intake.status).to eq(:ota_chunk_fetch)
      expect(intake.query).to eq({ "v" => "7", "ch" => "3" })
    end


    it "parses the frozen C-builder GET golden byte-for-byte (firmware Coap_Build_Get)" do
      # [FW.60 freeze-contract] Той самий hex заморожено у
      # firmware/test/test_at_engine.c (test_fw60_coap_build_get_golden).
      golden_get_hex = "40011234" \
                       "B4706F6C6C" \
                       "0D02534E45542D512D3030303030303031" \
                       "4566773D3432"
      intake = described_class.handle_telemetry_datagram([ golden_get_hex ].pack("H*"))

      expect(intake.status).to eq(:downlink_poll)
      expect(intake.gateway_uid).to eq("SNET-Q-00000001")
      expect(intake.query).to eq({ "fw" => "42" })
      expect(intake.request.message_id).to eq(0x1234)
    end

    it "PUT на poll-шлях НЕ матчить downlink-маршрут (4.04)" do
      put_pdu = get_pdu(%w[poll SNET-Q-00000001])
      put_pdu.setbyte(1, 0x03) # code → PUT

      intake = described_class.handle_telemetry_datagram(put_pdu)

      expect(intake.status).to eq(:unknown_route)
    end

    it "build_content: 2.05 piggyback ACK + 0xFF + payload (те, що Coap_Reply_Confirms зарахує)" do
      request = described_class.parse_request(get_pdu(%w[poll X], mid: 0xBEEF))

      reply = described_class.build_content(request, payload: "\x01\x02".b)

      expect(reply.bytes.first(4)).to eq([ 0x60, 0x45, 0xBE, 0xEF ])
      expect(reply.byteslice(4, 3)).to eq("\xFF\x01\x02".b)
    end
  end
end
