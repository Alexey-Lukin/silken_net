# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.17] Golden-KAT parity з firmware/common/key_ratchet.h: ті самі вектори
# (K0 = 000102..0F, DID = 0xDEADBEEF) заморожені у firmware/test/
# test_key_ratchet.c — зміна будь-якого байта мусить впасти ОБАБІЧ.
RSpec.describe Cryptography::KeyRatchet do
  let(:k0_hex) { "000102030405060708090A0B0C0D0E0F" }
  let(:did)    { 0xDEADBEEF }

  describe ".next_key_hex (KAT-ланцюг)" do
    it "відтворює заморожений ланцюг K1→K2→K3" do
      k1 = described_class.next_key_hex(k0_hex, did)
      k2 = described_class.next_key_hex(k1, did)
      k3 = described_class.next_key_hex(k2, did)

      expect(k1).to eq("C2A8861DEF01E2A944D3CD989A7CF117")
      expect(k2).to eq("4E1E7355E593D034E7D800D0B9843506")
      expect(k3).to eq("C7593AA70E31334ABB2BA45DC79B153B")
    end

    it "розводить ланцюги різних DID при спільному K0 (Context у KDF)" do
      expect(described_class.next_key_hex(k0_hex, did))
        .not_to eq(described_class.next_key_hex(k0_hex, 0xCAFEF00D))
    end

    it "відкидає ключ неправильної довжини" do
      expect { described_class.next_key("short".b, did) }
        .to raise_error(described_class::InputError)
    end

    it "відкидає nil-ключ (guard проти nil-receiver у `current_key&.bytesize`)" do
      expect { described_class.next_key(nil, did) }
        .to raise_error(described_class::InputError)
    end
  end

  describe ".advance_hex (версійна дисципліна — дзеркало Key_Ratchet_Steps)" do
    it "просуває на кілька версій одним викликом (0 → 3 = K3)" do
      expect(described_class.advance_hex(k0_hex, did, from: 0, to: 3))
        .to eq("C7593AA70E31334ABB2BA45DC79B153B")
    end

    it "відмовляє replay, rollback і runaway-стрибок" do
      expect(described_class.advance_hex(k0_hex, did, from: 5, to: 5)).to be_nil
      expect(described_class.advance_hex(k0_hex, did, from: 5, to: 2)).to be_nil
      expect(described_class.advance_hex(k0_hex, did, from: 0, to: 9)).to be_nil
      expect(described_class.advance_hex(k0_hex, did, from: 0, to: 8)).to be_present
    end
  end

  describe ".did_to_u32 (інверсія SNET-%08X)" do
    it "повертає сирий uint32 DID — той самий Context, що бачить firmware" do
      expect(described_class.did_to_u32("SNET-DEADBEEF")).to eq(0xDEADBEEF)
    end

    it "відкидає рядок поза апаратним форматом" do
      expect { described_class.did_to_u32("DEADBEEF") }
        .to raise_error(described_class::InputError)
      expect { described_class.did_to_u32("SNET-XYZ") }
        .to raise_error(described_class::InputError)
    end
  end

  describe "OtaPackagerService.build_rotate_key_block (wire 0x9E)" do
    it "емітить заморожений golden-кадр (target_version = 3)" do
      # Той самий hex парсить firmware test_parse_golden_frame.
      block = OtaPackagerService.build_rotate_key_block(3)
      expect(block.unpack1("H*").upcase).to eq("9E040003005C48")
    end

    it "відкидає версію поза u16 (0 — не команда, ratchet тільки вперед)" do
      expect { OtaPackagerService.build_rotate_key_block(0) }.to raise_error(ArgumentError)
      expect { OtaPackagerService.build_rotate_key_block(0x1_0000) }.to raise_error(ArgumentError)
    end
  end
end
