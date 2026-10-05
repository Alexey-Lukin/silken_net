# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.66] Що зробить із розподілом статусу ЯКІР КАДРУ — свіжий старт із `K_seed` на кожен кадр
# замість теплого ланцюга (розвилка `00_07 FW.66`, механізм — `03_04 §7.3`).
#
# Свіжий старт лежить у [-1,1]³, тобто біля сідла в нулі, і всі такі старти перші петлі йдуть
# однією нестійкою гілкою: z після N кроків ФАЗОВО-КОГЕРЕНТНИЙ, тож частка кадрів поза смугою
# стає функцією температури й N, а не хаосу. Теплий ланцюг давно на атракторі й дає
# інваріантну частку. Прилад друкує обидві — для кількох N і двох смуг (заводська 45 ·
# дубова 40, сід FW.8). ⊕ Якір у ГАБАРИТ атрактора (точка HMAC → коробка x ±20 · y ±27 ·
# z 1…ρ+20, далі ті самі 250 кроків) різні старти одразу розводить по фазах — його частка
# друкується поруч; і сила печатки: частка ключів, чий z лягає в найщільніший квант дроту
# (q = 2⁻⁹ ≈ 2ε), тобто шанс фальсифікатора без `K_seed` влучити за кадр.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/lorenz_anchor_transient.rb
#
# ⛔ СТЕЛІ, ОГОЛОШЕНІ ВГОЛОС:
#   • якір емульовано `SeedDerivation.initial_state(seed, n)` — HMAC тієї самої форми, тож
#     розподіл старту в [-1,1]³ той самий; справжній якір мав би власну доменну мітку;
#   • температура стала на прогін, акустика 0 (пʼєзо зрізано, HW.30); ρ = 28 + 0.2·T;
#   • N > 250 — це ціна в обчисленні Фази 3 (пропорційно; енергія 250 кроків на кремнії
#     не міряна — у каноні стеля 3.96 мДж, `02_03 §9.4`);
#   • вибірка: теплий ланцюг 20 × 2000 кадрів, свіжий старт 20 × 300 на кожне N;
#   • коробка — моя конструкція (межі з габариту атрактора при ρ 28…36), а сила печатки впирається
#     в роздільність вибірки: найщільніший квант із 6000 зразків при ≈ 20 000 квантів діапазону
#     набирає кілька влучень і за рівномірного розподілу, тож число нижче ≈ 1·10⁻³ — межа, не міра.

$LOAD_PATH.unshift File.expand_path("../../app/services", __dir__)
module SilkenNet; end
require "openssl"
require "silken_net/attractor"
require "silken_net/seed_derivation"

A = SilkenNet::Attractor
SD = SilkenNet::SeedDerivation
STEPS = [ 250, 300, 350, 400, 500, 750 ].freeze
CASES = [ [ -10, 45.0 ], [ 10, 45.0 ], [ 30, 45.0 ], [ 41, 45.0 ], [ 41, 40.0 ] ].freeze

# Те саме ядро, що `Attractor.iterate_lorenz` (явний Ейлер, BASE_SIGMA за акустики 0), але з N кроків.
def z_after(xyz, rho, steps)
  x, y, z = xyz
  steps.times do
    dx = A::BASE_SIGMA * (y - x)
    dy = x * (rho - z) - y
    dz = (x * y) - (A::BASE_BETA * z)
    x += dx * A::DT
    y += dy * A::DT
    z += dz * A::DT
  end
  z
end

rho_at = ->(t) { (A::BASE_RHO + (t * 0.2)).clamp(A::RHO_LIMITS.min, A::RHO_LIMITS.max) }
box = ->(u, t) { [ u[0] * 20.0, u[1] * 27.0, 1.0 + ((u[2] + 1.0) / 2.0 * (rho_at.(t) + 19.0)) ] }
best_quantum = ->(zs) { zs.map { |z| (z * 512).round }.tally.values.max.fdiv(zs.size) }

# Самоперевірка: на N = ITERATIONS ядро приладу бітово ≡ серверному.
probe = Random.new(1)
5.times do
  start = A.as_rtc_state(SD.initial_state(probe.bytes(32), 20_300))
  *, z_server = A.calculate_z_from_state(*start, 41.0, 0)
  abort "ядро приладу розійшлося з Attractor" unless z_after(start, rho_at.(41.0), A::ITERATIONS) == z_server
end

puts "lorenz_anchor_transient — частка кадрів із z ВИЩЕ ρ-відносної стелі (anomaly, 0 балів)"
CASES.each do |temp, zmax|
  rng = Random.new(20_261_005) # детерміновано: число в каноні відтворюється цією командою
  seeds = Array.new(20) { rng.bytes(32) }
  ceiling = A.anomaly_ceiling(temp, zmax)
  above = ->(z) { z > ceiling }

  warm = 0
  seeds.each do |seed|
    state = A.as_rtc_state(SD.initial_state(seed, 20_300))
    2000.times do
      _, x, y, z = A.calculate_z_from_state(*state, temp, 0)
      warm += 1 if above.(z)
      state = A.as_rtc_state([ x, y, z ])
    end
  end

  starts = seeds.flat_map { |seed| Array.new(300) { |k| SD.initial_state(seed, 1_000_000 + k) } }
  unit_z = starts.map { |u| z_after(A.as_rtc_state(u), rho_at.(temp), A::ITERATIONS) }
  box_z = starts.map { |u| z_after(A.as_rtc_state(box.(u, temp)), rho_at.(temp), A::ITERATIONS) }
  fresh = STEPS.map do |steps|
    hits = seeds.sum do |seed|
      300.times.count { |k| above.(z_after(A.as_rtc_state(SD.initial_state(seed, 1_000_000 + k)), rho_at.(temp), steps)) }
    end
    format("%d: %.1f %%", steps, 100.0 * hits / 6000)
  end
  puts format("  %+d °C, смуга до %.0f (стеля %.1f): теплий ланцюг %.2f %% · свіжий старт за N кроків — %s",
              temp, zmax, ceiling, 100.0 * warm / 40_000, fresh.join(" · "))
  puts format("      якір у габарит, 250 кроків: %.2f %% · печатка (найщільніший квант): якір [-1,1]³ %.1e · габарит %.1e",
              100.0 * box_z.count(&above) / box_z.size, best_quantum.(unit_z), best_quantum.(box_z))
end
