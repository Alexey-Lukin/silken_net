# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.38] MAC над Queen-pull запитом. Golden-вектори — ті самі байти, що
# firmware/test/test_pull_mac.c: C-білдер і Rails-перевірка не можуть розійтись мовчки.
RSpec.describe Downlink::PullMac do
  let(:keyc) { (0..31).to_a.pack("C*") }

  it "matches the firmware golden vectors" do
    expect(described_class.hex(keyc: keyc, route: "poll", uid: "SNET-Q-00000001", mid: 4660,
                               raw_query: [ "fw=7", "cmd=0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0" ]))
      .to eq("4919db6f8e65d85e178ac31330b5f73f")
    expect(described_class.hex(keyc: keyc, route: "poll", uid: "SNET-Q-00000001", mid: 1, raw_query: [ "fw=0" ]))
      .to eq("be29f3cefc29a8a9550fce0089cdd998")
    expect(described_class.hex(keyc: keyc, route: "ota", uid: "SNET-Q-00000001", mid: 65_535,
                               raw_query: [ "v=12", "ch=3" ]))
      .to eq("84e60570ae08fb40967c76f9a90fefda")
  end

# [FW.60] Той самий вектор заморожено в firmware/test/test_pull_mac.c (Pull_Mac_Reply_Tag).
it "matches the firmware golden reply tag" do
  tag = described_class.reply_tag(keyc: keyc, m_hex: "4919db6f8e65d85e178ac31330b5f73f",
                                  envelope: (0..47).to_a.pack("C*"))
  expect(tag.unpack1("H*")).to eq("776e7562d30028766e3f56d255f0f11a")
end

  describe ".authentic?" do
    let(:gateway) { create(:gateway) }
    let!(:hardware_key) { create(:hardware_key, device_uid: gateway.uid, aes_key_hex: keyc.unpack1("H*").upcase) }

    def result_for(query, mid: 4660, status: :downlink_poll)
      request = CoapServerPdu::Request.new(message_id: mid, uri_query: query)
      CoapServerPdu::Intake.new(status: status, gateway_uid: gateway.uid, request: request, query: {})
    end

    def signed(query, key: keyc, mid: 4660, route: "poll")
      query + [ "m=#{described_class.hex(keyc: key, route: route, uid: gateway.uid, mid: mid, raw_query: query)}" ]
    end

    it "accepts the request the Queen signed, on both pull routes" do
      expect(described_class.authentic?(gateway: gateway, result: result_for(signed([ "fw=7" ])))).to be(true)
      ota = result_for(signed([ "v=12", "ch=3" ], route: "ota"), status: :ota_chunk_fetch)
      expect(described_class.authentic?(gateway: gateway, result: ota)).to be(true)
    end

    it "rejects a request without a MAC" do
      expect(described_class.authentic?(gateway: gateway, result: result_for([ "fw=7" ]))).to be(false)
    end

    # Сама атака SEC.38: той самий запит, але `fw=` підмінено.
    it "rejects a forged fw= under a MAC made for another value" do
      forged = signed([ "fw=0" ]).tap { _1[0] = "fw=999" }
      expect(described_class.authentic?(gateway: gateway, result: result_for(forged))).to be(false)
    end

    it "binds the route and the MID into the MAC" do
      expect(described_class.authentic?(gateway: gateway, result: result_for(signed([ "fw=7" ]), mid: 4661))).to be(false)
      as_ota = result_for(signed([ "v=12", "ch=3" ]), status: :ota_chunk_fetch)
      expect(described_class.authentic?(gateway: gateway, result: as_ota)).to be(false)
    end

    it "seals the reply with a tag bound to THIS request's m=" do
      query = signed([ "fw=7" ])
      sealed = described_class.seal_reply(gateway: gateway, result: result_for(query), envelope: "E" * 32)
      m_hex = query.last.delete_prefix("m=")

      expect(sealed.byteslice(0, 32)).to eq("E" * 32)
      expect(sealed.byteslice(32, 16)).to eq(described_class.reply_tag(keyc: keyc, m_hex: m_hex, envelope: "E" * 32))
      other = described_class.reply_tag(keyc: keyc, m_hex: signed([ "fw=8" ]).last.delete_prefix("m="), envelope: "E" * 32)
      expect(sealed.byteslice(32, 16)).not_to eq(other)
    end

    it "rejects everything when the gateway has no KEYC" do
      hardware_key.destroy!
      expect(described_class.authentic?(gateway: gateway.reload, result: result_for(signed([ "fw=7" ])))).to be(false)
    end

    # KEYC — той, що Королева тримає ЗАРАЗ: у Dual-Key Grace новий ключ ще не доїхав.
    it "verifies with the previous key while Dual-Key Grace is open" do
      previous = Array.new(32) { 0xA5 }.pack("C*")
      hardware_key.update!(previous_aes_key_hex: previous.unpack1("H*").upcase)
      gateway.reload

      expect(described_class.authentic?(gateway: gateway, result: result_for(signed([ "fw=7" ], key: previous)))).to be(true)
      expect(described_class.authentic?(gateway: gateway, result: result_for(signed([ "fw=7" ])))).to be(false)
    end
  end
end
