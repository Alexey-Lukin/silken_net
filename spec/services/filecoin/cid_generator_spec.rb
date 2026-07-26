# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Filecoin::CidGenerator do
  describe ".cidv1" do
    # Golden-вектори: збігаються з `ipfs add --raw-leaves --cid-version 1`
    # (raw codec 0x55 + sha2-256). Це зовнішня правда, не self-check.
    it "matches the canonical empty-content CIDv1 (raw + sha2-256)" do
      expect(described_class.cidv1("")).to eq(
        "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
      )
    end

    it "matches the canonical CIDv1 of 'hello'" do
      expect(described_class.cidv1("hello")).to eq(
        "bafkreibm6jg3ux5qumhcn2b3flc3tyu6dmlb4xa7u5bf44yegnrjhc4yeq"
      )
    end

    it "emits a base32 multibase 'b' string with the raw+sha256 'bafkrei' prefix" do
      cid = described_class.cidv1("silkennet")
      expect(cid).to start_with("bafkrei")
      expect(cid.length).to eq(59)
      expect(cid).to match(/\Ab[a-z2-7]+\z/) # multibase 'b' + RFC4648 base32 lower
    end

    it "is deterministic for identical bytes" do
      first  = described_class.cidv1("payload")
      second = described_class.cidv1("payload")
      expect(first).to eq(second)
    end

    it "is collision-sensitive: different bytes → different CID" do
      expect(described_class.cidv1("a")).not_to eq(described_class.cidv1("b"))
    end

    it "round-trips: decoded multihash digest equals SHA-256 of the input" do
      cid = described_class.cidv1("witness")
      rev = "abcdefghijklmnopqrstuvwxyz234567".each_char.with_index.to_h
      bits = cid[1..].chars.map { |c| rev[c].to_s(2).rjust(5, "0") }.join
      bytes = bits[0...(bits.length / 8 * 8)].chars.each_slice(8).map { |g| g.join.to_i(2) }
      expect(bytes[0, 4]).to eq([ 0x01, 0x55, 0x12, 0x20 ]) # v1 ‖ raw ‖ sha2-256 ‖ len32
      digest_hex = bytes[4, 32].map { |b| format("%02x", b) }.join
      expect(digest_hex).to eq(Digest::SHA256.hexdigest("witness"))
    end

    context "with a Hash/Array payload (canonical JSON)" do
      it "is independent of key insertion order" do
        a = described_class.cidv1(z: 1, a: 2, m: { y: 9, x: 8 })
        b = described_class.cidv1(a: 2, m: { x: 8, y: 9 }, z: 1)
        expect(a).to eq(b)
      end

      it "equals the CID of its own canonical_json string form" do
        payload = { device_uid: "SNET-1", z_value: 23.45 }
        expect(described_class.cidv1(payload)).to eq(
          described_class.cidv1(described_class.canonical_json(payload))
        )
      end
    end
  end

  describe ".canonical_json" do
    it "recursively sorts keys and emits compact JSON" do
      expect(described_class.canonical_json(b: 1, a: { d: 4, c: 3 })).to eq(
        '{"a":{"c":3,"d":4},"b":1}'
      )
    end

    it "preserves array element order (only keys are sorted)" do
      expect(described_class.canonical_json(items: [ 3, 1, 2 ])).to eq('{"items":[3,1,2]}')
    end
  end
end
