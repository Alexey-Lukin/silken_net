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

    it "мапить нульовий сирий DID у SEED (guard: DID ніколи не 0 — резерв Королеви-Сентінель)" do
      # Сконструйований UID, де фінальний mix32-вхід = 0 (mix32(0)=0) → сирий DID = 0:
      # w2 = h_prev, тож h_prev ^ w2 = 0. Guard мусить повернути SEED, дзеркало firmware.
      h_after_w0 = described_class.mix32(described_class::SEED ^ 0)
      h_prev     = described_class.mix32(h_after_w0 ^ 0)
      expect(described_class.did_from_uid_words(0, 0, h_prev)).to eq(described_class::SEED)
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

  describe ".uid_words / .wire_did_from_uid_hex — канонічний 24-hex UID-рядок" do
    it "ріже рядок на три %08X-слова у порядку регістрів (golden g1)" do
      expect(described_class.uid_words("0039002F3138511538323634"))
        .to eq([ 0x0039002F, 0x31385115, 0x38323634 ])
    end

    it "деривує той самий wire-DID, що й пословний виклик (golden g1)" do
      expect(described_class.wire_did_from_uid_hex("0039002F3138511538323634"))
        .to eq("SNET-80B12004")
    end

    it "нормалізує регістр і краї" do
      expect(described_class.wire_did_from_uid_hex(" 0039002f3138511538323634\n"))
        .to eq("SNET-80B12004")
    end

    it "відкидає не-24-hex вхід голосно (ArgumentError, не сміттєвий DID)" do
      expect { described_class.uid_words("SNET-80B12004") }
        .to raise_error(ArgumentError, /24 hex/)
      expect { described_class.uid_words("0039002F31385115383236") }
        .to raise_error(ArgumentError)
      expect { described_class.uid_words(nil) }
        .to raise_error(ArgumentError)
    end
  end
end
