# frozen_string_literal: true

require "rails_helper"

# [FW.54 Вісь 2] Golden-вектори нижче ДОСЛІВНО заморожені у
# firmware/test/test_soldier_logic.c (test_did_golden_* / avalanche) — це
# крос-імпл freeze-contract did_derive.h ↔ DidDerivation. Зміна будь-якого
# байта мусить впасти ОБАБІЧ.
RSpec.describe SilkenNet::DidDerivation do
  describe ".did_from_uid_words — golden-parity з firmware Did_Derive_From_Uid" do
    it "g1: реалістичний WLE5 UID-триплет" do
      expect(described_class.did_from_uid_words(0x0039002F, 0x31385115, 0x38323634))
        .to eq(0x80B12004)
    end

    it "g2: дефектний UID все-нулі — детермінований і ненульовий" do
      did = described_class.did_from_uid_words(0, 0, 0)
      expect(did).to eq(0xC611B59B)
      expect(did).not_to be_zero
    end

    it "g3: все-FF (erased-flash патерн)" do
      expect(described_class.did_from_uid_words(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF))
        .to eq(0x8BA660CA)
    end

    it "g4: один біт UID → зовсім інший DID (avalanche)" do
      expect(described_class.did_from_uid_words(0x0039002E, 0x31385115, 0x38323634))
        .to eq(0xE203A561)
    end

    it "ніколи не нуль і детермінований на LCG-sweep (дзеркало C-sweep)" do
      lcg = 0x12345678
      1000.times do
        w0 = (lcg = (lcg * 1_664_525 + 1_013_904_223) & 0xFFFFFFFF)
        w1 = (lcg = (lcg * 1_664_525 + 1_013_904_223) & 0xFFFFFFFF)
        w2 = (lcg = (lcg * 1_664_525 + 1_013_904_223) & 0xFFFFFFFF)
        did = described_class.did_from_uid_words(w0, w1, w2)
        expect(did).not_to be_zero
        expect(described_class.did_from_uid_words(w0, w1, w2)).to eq(did)
      end
    end
  end

  describe ".wire_did" do
    it "формує канонічний trees.did: SNET-XXXXXXXX" do
      expect(described_class.wire_did(0x0039002F, 0x31385115, 0x38323634))
        .to eq("SNET-80B12004")
    end
  end
end
