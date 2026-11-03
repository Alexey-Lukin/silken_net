# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telemetry::EmaRecurrence do
  let(:unknown) { SilkenNet::Attractor::DELTA_T_UNKNOWN_S }

  # 🔴 Паритет МІЖ мовами: α — з того самого заголовка, що компілює прошивка, а таблиці — з її host-тесту.
  # Власних копій спек не тримає: інакше кожна сторона звіряла б арифметику лише сама з собою, і зміна α в
  # заголовку разом із C-пінами лишила б обидві сюїти зеленими при розбіжному дзеркалі.
  let(:header)    { Rails.root.join("firmware/common/ema_filter.h").read }
  let(:host_test) { Rails.root.join("firmware/test/test_soldier_logic.c").read }

  def host_table(test_name, columns)
    body = host_test[/TEST\(#{test_name}\)(.*?)\nTEST\(/m, 1].to_s
    row  = /\{\s*#{([ '(\d+)u' ] * columns).join(',\s*')}\s*\}/
    body.scan(row).map { |cells| cells.map(&:to_i) }
  end

  it "бере α з заголовка, який компілює прошивка" do
    expect(header[/#define EMA_ALPHA_NUM\s+(\d+)/, 1]&.to_i).to eq(described_class::ALPHA_NUM)
    expect(header[/#define EMA_ALPHA_DEN\s+(\d+)/, 1]&.to_i).to eq(described_class::ALPHA_DEN)
  end

  it "тепла гілка — та сама ціла арифметика, що EMA_Update (піни host-тесту)" do
    pins = host_table("test_ema_warm_step_pins", 3)

    expect(pins.size).to eq(5) # порожня вибірка зелена завжди — розмір пінимо
    pins.each { |prev_x100, raw, next_x100| expect(described_class.step_x100(prev_x100, raw)).to eq(next_x100) }
  end

  # Golden-послідовність host-тесту — [сирий, стан ×100, лічильник, EMA на дроті] на пробудження.
  describe "golden-послідовність прошивки" do
    let(:gold) { host_table("test_ema_golden_wire_sequence", 4) }

    it "внутрішній стан ×100 іде за дзеркалом на кожному теплому кроці" do
      expect(gold.size).to eq(10)
      gold.each_cons(2) do |(_, prev_x100, prev_count, _), (raw, x100, _, _)|
        next if prev_count.zero?

        expected = raw == unknown ? prev_x100 : described_class.step_x100(prev_x100, raw)
        expect(x100).to eq(expected)
      end
    end

    it "так, як її бачить сервер, — кожна пара, що судиться, узгоджена" do
      wire = gold.map { |raw, _x100, _count, ema| [ [ raw, described_class::WIRE_MAX ].min, ema ] }
      verdicts = wire.each_cons(2).map do |(_, prev_ema), (raw, ema)|
        described_class.deviation(prev_ema: prev_ema, raw: raw, ema: ema)
      end

      # прогрів ×2 · узгоджено ×3 (третя — сентинел сирого) · сатурований сирий · узгоджено ×3
      expect(verdicts).to eq([ nil, nil, 0, 0, 0, nil, 0, 0, 0 ])
    end
  end

  it "фальсифікатор, що тримає EMA коротшою за сирий, читається мінусом" do
    expect(described_class.deviation(prev_ema: 3000, raw: 6500, ema: 3000)).to eq(-700)
  end

  it "допуск — рівно зрізання дроту до секунди, не ширше" do
    expect(described_class.expected_range(prev_ema: 6506, raw: 7003)).to eq(6605..6606)
    expect(described_class.deviation(prev_ema: 6506, raw: 7003, ema: 6604)).to eq(-1)
    expect(described_class.deviation(prev_ema: 6506, raw: 7003, ema: 6607)).to eq(1)
  end

  it "на сентинелі сирого EMA мусить лишитись тією самою" do
    expect(described_class.deviation(prev_ema: 6605, raw: unknown, ema: 6605)).to eq(0)
    expect(described_class.deviation(prev_ema: 6605, raw: unknown, ema: 6604)).to eq(-1)
  end

  it "пари без висновку не судить" do
    expect(described_class.deviation(prev_ema: unknown, raw: 6500, ema: 6500)).to be_nil # прогрів, скид фільтра
    expect(described_class.deviation(prev_ema: 0xFFFF, raw: 6500, ema: 6500)).to be_nil  # стан над дротом невідомий
    expect(described_class.deviation(prev_ema: 6500, raw: 0xFFFF, ema: 6500)).to be_nil  # фільтр узяв більше за дріт
    expect(described_class.deviation(prev_ema: 6500, raw: 6500, ema: unknown)).to be_nil # скид фільтра між кадрами
  end

  it "бік відхилення — мітка, значення — модуль" do
    expect([ -700, 0, 3 ].map { described_class.side(_1) }).to eq(%w[short exact long])
  end
end
