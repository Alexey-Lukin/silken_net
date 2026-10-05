# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.66] Чи варто міняти ядро Z на Солдаті: Лоренц ⊥ відображення Ено ⊥ HMAC.
# Робочий аркуш — `docs/protocols/hardware/z_core_forks.md`; розвилка — `00_07` FW.66, нога 2.
#
# Що міряє (печатка = шанс фальсифікатора без `K_seed` влучити у вихідне число за кадр):
#   • Ено (x' = 1 − a·x² + y, y' = b·x): показник Ляпунова при a = 1.4, b = 0.3; скільки значень a з
#     [1.00, 1.42] не хаотичні, якби a модулювати температурою, як ρ у Лоренца; скільки випадкових
#     стартів у природній коробці тікає в нескінченність; біти печатки — найщільніший бін із 2^16;
#   • Лоренц, якір у габарит атрактора (рекомендація (А) FW.66), 250 кроків — ті самі біти.
# Енергію ядра друкує інший прилад: `ruby tools/firmware/tx_cadence_budget.rb lorenz_mj=…`.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/z_core_alternatives.rb
#
# ⛔ СТЕЛІ, ОГОЛОШЕНІ ВГОЛОС:
#   • біти — за 2^16 бінами на діапазон змінної (дріт `device_z` — 16 біт); найщільніший бін із N
#     зразків має підлогу ≈ 6/N навіть за рівномірного розподілу, тож для Лоренца число — межа вибірки;
#   • a модулюється лише гіпотетично: ядро Ено з температурою не написано — рядок показує, ЧОМУ так
#     робити не можна (періодичні вікна), а не що робила б прошивка;
#   • HMAC тут не рахується: його печатка — криптографічна (16 біт за усіченого тегу), а ціну в тактах
#     дає оцінка, не вимір (шапка аркуша).

$LOAD_PATH.unshift File.expand_path("../../app/services", __dir__)
module SilkenNet; end
require "openssl"
require "silken_net/attractor"
require "silken_net/seed_derivation"

A = SilkenNet::Attractor
SD = SilkenNet::SeedDerivation

def henon_lyapunov(a, b: 0.3, steps: 20_000, burn: 1_000)
  x = y = 0.1
  v = [ 1.0, 0.0 ]
  sum = 0.0
  (burn + steps).times do |i|
    v = [ (-2.0 * a * x * v[0]) + v[1], b * v[0] ] # якобіан [[−2ax, 1], [b, 0]]
    x, y = 1.0 - (a * x * x) + y, b * x
    return nil unless x.finite? && x.abs < 1e6

    norm = Math.hypot(*v)
    v = v.map { |c| c / norm }
    sum += Math.log(norm) if i >= burn
  end
  sum / steps
end

def densest_bin_bits(values, low, high)
  share = values.map { |v| ((v - low) / (high - low) * 65_536).floor }.tally.values.max.fdiv(values.size)
  [ share, -Math.log2(share) ]
end

lyapunov = henon_lyapunov(1.4)
abort "Ено розійшовся з літературою (λ ≈ 0.419)" unless (lyapunov - 0.419).abs < 0.01
puts format("Ено a = 1.4, b = 0.3: λ = %.3f на ітерацію → за 64 ітерації різниця росте в %.1e раз",
            lyapunov, Math.exp(lyapunov * 64))

grid = (0..420).map { |k| 1.0 + (k * 0.001) }
lams = grid.map { |a| henon_lyapunov(a, steps: 4_000, burn: 500) }
windows = lams.compact.count { |l| l <= 0.0 }
puts format("якби a модулювала температура в [1.00, 1.42]: не хаос (λ ≤ 0) — %d із %d значень, утеча — %d",
            windows, grid.size, lams.count(&:nil?))

rng = Random.new(5)
escaped = 20_000.times.count do
  x = (rng.rand * 3) - 1.5
  y = (rng.rand * 0.9) - 0.45
  64.times do
    x, y = 1.0 - (1.4 * x * x) + y, 0.3 * x
    break unless x.abs < 1e3
  end
  x.abs >= 1e3 || !x.finite?
end
puts format("утеча стартів із коробки [-1.5, 1.5] × [-0.45, 0.45] за 64 ітерації: %.1f %%", escaped / 200.0)

rng = Random.new(7)
henon_x = []
while henon_x.size < 200_000
  x = (rng.rand * 2) - 1
  y = (rng.rand * 0.6) - 0.3
  alive = 64.times.all? { (x, y = 1.0 - (1.4 * x * x) + y, 0.3 * x) && x.abs < 10 }
  henon_x << x if alive
end
share, bits = densest_bin_bits(henon_x, -1.3, 1.3)
puts format("печатка Ено (x після 64 ітерацій, 200 000 стартів): найщільніший бін %.1e → %.1f біт на кадр", share, bits)

rng = Random.new(9)
rho = 30.0 # T = 10 °C
box = ->(u) { [ u[0] * 20.0, u[1] * 27.0, 1.0 + ((u[2] + 1.0) / 2.0 * (rho + 19.0)) ] }
lorenz_z = Array.new(60_000) do
  *, z = A.calculate_z_from_state(*A.as_rtc_state(box.(SD.initial_state(rng.bytes(32), 1))), 10.0, 0)
  z
end
share, bits = densest_bin_bits(lorenz_z, 0.0, 64.0)
puts format("печатка Лоренца (якір у габарит, 250 кроків, 60 000 стартів): найщільніший бін %.1e → %.1f біт (підлога вибірки ≈ %.0e)",
            share, bits, 6.0 / 60_000)
