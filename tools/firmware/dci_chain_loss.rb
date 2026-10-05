# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.66] Чи переживає теплий ланцюг DCI ВТРАТУ кадру — і що робить сервер, коли не переживає.
#
# Сервер продовжує Лоренц від хвоста ОСТАННЬОГО ОТРИМАНОГО `TelemetryLog`
# (`TelemetryUnpackerService#previous_lorenz_state_for`), а пристрій — від стану в RTC після
# КОЖНОГО свого кроку. Паритет тримається лише тоді, коли кожен крок пристрою доходить до
# сервера кадром (`03_04 §5`: «паритет — це й КІЛЬКІСТЬ кроків»). Прилад моделює дві сторони
# на ОДНОМУ ядрі (`SilkenNet::Attractor`, бітово ≡ mruby з FW.7) і рахує, чим закінчується
# розбіжність після одного втраченого кадру: відновленням ARCH.41 (три cold-кандидати доби —
# дзеркало `TelemetryUnpackerService#try_time_sync_recovery`) або прапорцем fraud.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/dci_chain_loss.rb               # каденс 1.81 год, 20 дерев × 2000 кадрів
#   ruby tools/firmware/dci_chain_loss.rb h=1.731 frames=4000 trees=40
#   ruby tools/firmware/dci_chain_loss.rb temp=-10                # стала температура замість добової синусоїди
#
# ⛔ СТЕЛІ, ОГОЛОШЕНІ ВГОЛОС:
#   • обидві сторони — СЕРВЕРНЕ ядро; паритет ядер mruby ⟷ CRuby — предмет Gate L
#     (`tools/firmware/dci_epsilon_sweep.sh`), не цього приладу;
#   • смуга — лише заводська (2.0 … 45.0, ρ-відносна стеля): набір кандидатів FW.8
#     (`Tree#device_lorenz_bands`) не моделюється, а розсинхронізований ланцюг ще й ПОДАЄ
#     хибні докази смуги (`record_band_evidence!`) — цього числа тут немає;
#   • температура — синтетична добова синусоїда 10 ± 8 °C: частка кадрів поза смугою залежить
#     від ρ(T), тож ставка — властивість цієї моделі, не поля; акустика 0 (пʼєзо зрізано, HW.30);
#   • «хибний time-sync» лічить СПРАЦЮВАННЯ відновлення; `TimeSyncDownlinkWorker` тротлінгу не
#     має, тож кожне — CoAP PUT і маяк Королеви, але ефірний час маяків тут не рахується;
#   • втрата — РІВНО ОДИН кадр; реальна PER дає кілька, і кожен лише перезапускає той самий
#     розсинхрон (другий не «лагодить» перший).

$LOAD_PATH.unshift File.expand_path("../../app/services", __dir__)
module SilkenNet; end
require "openssl"
require "silken_net/attractor"
require "silken_net/seed_derivation"

A = SilkenNet::Attractor
SD = SilkenNet::SeedDerivation
BAND_MIN = 2.0                  # дзеркало firmware LORENZ_DEFAULT_Z_MIN_X100 / 100
BAND_MAX = 45.0                 # дзеркало firmware LORENZ_DEFAULT_Z_MAX_X100 / 100
RTC_DEFAULT_EPOCH_DAY = 10_957  # дзеркало TelemetryUnpackerService::FIRMWARE_RTC_DEFAULT_EPOCH_DAY
DAY0 = 20_300                   # довільна «сьогоднішня» доба моделі

params = { "h" => 1.81, "frames" => 2000, "trees" => 20, "lost_at" => 10, "temp" => nil }
ARGV.each do |arg|
  key, value = arg.split("=", 2)
  abort "невідомий параметр: #{arg}" unless params.key?(key) && value
  params[key] = %w[h temp].include?(key) ? Float(value) : Integer(value)
end
h, frames, trees, lost_at = params.values_at("h", "frames", "trees", "lost_at")
FIXED_TEMP = params["temp"]

def in_band?(z, temp) = z >= BAND_MIN && z <= A.anomaly_ceiling(temp, BAND_MAX)
def temp_at(k, h) = FIXED_TEMP || (10.0 + 8.0 * Math.sin(2 * Math::PI * (k * h) / 24.0))

# Один ланцюг пари «пристрій ⟷ сервер». lost_at < 0 — контроль без втрат.
def run_tree(seed:, frames:, h:, lost_at:)
  device = SD.initial_state(seed, DAY0)
  server = device.dup
  outcome = Hash.new(0)
  frames.times do |k|
    temp = temp_at(k, h)
    day = DAY0 + ((k * h) / 24.0).floor
    _, dx, dy, dz = A.calculate_z_from_state(*device, temp, 0)
    device = [ dx, dy, dz ]
    next if k == lost_at # кадр k загубився в ефірі: пристрій крокнув, сервер його не бачив

    _, sx, sy, sz = A.calculate_z_from_state(*server, temp, 0)
    server = [ sx, sy, sz ]
    device_in = in_band?(dz, temp)
    next if device_in == in_band?(sz, temp)

    recovered = [ day, day - 1, RTC_DEFAULT_EPOCH_DAY ].any? do |d|
      *, zc = A.calculate_z_from_state(*SD.initial_state(seed, d), temp, 0)
      in_band?(zc, temp) == device_in
    end
    outcome[recovered ? :spurious_time_sync : :false_fraud] += 1
  end
  outcome
end

rng = Random.new(20_261_005) # детерміновано: число в каноні відтворюється цією командою
seeds = Array.new(trees) { rng.bytes(32) }
control = seeds.map { |s| run_tree(seed: s, frames: frames, h: h, lost_at: -1) }
lossy   = seeds.map { |s| run_tree(seed: s, frames: frames, h: h, lost_at: lost_at) }

sum = ->(runs, key) { runs.sum { |r| r[key] } }
judged = trees * (frames - lost_at - 1)
per_frame = %i[false_fraud spurious_time_sync].to_h { |k| [ k, sum.(lossy, k).fdiv(judged) ] }
per_day = 24.0 / h

puts "dci_chain_loss — #{trees} дерев × #{frames} кадрів, каденс #{h} год (#{format('%.1f', per_day)} кадр/добу), " \
     "температура #{FIXED_TEMP ? "стала #{FIXED_TEMP} °C" : 'добова синусоїда 10 ± 8 °C'}"
puts "  контроль без втрат: fraud #{sum.(control, :false_fraud)} · time-sync #{sum.(control, :spurious_time_sync)} " \
     "(мусить бути 0/0 — інакше прилад міряє не розсинхрон)"
puts "  один втрачений кадр (k=#{lost_at}), на кадр після нього:"
puts format("    хибний P0 fraud        %.4f  ⇒ P(≥1 на дерево-добу) ≈ %.3f",
            per_frame[:false_fraud], 1 - (1 - per_frame[:false_fraud])**per_day)
puts format("    хибний time-sync (ARCH.41) %.4f  ⇒ P(≥1 на дерево-добу) ≈ %.3f",
            per_frame[:spurious_time_sync], 1 - (1 - per_frame[:spurious_time_sync])**per_day)
puts "    дерев без жодного прапорця: #{lossy.count { |r| r.values.sum.zero? }} із #{trees}"
exit((sum.(control, :false_fraud) + sum.(control, :spurious_time_sync)).zero? ? 0 : 1)
