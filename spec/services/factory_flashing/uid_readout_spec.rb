# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FactoryFlashing::UidReadout do
  describe ".words" do
    it "парсить канонічний рядок CLI (адреса : три слова)" do
      stdout = <<~OUT
        Reading 32-bit memory content
          Size          : 12 Bytes
          Address:      : 0x1fff7590

        0x1FFF7590 : 0039002F 31385115 38323634
      OUT

      expect(described_class.words(stdout)).to eq([ 0x0039002F, 0x31385115, 0x38323634 ])
    end

    it "толерантний до 0x-префіксів і нижнього регістру слів" do
      expect(described_class.words("0x1fff7590: 0x0039002f 0x31385115 0x38323634"))
        .to eq([ 0x0039002F, 0x31385115, 0x38323634 ])
    end

    it "nil без адресного рядка (чужий/порожній вивід — Session відмовляє записом)" do
      expect(described_class.words("FAKE-CLI OK")).to be_nil
      expect(described_class.words(nil)).to be_nil
    end

    it "nil при <3 словах після адреси (обрізаний вивід)" do
      expect(described_class.words("0x1FFF7590 : 0039002F 31385115")).to be_nil
    end
  end

  describe ".uid_hex" do
    it "склеює слова у канонічний 24-hex паспорт (форма trees.silicon_uid_hex)" do
      expect(described_class.uid_hex([ 0x0039002F, 0x31385115, 0x38323634 ]))
        .to eq("0039002F3138511538323634")
    end
  end
end
