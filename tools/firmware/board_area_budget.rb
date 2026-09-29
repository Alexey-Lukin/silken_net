#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [HW.9] Бюджет площі плати Солдата — другий прохід: КОРТЬЯРДИ, не корпуси.
# Канон (`02_01 §3.5`) друкує результат і посилається сюди; перелік деталей із
# джерелом кожного числа живе тут, бо сума в прозі не має чим себе перевиміряти.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/board_area_budget.rb                         # сторони · важелі · потрібний Ø
#   ruby tools/firmware/board_area_budget.rb --booster nn02_224 --edlc fc --diameter 21
#   ruby tools/firmware/board_area_budget.rb --assert     # модель ⟷ канон: два якорі + ціль контуру
#
# 🔑 Кортьярд — межа, за яку сусідня деталь не заходить (IPC-7351 nominal). Тож
# сума кортьярдів, більша за корисну площу сторони, означає «не розводиться ЗА
# ЖОДНОГО розведення», і рядок заповнення 100 % нижче є ПІДЛОГОЮ, а не прогнозом.
# Кортьярди типових корпусів — бібліотека KiCad (`kicad-footprints`, генератор за
# IPC-7351 nominal; межі шару F.CrtYd, зчитано 2026-09-29), вендорних — їхні
# креслення; джерело названо в кожному рядку.
#
# ⛔ СТЕЛІ, ОГОЛОШЕНІ ВГОЛОС — усе нижче тягне відповідь лише ВГОРУ:
#   • clearance-зона бустера не рахується: для землі нашого розміру числа немає
#     в жодній прочитаній публікації (`02_01 §5.2`: 40 × 12 для NN03-310,
#     20–60 × 11 для інших деталей) — рахується лише кортьярд самої деталі;
#   • отвори стійок між поверхами (`02_01 §5.3`), UART-пади BFU-лоадера (умовні,
#     `00_07` SEC.24) і тест-точки поза SWD не рахуються;
#   • поз. 19 (RF-тракт) — клас без P/N: оцінка кількості пасивів, не перелік;
#   • заповнення 70 / 60 % — наше прочитання щільності ручного розведення, НЕ
#     вимір; друкується, щоб показати чутливість, і вердикту не несе.

USABLE_EDGE_MM = 0.3      # відступ міді від краю — `02_01 §3.5`
CEILING_MM     = 15.17    # найслабша можлива стеля (комір 0.2, лише SLM) — `52` §collar_radial_budget
# Радіальний ланцюг купола, дзеркало `52` §rim_boss_radial_budget (правити в домі):
# стеля плати = Ø радома − 2 × 4.715 (стінка + прилив) − 2 × стінка коміра.
BOSS_BAND_MM   = 4.715
COLLAR_WALL_MM = 0.2
FILL_LEVELS    = [ 1.0, 0.7, 0.6 ].freeze

def rect(w, h) = w * h
def disc(d) = Math::PI / 4 * d * d
C0402 = rect(1.82, 0.92)  # KiCad C_0402_1005Metric
R0402 = rect(1.86, 0.94)  # KiCad R_0402_1005Metric
C0603 = rect(2.96, 1.46)  # KiCad C_0603_1608Metric
SOT23_6 = rect(4.10, 3.40) # KiCad SOT-23-6 — TPS22860 лише DBV: єдиний orderable (TI SLVSD04, addendum 10-11-2025)

# ⚖️ founder 2026-09-29 (`02_01 §6`): пʼєзо з Солдата зрізано — поз. 5 (пʼєзо) і поз. 6 (кламп BAT54S
# + DNP-поріг перед EXTI) на платі немає. Бустер носія не має (поз. 4), а контур креслять під ОБВІДНУ
# обох кандидатів — більший NN02-224 (⚖️ делеговано 2026-09-29, `00_07` HW.33; врізка `02_01 §3.5`):
# тож дефолт нижче — рішення присуду, а не CLI (in-silico §Critical Rules #9), а сусідній кандидат
# друкується поруч рядком `бустер — теж вхід цілі`.
BOOSTER = { # поз. 4 — корпус + 0.25 на бік; дві родини, що габаритно влазять (`02_01 §5.2`)
  "nn02_201" => [ "Ignion NN02-201 7.0 × 3.0", rect(7.50, 3.50) ],
  "nn02_224" => [ "Ignion NN02-224 12.0 × 3.0", rect(12.50, 3.50) ]
}.freeze
# ⚖️ founder 2026-09-29 (02_03 §12.1): обрано `kr` з автоматизованою пайкою виводів; `fc` ВІДХИЛЕНО, але
# лишається — його рядок і є доказом, на якому стоїть відмова (квадратна основа → геометрична ціль).
EDLC = { # поз. 3 — [назва, низ RF Deck, пади на верху RF Deck]
  # Диск Ø11.5 + 0.25 на бік, виводи до W1 12.4, отвори Ø1.10 + кільце 0.35 (Eaton TD 4327).
  "kr" => [ "EDLC Eaton KR-5R5H474-R, горизонтальний THT, reflow заборонено", disc(12.0) + (2 * rect(1.30, 0.45)), 2 * disc(2.30) ],
  # Основа 16.3 × 16.3 + 0.25 на бік; H 9.5 — лише за B2B 10 (KEMET S6011_FC, 2026-02-13).
  "fc" => [ "EDLC KEMET FC0H474ZFTBR32-SS, SMD лише reflow, −40…+85 °C, H 9.5 — лише за B2B 10", rect(16.80, 16.80), 0.0 ]
}.freeze
B2B = { # поз. 12 — Samtec FW-D-SM Rev D: розмах падів 6.86, контур 6.35 · CLP-1XX-D Rev W: корпус 6.78 × 3.05, пади 4.70
  header: rect(6.85, 7.36),
  socket: rect(7.28, 5.20)
}.freeze

def parts(booster:, rigid_flex:, edlc: "kr")
  power = [
    [ "BQ25570 VQFN-20 3.5 × 3.5 (поз. 2; KiCad QFN-20-1EP_3.5x3.5mm)", rect(4.76, 4.76) ],
    [ "L1 22 µH Coilcraft LPS4018 (поз. 15; рекомендація TI)", rect(4.90, 4.40) ],
    [ "L2 10 µH Toko DFE252012C (поз. 15; проксі KiCad L_1008_2520Metric)", rect(3.90, 2.70) ],
    [ "буфер 47 µF 1210 (поз. 9)", rect(4.60, 3.20) ],
    [ "CIN · CSTOR 4.7 µF 0603 × 2 (SLUSBH2G §8.2: мінімум)", 2 * C0603 ],
    [ "CREF 10 nF · CBYP 0.01 µF 0402 × 2 (SLUSBH2G §8.2)", 2 * C0402 ],
    [ "дільники 0402 × 9 (поз. 10; `02_03 §5`)", 9 * R0402 ],
    [ "OVP: TLV840 SOT-23-5 + DMN2990UFA (проксі SOT-1123) + 0402 × 2 (поз. 14)", rect(4.10, 3.40) + rect(1.70, 1.10) + 2 * R0402 ]
  ]
  rf_bottom = [ [ EDLC.fetch(edlc)[0] + " (поз. 3)", EDLC.fetch(edlc)[1] ] ]
  unless rigid_flex
    power << [ "B2B header Samtec FW-SM 2 × 5 (поз. 12)", B2B[:header] ]
    rf_bottom << [ "B2B socket Samtec CLP 2 × 5 (поз. 12)", B2B[:socket] ]
  end
  rf_top = [
    [ "STM32WLE5CC UFQFPN48 (поз. 1; KiCad QFN-48-1EP_7x7mm)", rect(8.26, 8.26) ],
    [ "розвʼязка DS13105 Rev 12 рис. 14: 0402 × 3 + 0603 × 2", 3 * C0402 + 2 * C0603 ],
    [ "TCXO NT2016SF (поз. 16; проксі Crystal_SMD_2016-4Pin) + 0402 × 3", rect(3.00, 2.60) + 3 * C0402 ],
    [ "LSE-кварц клас 2012 (поз. 17, P/N не обрано) + 0402 × 2", rect(3.00, 2.20) + 2 * C0402 ],
    [ "SMPS MLZ2012M150W 0805 + 470 nF 0603 (поз. 18)", rect(3.50, 1.70) + C0603 ],
    [ "RF-тракт — КЛАС: ≈ 11 × 0402 + SPDT WSON-6 1.5 × 1.5 (поз. 19)", 11 * C0402 + rect(2.40, 2.04) ],
    [ BOOSTER.fetch(booster)[0] + " + П-ланка 0402 × 3 (поз. 4)", BOOSTER.fetch(booster)[1] + 3 * C0402 ],
    [ "BME280 LGA-8 2.5 × 2.5 + 0402 × 2 (поз. 20)", rect(2.82, 3.08) + 2 * C0402 ],
    [ "ключ BME280 TPS22860 SOT-23-6 (поз. 21)", SOT23_6 ],
    [ "SE05x DNP (проксі QFN-20 3 × 3) + 0402 × 3 (поз. 13)", rect(4.26, 4.26) + 3 * C0402 ],
    [ "ключ Vcap-sense TPS22860 SOT-23-6 + 0402 × 2 (поз. 23)", SOT23_6 + 2 * R0402 ],
    [ "SWD-пади × 5, Ø1.0 (⚖️ 2026-09-27: на всіх платах серії)", 5 * rect(1.50, 1.50) ]
  ]
  rf_top << [ "пади THT-виводів EDLC × 2 (поз. 3)", EDLC.fetch(edlc)[2] ] if EDLC.fetch(edlc)[2].positive?
  { "Power Deck, верх" => power, "RF Deck, низ" => rf_bottom, "RF Deck, верх" => rf_top }
end

def usable(d) = disc(d - (2 * USABLE_EDGE_MM))
def diameter_for(area) = (2 * Math.sqrt(area / Math::PI)) + (2 * USABLE_EDGE_MM)
def radome_for(board_d) = board_d + (2 * BOSS_BAND_MM) + (2 * COLLAR_WALL_MM)
def sums(sides) = sides.transform_values { |rows| rows.sum { |_, a| a } }

def report_sides(sides, diameter)
  u = usable(diameter)
  sums(sides).each do |side, total|
    puts format("  %-18s %7.1f мм² із %.1f → %4.0f %%", side, total, u, 100 * total / u)
  end
  total = sums(sides).values.sum
  puts format("  %-18s %7.1f мм² із %.1f → %4.0f %%", "усі три сторони", total, 3 * u, 100 * total / (3 * u))
end

def required(sides)
  s = sums(sides)
  FILL_LEVELS.map do |fill|
    bind = diameter_for(s.values.max / fill)
    even = diameter_for(s.values.sum / 3 / fill)
    format("заповнення %3.0f %%: без перенесення між сторонами Ø%.1f · з вільним перенесенням Ø%.1f (радом ≈ Ø%.1f)",
           100 * fill, bind, even, radome_for(even))
  end
end

# Геометрична підлога низу RF Deck (in-silico §Critical Rules #11: деталь судиться на КОЖНІЙ осі
# оболонки). EDLC і сокет B2B стоять на ОДНІЙ стороні, і сума площ цього не бачить: квадрат основи FC
# потребує кола з його діагоналлю, а сокет — сегмента біля краю EDLC. Центр EDLC зсувається від центру
# плати на s, сокет прикладено з протилежного боку; s підбирається. Фаски основи FC вендор не нормує
# (креслення S6011_FC: фаски на двох кутах без розміру), тож квадрат — повний, тобто верхня межа.
EDLC_SHAPE = { "kr" => [ :disc, 6.0, 6.45 ],     # Ø12.0 з кортьярдом, виводи до W1 12.4 + 0.5
               "fc" => [ :square, 8.4, 8.4 ] }.freeze # основа 16.3 × 16.3 + 0.25 на бік
SOCKET_EXTENT = [ 5.20, 3.64 ].freeze            # CLP з кортьярдом: радіально · половина вздовж краю

def geometric_floor(edlc, socket:)
  kind, half, reach = EDLC_SHAPE.fetch(edlc)
  radius = (0..6000).map do |i|
    s = i / 1000.0
    pts = kind == :disc ? [ [ -s - half, 0.0 ], [ -s, reach ] ] : [ [ -s - half, half ], [ -s + half, half ] ]
    pts << [ -s + half + SOCKET_EXTENT[0], SOCKET_EXTENT[1] ] if socket
    pts.map { |x, y| Math.hypot(x, y) }.max
  end.min
  (2 * radius) + (2 * USABLE_EDGE_MM)
end

# Ціль контуру = більше з двох осей: площа за 70 % заповнення (рівномірно по трьох сторонах) ·
# геометрична підлога. ⚠️ Бустер — теж її вхід: носія немає (поз. 4), тож ціль береться під обвідну.
def target_for(booster:, edlc:, rigid_flex:)
  area = diameter_for(sums(parts(booster:, edlc:, rigid_flex:)).values.sum / 3 / 0.7)
  [ area, geometric_floor(edlc, socket: !rigid_flex) ]
end

# Самоперевірка. Якорі — ДВА числа, яких модель не вигадувала: корисна площа першого проходу й
# ратифікований Ø25 радома на тій самій стелі. Решта — не якорі, а ДЗЕРКАЛА: канон цитує вихід
# моделі, тож пін ловить дрейф канону від моделі, але не помилку самої моделі.
if ARGV == [ "--assert" ]
  near = ->(value, canon) { (value - canon).abs < 0.05 }
  target = ->(booster, rigid) { target_for(booster:, edlc: "kr", rigid_flex: rigid).max }
  checks = {
    "корисна площа на Ø15.17 = 166.7 мм² (`02_01 §3.5`, перший прохід)" => near.(usable(CEILING_MM), 166.7),
    "стеля Ø15.17 ⟷ радом Ø25 (`52` §rim_boss_radial_budget)" => (radome_for(CEILING_MM) - 25.0).abs < 1e-9,
    "ціль kr · nn02_224 (обвідна бустерів, ⚖️ HW.33): пара B2B Ø19.5, rigid-flex Ø18.1 (`02_01 §3.5`)" =>
      near.(target.("nn02_224", false), 19.5) && near.(target.("nn02_224", true), 18.1),
    "сусідній кандидат, kr · nn02_201: пара B2B Ø19.3, rigid-flex Ø17.8 (`02_01 §3.5`, ціна обвідної)" =>
      near.(target.("nn02_201", false), 19.3) && near.(target.("nn02_201", true), 17.8)
  }
  checks.each { |name, ok| puts "#{ok ? 'OK  ' : 'FAIL'} #{name}" }
  exit(checks.values.all? ? 0 : 1)
end

opts = { booster: "nn02_224", edlc: "kr", diameter: CEILING_MM }
ARGV.each_slice(2) do |flag, value|
  case flag
  when "--booster" then opts[:booster] = value
  when "--edlc" then opts[:edlc] = value
  when "--diameter" then opts[:diameter] = Float(value)
  else abort "Usage: #{$PROGRAM_NAME} [--booster #{BOOSTER.keys.join('|')}] [--edlc #{EDLC.keys.join('|')}] [--diameter мм]"
  end
end
abort "невідомий --booster" unless BOOSTER.key?(opts[:booster])
abort "невідомий --edlc" unless EDLC.key?(opts[:edlc])
variant = opts.slice(:booster, :edlc)

base = parts(**variant, rigid_flex: false)
puts "Бюджет площі плати Солдата — кортьярди (HW.9, другий прохід)"
puts format("Контур Ø%.2f → корисна площа сторони %.1f мм² (відступ міді %.1f мм)",
            opts[:diameter], usable(opts[:diameter]), USABLE_EDGE_MM)
puts
base.each do |side, rows|
  puts "#{side}:"
  rows.each { |name, area| puts format("  %6.1f  %s", area, name) }
end
puts
puts "Сума кортьярдів проти корисної площі:"
report_sides(base, opts[:diameter])

puts
puts "Важелі (кожен — окремо, на контурі Ø#{opts[:diameter]}):"
flex = parts(**variant, rigid_flex: true)
puts format("  rigid-flex замість пари B2B: усе %.0f %% (−%.1f мм²)",
            100 * sums(flex).values.sum / (3 * usable(opts[:diameter])), B2B.values.sum)
third = sums(base).values.sum + B2B.values.sum
puts format("  третій поверх (+2 сторони, +друга пара B2B): %.0f %% за площею; вертикаль — `52`: над RF Deck лишається 4.15 мм, а друга пара FW/CLP забирає ≥ 1.6 + 7.72",
            100 * third / (5 * usable(opts[:diameter])))

puts
puts "Корінь — який контур закриває (Ø плати; радом за незмінних приливу #{BOSS_BAND_MM} і коміра #{COLLAR_WALL_MM}):"
puts "  пара B2B:"
required(base).each { |line| puts "    #{line}" }
puts "  rigid-flex:"
required(flex).each { |line| puts "    #{line}" }

puts
puts "Ціль контуру = більше з двох: площа (70 % заповнення, рівномірно) · геометрія низу RF Deck; бустер #{opts[:booster]}:"
EDLC.each_key do |key|
  [ [ "пара B2B", false ], [ "rigid-flex", true ] ].each do |label, rigid|
    area, geo = target_for(**variant, edlc: key, rigid_flex: rigid)
    target = [ area, geo ].max
    puts format("  %-3s %-10s площа Ø%.1f · геометрія Ø%.1f → Ø%.1f (радом ≈ Ø%.1f)",
                key, label, area, geo, target, radome_for(target))
  end
end
sweep = BOOSTER.keys.map do |key|
  pair = [ false, true ].map { |rigid| target_for(booster: key, edlc: opts[:edlc], rigid_flex: rigid).max }
  format("%s пара B2B Ø%.1f (радом ≈ Ø%.1f) / rigid-flex Ø%.1f", key, pair[0], radome_for(pair[0]), pair[1])
end
puts "  бустер — теж вхід цілі (поз. 4 без носія; контур — під обвідну, ⚖️ HW.33), #{opts[:edlc]}: #{sweep.join(' · ')}"
