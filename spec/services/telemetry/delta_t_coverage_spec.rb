# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telemetry::DeltaTCoverage do
  let(:now) { Time.utc(2026, 10, 9, 12, 0, 0) }

  it "ділить суму сирих delta_t на час від попереднього прийому" do
    expect(described_class.ratio([ 3600, 3600 ], since: now - 7200, now: now)).to be_within(1e-9).of(1.0)
    expect(described_class.ratio([ 600 ], since: now - 6000, now: now)).to be_within(1e-9).of(0.1)
  end

  it "мовчить на першому прийомі дерева" do
    expect(described_class.ratio([ 3600 ], since: nil, now: now)).to be_nil
  end

  it "мовчить, коли проміжок тоне в затримці черги" do
    expect(described_class.ratio([ 30 ], since: now - 59, now: now)).to be_nil
    expect(described_class.ratio([ 60 ], since: now - 60, now: now)).to be_within(1e-9).of(1.0)
  end

  it "рахує по виміряних кадрах: сентинел пропускає, сатурований дріт — нижньою межею" do
    unknown = SilkenNet::Attractor::DELTA_T_UNKNOWN_S
    expect(described_class.ratio([ 3600, unknown ], since: now - 7200, now: now)).to be_within(1e-9).of(0.5)
    expect(described_class.ratio([ 70_000 ], since: now - 70_000, now: now)).to be_within(1e-9).of(65_535 / 70_000.0)
  end

  it "один сентинел на конверт не засліплює підробку — частка лишається низькою" do
    unknown = SilkenNet::Attractor::DELTA_T_UNKNOWN_S
    expect(described_class.ratio([ 600, 600, unknown ], since: now - 13_000, now: now)).to be < 0.1
  end

  it "мовчить, коли жодного виміряного кадру" do
    expect(described_class.ratio([ SilkenNet::Attractor::DELTA_T_UNKNOWN_S ], since: now - 3600, now: now)).to be_nil
  end

  it "кадр без поля (паніка) пропускає, а без жодного виміряного — мовчить" do
    expect(described_class.ratio([ nil, 3600 ], since: now - 3600, now: now)).to be_within(1e-9).of(1.0)
    expect(described_class.ratio([ nil ], since: now - 3600, now: now)).to be_nil
    expect(described_class.ratio([], since: now - 3600, now: now)).to be_nil
  end
end
