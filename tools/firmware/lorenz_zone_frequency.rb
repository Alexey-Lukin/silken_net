#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Частота Z-зон на ТЕПЛОМУ ланцюзі — справжній контракт прошивки, не бекендне
# дзеркало (`firmware/bio_contracts/bio_contract.rb`, той самий `evaluate_and_pack`,
# що ганяє mruby на Солдаті). Друкує частку циклів зі статусом stress на заводській
# смузі, частку z нижче порогів родин (5.0 · 8.0 — колишні сіди, знято з FW.66) і MAX-зону
# дуба (колишній сід 40.0):
# цикли, де смуга родини каже anomaly (0 балів), а заводська — homeostasis (5–31),
# тобто ціну заводської смуги як кандидата після доказу (FW.8, поправка 7), за температурою.
# ⊕ anomaly на заводській смузі — кадр без балів (`EMISSION_ELIGIBLE_STATUSES`), тобто ціну
# z-статусу, що його задає хаос нашого `K_seed`, а не ліс (E.64 · FW.66).
#
# Навіщо окремо від cold-start-заміру: «stress (z < 2) недосяжний» стояв у каноні на
# 0 з 5 000 холодних стартів, а ρ-clamp обмежує РІВНОВАГУ (z_eq = ρ − 1), не
# траєкторію, — теплий ланцюг проходить повз сідло в нулі й дає z < 2, рідко й холодом
# (03_04 §5.3). Числа — вибірка з фіксованих зерен; інша популяція старту дасть інші.
#
#   ruby tools/firmware/lorenz_zone_frequency.rb [--cycles N]
load File.expand_path("../../firmware/bio_contracts/bio_contract.rb", __dir__)

cycles = ARGV.include?("--cycles") ? Integer(ARGV[ARGV.index("--cycles") + 1]) : 60_000
seeds  = [ 11, 22, 33 ]
temps  = [ -25, -15, -5, 0, 10, 20, 30, 41 ]

puts "теплий ланцюг: #{cycles} циклів × #{seeds.size} стартів ∈ [-1,1]; acoustic 0; смуга 2.0/45.0"
temps.each do |temp|
  total = stress = anomaly = below5 = below8 = oak_max = 0
  zmin = Float::INFINITY
  seeds.each do |seed|
    rng = Random.new(seed)
    x, y, z = Array.new(3) { (rng.rand * 2) - 1 }
    cycles.times do
      oak = SilkenNet::BioContract.evaluate_and_pack(x, y, z, temp.to_f, 0.0, 60, 3300, 2.0, 40.0)
      payload, x, y, z = SilkenNet::BioContract.evaluate_and_pack(x, y, z, temp.to_f, 0.0, 60, 3300, 2.0, 45.0)
      abort "смуга зрушила траєкторію" unless oak[1..] == [ x, y, z ]
      total += 1
      stress += 1 if ((payload >> 5) & 3) == 1
      anomaly += 1 if ((payload >> 5) & 3) == 2
      oak_max += 1 if ((oak[0] >> 5) & 3) == 2 && ((payload >> 5) & 3).zero?
      below5 += 1 if z < 5.0
      below8 += 1 if z < 8.0
      zmin = z if z < zmin
    end
  end
  pct = ->(n) { format("%.4f %%", 100.0 * n / total) }
  puts format("%+4d °C  stress %s · anomaly %s · z<5 %s · z<8 %s · MAX-зона дуба %s · min z %.2f",
              temp, pct.(stress), pct.(anomaly), pct.(below5), pct.(below8), pct.(oak_max), zmin)
end
