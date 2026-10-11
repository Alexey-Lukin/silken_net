# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/leaf_payload_shape"

# [FW.66 (Б) · S8] Форма листа, яку судять обидва офлайн-верифікатори. Хешування тут ні до чого:
# спека судить рамку v2 так, як її бачить аудитор без ключа.
RSpec.describe LeafPayloadShape do
  let(:frame) { "000ddf01" + ("ab" * 26) }
  let(:v2) do
    { "leaf_version" => 2, "telemetry_log_id" => 7, "device_uid" => "SNET-000DDF01",
      "raw_record" => frame, "qatt_envelope_sha256" => "ab" * 32, "ema_delta_t_s" => 3600,
      "growth_points" => 38, "created_at" => "2026-07-19T12:00:00.000000Z" }
  end

  it "приймає чесний лист v2" do
    expect(described_class.errors(v2)).to be_empty
  end

  it "відкидає верхній регістр hex — інакше той самий кадр мав би дві форми й минав перевірку повтору" do
    expect(described_class.errors(v2.merge("raw_record" => frame.upcase))).to include(/60 нижніх hex/)
  end

  it "відкидає версію, задану не цілим 2" do
    expect(described_class.errors(v2.merge("leaf_version" => "2"))).to include(/невідома версія/)
  end

  # ⚖️ [FW.66 (Б) · S8b] Бали v2 законні рівно двох значень: формула v2 від входу або нуль.
  describe "бали листа v2 проти замороженої формули" do
    it "нуль при додатній формулі — законне утримання, і воно рахується, а не падає" do
      held = v2.merge("growth_points" => 0)

      expect(described_class.errors(held)).to be_empty
      expect(described_class.v2_points_held?(held)).to be(true)
      expect(described_class.v2_points_held?(v2)).to be(false)
    end

    it "третє значення — підробка листа" do
      expect(described_class.errors(v2.merge("growth_points" => 37))).to include(/∉ \{0, 38\}/)
    end

    it "паніка (вхід NULL) і «не виміряно» (0) — лише нуль балів" do
      expect(described_class.errors(v2.merge("ema_delta_t_s" => nil, "growth_points" => 0))).to be_empty
      expect(described_class.errors(v2.merge("ema_delta_t_s" => 0, "growth_points" => 10))).to include(/∉ \{0, 0\}/)
    end

    it "дробові бали, вхід поза u16 і хеш конверта не в нижньому hex — відмова форми" do
      expect(described_class.errors(v2.merge("growth_points" => 38.0))).to include(/невідʼємне ціле/)
      expect(described_class.errors(v2.merge("ema_delta_t_s" => 65_536))).to include(/0\.\.65535/)
      expect(described_class.errors(v2.merge("qatt_envelope_sha256" => "AB" * 32))).to include(/64 нижніх hex/)
    end
  end
end
