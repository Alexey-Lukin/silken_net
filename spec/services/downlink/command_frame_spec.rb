# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.17 · docs/03_05 §2.5] Адресні команди Rails → Солдат. Кадри пінуються тими
# самими golden-векторами, що відкриває прошивка (CCM_KAT_DOWNLINK у
# firmware/common/ccm_kat_vectors.h, Dl_Ccm_Open у test_downlink_ccm.c): зелене
# тут і там = команда, збудована Rails, відкривається на Солдаті байт-у-байт.
RSpec.describe Downlink::CommandFrame, type: :service do
  def key_record(device_uid:, current_hex:, previous_hex: nil, key_version: 0, dlfc: 0)
    HardwareKey.new(device_uid: device_uid, aes_key_hex: current_hex,
                    previous_aes_key_hex: previous_hex, key_version: key_version,
                    downlink_frame_counter: dlfc)
  end

  describe ".rotate_key" do
    # DL1: ключ 00..0f — ПОПЕРЕДНІЙ, бо вузол у grace ще тримає саме його.
    let(:in_grace) do
      key_record(device_uid: "SNET-534E4554", current_hex: "AB" * 16,
                 previous_hex: (0..15).map { |b| format("%02X", b) }.join,
                 key_version: 3, dlfc: 0x0001_0002)
    end

    # Фіксований кадр = перевидача дає ті самі байти: Королева лише освіжає бюджет.
    it "builds the firmware-pinned DL1 frame under the PREVIOUS key" do
      expect(described_class.rotate_key(in_grace).unpack1("H*")).to eq("9e534e45540002651cdc65306dc0c12c0a")
    end

    it "refuses a closed grace — nothing to rotate" do
      in_grace.previous_aes_key_hex = nil
      expect { described_class.rotate_key(in_grace) }.to raise_error(ArgumentError, /не відкритий/)
    end

    it "refuses a re-provision grace (version 0) — MIC closes it, not 0x9E" do
      in_grace.key_version = 0
      expect { described_class.rotate_key(in_grace) }.to raise_error(ArgumentError, /не відкритий/)
    end

    it "refuses a grace without an issued DLFC — the Soldier never accepts DLFC 0" do
      in_grace.downlink_frame_counter = 0
      expect { described_class.rotate_key(in_grace) }.to raise_error(ArgumentError, /DLFC ротації не видано/)
    end
  end
end
