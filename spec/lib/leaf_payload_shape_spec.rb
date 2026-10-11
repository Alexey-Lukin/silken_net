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
      "raw_record" => frame, "created_at" => "2026-07-19T12:00:00.000000Z" }
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
end
