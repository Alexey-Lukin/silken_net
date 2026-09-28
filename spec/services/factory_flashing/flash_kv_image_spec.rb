# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.17] Golden-пін образу журналу re-provision (03_05 §3.8). Ті самі три
# doubleword'и `firmware/test/test_flash_kv.c` монтує справжнім flash_kv.c і
# звіряє з журналом, який прошивка лишає сама — тож зміна формату з будь-якого
# боку червонить протилежний пін.
RSpec.describe FactoryFlashing::FlashKvImage do
  it "emits the golden journal page for hiwater 42 (SKV1 · FINI · 0x15 = 42)" do
    expect(described_class.dws(ota_hiwater: 0x2A)).to eq([ 0x534B56310001FDE5, 0x46494E4900010F2E, 0x0000002A15A556DE ])
  end

  it "lays each doubleword little-endian for -w32 — low word at the dw address" do
    expect(described_class.words(ota_hiwater: 0x2A)).to eq(
      0x0803D000 => "0x0001FDE5", 0x0803D004 => "0x534B5631",
      0x0803D008 => "0x00010F2E", 0x0803D00C => "0x46494E49",
      0x0803D010 => "0x15A556DE", 0x0803D014 => "0x0000002A"
    )
  end

  it "names both journal pages for erasure — a surviving sibling with a higher seq would win the mount" do
    expect(described_class::PAGES).to eq([ 122, 123 ])
    expect(described_class::BASE_ADDR).to eq(0x08000000 + (122 * 0x800))
  end

  it "rejects a hiwater outside u32" do
    expect { described_class.dws(ota_hiwater: -1) }.to raise_error(ArgumentError)
    expect { described_class.dws(ota_hiwater: 0x1_0000_0000) }.to raise_error(ArgumentError)
  end
end
