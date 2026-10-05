# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.66] Чи тримається теплий ланцюг DCI між пристроєм і сервером — і що робить сервер, коли ні.
#
# Сервер продовжує Лоренц від хвоста ОСТАННЬОГО ОТРИМАНОГО `TelemetryLog`
# (`TelemetryUnpackerService#previous_lorenz_state_for`), а пристрій — від стану в RTC після
# КОЖНОГО свого кроку. Паритет вимагає двох речей (`03_04 §5`): (а) однакової ТОЧНОСТІ стану між
# кадрами — Солдат тримає його у float32 (`float lorenz_x`, RTC DR16–DR18) і так само звужує
# cold-start, тож сервер мусить звужувати теж (`SilkenNet::Attractor.as_rtc_state`); (б) однакової
# КІЛЬКОСТІ кроків — кожен крок пристрою мусить дійти до сервера кадром. Прилад моделює обидві
# сторони на ОДНОМУ ядрі (`SilkenNet::Attractor`, бітово ≡ mruby з FW.7) і рахує, чим закінчується
# розбіжність: відновленням ARCH.41 (три cold-кандидати доби — дзеркало
# `TelemetryUnpackerService#try_time_sync_recovery`) або прапорцем fraud.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/dci_chain_loss.rb                  # сервер звужує (код після FW.66), один втрачений кадр
#   ruby tools/firmware/dci_chain_loss.rb server=double    # сервер у double — дефект ДО FW.66: розрив без жодної втрати
#   ruby tools/firmware/dci_chain_loss.rb h=1.731 frames=4000 trees=40 lost_at=-1
#   ruby tools/firmware/dci_chain_loss.rb temp=-10         # стала температура замість добової синусоїди
#   ruby tools/firmware/dci_chain_loss.rb claim=homeostasis lost_at=-1   # фальсифікатор: статус ВИБРАНО, не обчислено
#
# ⛔ СТЕЛІ, ОГОЛОШЕНІ ВГОЛОС:
#   • обидві сторони — СЕРВЕРНЕ ядро; паритет ядер mruby ⟷ CRuby — предмет Gate L
#     (`tools/firmware/dci_epsilon_sweep.sh`), а Gate L ланцюжить обидва боки в double, тобто
#     звуження між кадрами не бачить — його бачить цей прилад і пін `spec/lib/hil/soldier_node_spec.rb`;
#   • смуга — лише заводська (2.0 … 45.0, ρ-відносна стеля): набір кандидатів FW.8
#     (`Tree#device_lorenz_bands`) не моделюється, а розсинхронізований ланцюг ще й ПОДАЄ
#     хибні докази смуги (`record_band_evidence!`) — цього числа тут немає;
#   • температура — синтетична добова синусоїда 10 ± 8 °C: частка кадрів поза смугою залежить
#     від ρ(T), тож ставка — властивість цієї моделі, не поля; акустика 0 (пʼєзо зрізано, HW.30);
#   • «хибний time-sync» лічить СПРАЦЮВАННЯ відновлення; `TimeSyncDownlinkWorker` тротлінгу не
#     має, тож кожне — CoAP PUT і маяк Королеви, але ефірний час маяків тут не рахується;
#   • втрата — РІВНО ОДИН кадр; живі пускачі того самого роду (морозне відкладення TX після кроку,
#     VM_ERROR-кадр, на якому сервер крокує, а пристрій ні, перезапис CIFO Королеви, дублікат
#     кадру) і cold start пристрою, якого сервер не бачить, дають той самий розсинхрон, і жоден
#     наступний його не «лагодить».

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

params = { "h" => 1.81, "frames" => 2000, "trees" => 20, "lost_at" => 10, "temp" => nil, "server" => "float32",
           "claim" => "honest" }
ARGV.each do |arg|
  key, value = arg.split("=", 2)
  abort "невідомий параметр: #{arg}" unless params.key?(key) && value
  params[key] = case key
  when "h", "temp" then Float(value)
  when "server", "claim" then value
  else Integer(value)
  end
end
abort "server=float32|double" unless %w[float32 double].include?(params["server"])
abort "claim=honest|homeostasis" unless %w[honest homeostasis].include?(params["claim"])
FORGER = params["claim"] == "homeostasis" # грошовий напрям підробки: «я в гомеостазі» на КОЖНОМУ кадрі
h, frames, trees, lost_at = params.values_at("h", "frames", "trees", "lost_at")
FIXED_TEMP = params["temp"]
SERVER_NARROWS = params["server"] == "float32"

def in_band?(z, temp) = z >= BAND_MIN && z <= A.anomaly_ceiling(temp, BAND_MAX)
def temp_at(k, h) = FIXED_TEMP || (10.0 + 8.0 * Math.sin(2 * Math::PI * (k * h) / 24.0))
def device_state(xyz) = A.as_rtc_state(xyz)                       # Солдат: float32 між кадрами
def server_state(xyz) = SERVER_NARROWS ? A.as_rtc_state(xyz) : xyz

# Один ланцюг пари «пристрій ⟷ сервер». lost_at < 0 — без втрат.
def run_tree(seed:, frames:, h:, lost_at:)
  cold = SD.initial_state(seed, DAY0)
  device = device_state(cold)
  server = server_state(cold)
  outcome = Hash.new(0)
  frames.times do |k|
    temp = temp_at(k, h)
    day = DAY0 + ((k * h) / 24.0).floor
    _, dx, dy, dz = A.calculate_z_from_state(*device, temp, 0)
    device = device_state([ dx, dy, dz ])
    next if k == lost_at # кадр k загубився: пристрій крокнув, сервер його не бачив

    _, sx, sy, sz = A.calculate_z_from_state(*server, temp, 0)
    server = server_state([ sx, sy, sz ])
    device_in = FORGER || in_band?(dz, temp) # обидві сторони судять double-Z до звуження
    next if device_in == in_band?(sz, temp)

    recovered = [ day, day - 1, RTC_DEFAULT_EPOCH_DAY ].any? do |d|
      *, zc = A.calculate_z_from_state(*server_state(SD.initial_state(seed, d)), temp, 0)
      in_band?(zc, temp) == device_in
    end
    outcome[recovered ? :spurious_time_sync : :false_fraud] += 1
  end
  outcome
end

rng = Random.new(20_261_005) # детерміновано: число в каноні відтворюється цією командою
seeds = Array.new(trees) { rng.bytes(32) }
clean = seeds.map { |s| run_tree(seed: s, frames: frames, h: h, lost_at: -1) }
lossy = lost_at.negative? ? nil : seeds.map { |s| run_tree(seed: s, frames: frames, h: h, lost_at: lost_at) }

sum = ->(runs, key) { runs.sum { |r| r[key] } }
per_day = 24.0 / h
report = lambda do |runs, judged|
  %i[false_fraud spurious_time_sync].each do |key|
    p_frame = sum.(runs, key).fdiv(judged)
    puts format("    %-24s %.4f на кадр (%d із %d) ⇒ P(≥1 на дерево-добу) ≈ %.3f",
                key == :false_fraud ? "хибний P0 fraud" : "хибний time-sync (ARCH.41)",
                p_frame, sum.(runs, key), judged, 1 - (1 - p_frame)**per_day)
  end
  puts "    дерев без жодного прапорця: #{runs.count { |r| r.values.sum.zero? }} із #{trees} (горизонт #{format('%.0f', frames * h / 24.0)} діб)"
end

puts "dci_chain_loss — #{trees} дерев × #{frames} кадрів, каденс #{h} год (#{format('%.1f', per_day)} кадр/добу), " \
     "температура #{FIXED_TEMP ? "стала #{FIXED_TEMP} °C" : 'добова синусоїда 10 ± 8 °C'}, сервер #{params['server']}, статус #{FORGER ? 'ВИБРАНО homeostasis (фальсифікатор)' : 'обчислено'}"
puts "  без втрат:"
report.(clean, trees * frames)
if lossy
  puts "  один втрачений кадр (k=#{lost_at}), на кадри після нього:"
  report.(lossy, trees * (frames - lost_at - 1))
end
# Код виходу — вердикт про ТОЧНІСТЬ: при server=float32 без втрат ланцюги мусять збігатися.
exit(SERVER_NARROWS && !FORGER && (sum.(clean, :false_fraud) + sum.(clean, :spurious_time_sync)).positive? ? 1 : 0)
