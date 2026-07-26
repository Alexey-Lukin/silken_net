# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.31] Gate L (CRuby-плече): читає дамп mruby-VM (host_main/parity_core,
# IEEE-біти x/y/z на кейс), жене ТІ САМІ зчеплені кейси через СПРАВЖНІЙ
# firmware/bio_contracts/bio_contract.rb у CRuby (FW.57-ізоляція: контракт
# dependency-free, без Rails) і друкує |Δz|-розподіл.
#
# Кожна сторона ланцюжить ВЛАСНИЙ хвіст (x,y,z) — модель warm-chaining DCI:
# сервер продовжує зі свого збереженого tail, пристрій зі свого. Кейс-
# генератор бітово дзеркалить firmware/sim/parity_core.h (LCG + краєві піни).
#
# Бекендове дзеркало (app/services/silken_net/attractor.rb) транзитивно
# покрите 200-кейсовим fuzz'ом attractor_spec проти цього ж контракту.
#
# Виклик: tools/firmware/dci_epsilon_sweep.sh (будує і годує VM-дамп).

require_relative "../../firmware/bio_contracts/bio_contract"

EPSILON = 0.001 # дзеркало TelemetryUnpackerService::DEFAULT_DCI_EPSILON

dump_path = ARGV.fetch(0)
vm_cases = []
File.foreach(dump_path) do |line|
  next unless line.start_with?("C")
  m = line.match(/p=(\h{2}) x=(\h{16}) y=(\h{16}) z=(\h{16})/)
  raise "малформатний рядок дампу: #{line.inspect}" unless m
  payload = m[1].to_i(16)
  bits = [ m[2], m[3], m[4] ].map { |hex| [ hex ].pack("H*").unpack1("G") }
  vm_cases << [ payload, *bits ]
end
n = vm_cases.length
raise "порожній дамп" if n.zero?

# ── Дзеркало кейс-генератора parity_core.h ───────────────────────────────
lcg_state = 0x53494C4B # "SILK"
lcg = lambda do
  lcg_state = (lcg_state * 1_664_525 + 1_013_904_223) & 0xFFFFFFFF
  lcg_state
end
PIN_TEMP = [ 25.0, -40.0, 85.0, 0.0 ].freeze
PIN_AC   = [ 10.0, 0.0, 255.0, 128.0 ].freeze
PIN_DT   = [ 60.0, 0.0, 86_400.0, 30.0 ].freeze
PIN_VCAP = [ 3300.0, 1800.0, 5500.0, 4500.0 ].freeze

x = 1.0
y = 1.0
z = 1.0
abs_dz = []
bit_exact_z = 0
payload_mismatches = 0

n.times do |i|
  if i < 4
    temp, ac, dt, vcap = PIN_TEMP[i], PIN_AC[i], PIN_DT[i], PIN_VCAP[i]
  else
    temp = -40.0 + (lcg.call % 126)
    ac   = (lcg.call % 256).to_f
    dt   = (lcg.call % 7200).to_f
    vcap = 1800.0 + (lcg.call % 3700)
  end

  payload, x, y, z = SilkenNet::BioContract.evaluate_and_pack(x, y, z, temp, ac, dt, vcap)

  vm_payload, _vm_x, _vm_y, vm_z = vm_cases[i]
  payload_mismatches += 1 if payload != vm_payload
  abs_dz << (z - vm_z).abs
  bit_exact_z += 1 if [ z ].pack("G") == [ vm_z ].pack("G")
end

sorted = abs_dz.sort
pct = ->(q) { sorted[[ (n * q).floor, n - 1 ].min] }
max_dz = sorted.last

puts "── [FW.31] |Δz| mruby-VM ↔ CRuby(справжній контракт), N=#{n} зчеплених кейсів ──"
puts format("  бітово-точний z: %d/%d (%.2f%%)", bit_exact_z, n, 100.0 * bit_exact_z / n)
puts format("  payload (категоричний): %d розбіжностей", payload_mismatches)
puts format("  max|Δz|    = %.3e", max_dz)
puts format("  p50        = %.3e", pct.call(0.50))
puts format("  p99        = %.3e", pct.call(0.99))
puts format("  p99.9      = %.3e", pct.call(0.999))
puts format("  p99.99     = %.3e", pct.call(0.9999))
puts format("  ε (поточний DEFAULT_DCI_EPSILON) = %.0e → запас = %.1f порядків",
            EPSILON, Math.log10(EPSILON / [ max_dz, Float::MIN ].max))

if payload_mismatches.positive?
  puts "❌ категорична розбіжність — це знахідка рівня FW.7/E.63, неси у 00_07"
  exit 1
end
if max_dz >= EPSILON
  puts "❌ max|Δz| ≥ ε — ε=0.001 НЕ безпечний, дивись 03_04 §7.1 крок 6 (ARCH.18?)"
  exit 1
end
puts "✅ Gate L (статистична половина): ε=0.001 тримає; ARM-плече = 0 бітово (FW.55)"
