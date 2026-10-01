#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [HW.7] Резистивні дільники BQ25570 — обчислювальний дім порогів. Канон
# (`02_03 §4`/`§5`) друкує РЕЗУЛЬТАТ і посилається сюди; рівняння й вибір E96
# живуть тут, бо число в прозі не має чим себе перевиміряти.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/bq25570_dividers.rb            # таблиця порогів + допуски
#   ruby tools/firmware/bq25570_dividers.rb --assert    # гейт: рівняння ⟷ TI-приклади
#   ruby tools/firmware/bq25570_dividers.rb --in-circuit [rov1=…]  # що покаже мультиметр на плечі В СХЕМІ
#
# 🔑 ЧОМУ ЦЕЙ ФАЙЛ САМОВАЛІДНИЙ, і це не оздоба. Рівняння взяті не з памʼяті, а з
# SLUSBH2G (MARCH 2013 – REVISED MARCH 2019). Доказ, що взяті правильно, — не
# цитата, а АРИФМЕТИКА: `--assert` проганяє ТРИ worked-приклади самого TI
# (§8.2.1/§8.2.2/§8.2.3) через ці ж функції й вимагає збігу з надрукованими там
# порогами. Зміни константу — приклади розійдуться. Тобто зелений `--assert` є
# твердженням про DATASHEET, а не про автора.
#
# 🔴 ЩО САМЕ ЦЕ ВИПРАВИЛО (провенанс, не хроніка): канон до 2026-09-09 застосовував
# ОДНУ generic-формулу дільника `V = VBIAS × (1 + R_up/R_low)` до всіх чотирьох
# порогів. Для OK/OUT вона правильна; для OV — ні: Equation (2) несе множник 3/2,
# і лише на OV. Наслідок був не косметичний — пара `16.9/4.75 МΩ` давала не 5.52 В,
# а 8.27 В, тобто overvoltage-захист іоністора 0.47F/5.5 В не спрацьовував НІКОЛИ
# при VSTOR(ABS MAX) = 5.5 В.
#
# ⛔ СТЕЛІ, ОГОЛОШЕНІ ВГОЛОС — інакше зелений прогін почне означати «не перевірено»:
#   • Скрипт рахує НОМІНАЛИ й ДОПУСКИ. Він не знає, які резистори стоять на
#     конкретній платі — `CJMCU-2557` приходить із Li-Po-дефолтом, і звірка з
#     залізом лишається 👤-заміром мультиметром (`00_07` HW.7).
#   • `VBAT_UV` НЕ програмується на BQ25570 (§7.3.2: internally set, 1.95 В typ) —
#     тут він друкується як константа кремнію, і жодних `RUV*` не існує.
#   • Скрипт рахує ВІДНОШЕННЯ й ПОРОГИ; він не моделює струм спокою дільників,
#     а той різний за побудовою: `ROV`/`ROK`/`ROUT` живить ІМПУЛЬСНИЙ `VRDIV`
#     (пульс кожні 64 мс), а `ROC` висить на `VIN_DC` ПОСТІЙНО — звідси й різні
#     рекомендовані суми (18–22 проти 11–15 МΩ). Вузол `ROC` розсуджено на
#     користь `VIN_DC` (`02_03 §4.А`), попри те що §7.3.1 datasheet каже `VRDIV`.
#   • Смуга «worst-case» нижче — це `VBAT_ACCURACY` ±2 % із паспорта, і вона
#     оголошена ДЛЯ 0.1 %-резисторів. На наших 1 % вона є НИЖНЬОЮ оцінкою — смугу
#     1 % E96 друкує окремий блок (`e96_band`: worst-case ⊕ RSS). Це смуга ПАРТІЇ;
#     мультиметр на стенді дає поріг однієї плати, і смуги не замінює.

# ── Константи кремнію (SLUSBH2G, Electrical Characteristics) ──────────────────
VBIAS_MIN = 1.205
VBIAS_TYP = 1.210
VBIAS_MAX = 1.217

VSTOR_ABS_MAX_V = 5.5           # Absolute Maximum Ratings + Figure 21
VBAT_OV_RANGE = (2.2..5.5)      # програмований діапазон
VBAT_UV_TYP_V = 1.95            # ⛔ ВНУТРІШНІЙ, не програмований (§7.3.2)
VBAT_UV_MIN_V = 1.91
VBAT_UV_MAX_V = 2.00
VBAT_ACCURACY = 0.02            # ±2 % для VBAT_OV/VBAT_OK ПРИ 0.1 % резисторах
# Допуск НАШИХ резисторів — 1 % E96 (BOM `02_01 §3` поз. 10; дзеркало, правити в домі).
RESISTOR_TOL = 0.01

# ── Дзеркала канону, потрібні лише щоб НАЗВАТИ ціну опції ─────────────────────
# ⚠️ Обидва — дзеркала, правити в домі: ємність EDLC → `02_03 §12.1`,
# робоче вікно → `02_03 §8` (від V_OK_ON; повне вікно OV→OFF — §9.8а). Тут вони не є SSOT і вживаються рівно для того,
# щоб таблиця опцій друкувала Δ до чинного бюджету, а не голу напругу.
EDLC_FARAD = 0.47
CANON_WINDOW_J = 4.39

# Рекомендовані суми плечей (Recommended Operating Conditions, МΩ): min/typ/max
RSUM_SPEC = {
  ov: [ 11, 13, 15 ],
  ok: [ 11, 13, 15 ],
  out: [ 11, 13, 15 ],
  oc: [ 18, 20, 22 ]
}.freeze

# ── Рівняння datasheet. Індекс 1 = НИЖНЄ плече (до GND), НАЙВИЩИЙ = ВЕРХНЄ ──
# ⚠️ Ця конвенція протилежна до тієї, що стояла в каноні до 2026-09-09, і саме
# вона є конвенцією TI. Тримати її дослівно — дешевша ціна, ніж перекладати.
# ⚠️ На трьохплечому OK-стеку верхнє плече — rok3, не rok2 (rok2 середнє,
# до жодної шини не торкається); функції нижче вже кодують це правильно —
# лише коментар над ними доти брехав.
module Bq25570
  module_function

  # Equation (2) — ЄДИНИЙ поріг серії з множником 3/2.
  def vbat_ov(rov1, rov2, vbias: VBIAS_TYP) = 1.5 * vbias * (1 + rov2.to_f / rov1)

  # Equation (3) — поріг при СПАДАННІ напруги (тобто OFF для системного навантаження).
  def vbat_ok_prog(rok1, rok2, vbias: VBIAS_TYP) = vbias * (1 + rok2.to_f / rok1)

  # Equation (4) — поріг при ЗРОСТАННІ (ON). Без `ROK3` дорівнює (3) ⇒ гістерезис = 0.
  def vbat_ok_hyst(rok1, rok2, rok3, vbias: VBIAS_TYP) = vbias * (1 + (rok2.to_f + rok3) / rok1)

  # Equation (5) — вихід buck-конвертера.
  def vout(rout1, rout2, vbias: VBIAS_TYP) = vbias * (1 + rout2.to_f / rout1)

  # Equation (1) — частка VOC, на якій тримається MPPT.
  def mppt_fraction(roc1, roc2) = roc1.to_f / (roc1 + roc2)
end

# ── E96 (1 %) ─────────────────────────────────────────────────────────────────
E96_MANTISSAS = [
  100, 102, 105, 107, 110, 113, 115, 118, 121, 124, 127, 130, 133, 137, 140, 143,
  147, 150, 154, 158, 162, 165, 169, 174, 178, 182, 187, 191, 196, 200, 205, 210,
  215, 221, 226, 232, 237, 243, 249, 255, 261, 267, 274, 280, 287, 294, 301, 309,
  316, 324, 332, 340, 348, 357, 365, 374, 383, 392, 402, 412, 422, 432, 442, 453,
  464, 475, 487, 499, 511, 523, 536, 549, 562, 576, 590, 604, 619, 634, 649, 665,
  681, 698, 715, 732, 750, 768, 787, 806, 825, 845, 866, 887, 909, 931, 953, 976
].freeze

# Значення E96 у МΩ, у діапазоні, придатному для цих дільників (0.1 .. 20 МΩ).
E96_MOHM = (-1..1).flat_map { |dec| E96_MANTISSAS.map { |m| (m * (10.0**dec) / 100.0).round(3) } }
                  .select { |v| v.between?(0.1, 20.0) }.sort.freeze

def e96_nearest(value) = E96_MOHM.min_by { |v| (Math.log(v) - Math.log(value)).abs }

# ── Самоперевірка: worked-приклади SLUSBH2G ───────────────────────────────────
# Кожен рядок — [опис, лямбда, надруковане в datasheet значення, допуск].
TI_EXAMPLES = [
  [ "§8.2.1 OV 4.2 В  (ROV1=5.62 ROV2=7.32)", -> { Bq25570.vbat_ov(5.62, 7.32) }, 4.18, 0.01 ],
  [ "§8.2.2 OV 5.0 В  (ROV1=4.75 ROV2=8.25)", -> { Bq25570.vbat_ov(4.75, 8.25) }, 4.97, 0.01 ],
  [ "§8.2.3 OV 3.3 В  (ROV1=7.15 ROV2=5.90)", -> { Bq25570.vbat_ov(7.15, 5.90) }, 3.31, 0.01 ],
  [ "§8.2.3 OK_PROG   (ROK1=4.99 ROK2=6.65)", -> { Bq25570.vbat_ok_prog(4.99, 6.65) }, 2.82, 0.01 ],
  [ "§8.2.3 OK_HYST   (+ROK3=1.24)", -> { Bq25570.vbat_ok_hyst(4.99, 6.65, 1.24) }, 3.12, 0.01 ],
  [ "§8.2.3 VOUT 1.8 В (ROUT1=8.66 ROUT2=4.22)", -> { Bq25570.vout(8.66, 4.22) }, 1.80, 0.01 ],
  [ "§8.2.3 MPPT 40 %  (ROC1=8.06 ROC2=12.0)", -> { Bq25570.mppt_fraction(8.06, 12.0) * 100 }, 40.0, 0.5 ]
].freeze

# Спростована формула — тримається як НЕГАТИВНИЙ контроль: `--assert` вимагає, щоб
# вона НЕ відтворювала жодного OV-прикладу. Без цього рядка зелений прогін не
# розрізняв би «формула правильна» і «обидві формули збігаються».
def refuted_ov(rov1, rov2, vbias: VBIAS_TYP) = vbias * (1 + rov2.to_f / rov1)

# ── Наш набір: цілі оголошені каноном `02_03 §4`, номінали виводяться тут ──────
def solve_ov(target_v, rsum_mohm: RSUM_SPEC[:ov][1])
  lo, _typ, hi = RSUM_SPEC[:ov]
  ratio = target_v / (1.5 * VBIAS_TYP) - 1                 # ROV2/ROV1
  # ⚠️ Поріг ЗАХИСТУ вгору не зсуваємо: беремо лише пари, що НЕ перевищують ціль.
  # Тай-брейк — близькість Σ до рекомендованої: менша сума = більший струм спокою
  # через дільник, а він тут постійна стаття бюджету, не похибка.
  cands = E96_MOHM.filter_map do |rov1|
    rov2 = e96_nearest(rov1 * ratio)
    sum = rov1 + rov2
    next unless sum.between?(lo, hi)
    v = Bq25570.vbat_ov(rov1, rov2)
    next if v > target_v
    [ [ target_v - v, (sum - rsum_mohm).abs ], [ rov1, rov2 ] ]
  end
  cands.min_by(&:first)&.last || [ e96_nearest(rsum_mohm / (1 + ratio)), e96_nearest(rsum_mohm * ratio / (1 + ratio)) ]
end

def solve_ok(off_v, on_v, rsum_mohm: RSUM_SPEC[:ok][1])
  rok1 = e96_nearest(VBIAS_TYP / off_v * rsum_mohm)
  rok2 = e96_nearest(rok1 * (off_v / VBIAS_TYP - 1))
  rok3 = e96_nearest(rok1 * (on_v / VBIAS_TYP - 1) - rok2)
  [ rok1, rok2, rok3 ]
end

def solve_out(target_v, rsum_mohm: RSUM_SPEC[:out][1])
  rout1 = e96_nearest(VBIAS_TYP / target_v * rsum_mohm)
  [ rout1, e96_nearest(rsum_mohm - rout1) ]
end

def solve_mppt(fraction, rsum_mohm: RSUM_SPEC[:oc][1])
  roc1 = e96_nearest(fraction * rsum_mohm)
  [ roc1, e96_nearest(rsum_mohm - roc1) ]
end

# ── Режими ────────────────────────────────────────────────────────────────────
def assert_mode
  failures = TI_EXAMPLES.reject { |_, fn, want, tol| (fn.call - want).abs <= tol }
  failures.each { |name, fn, want, _| warn "FAIL  #{name}: очікувано #{want}, обчислено #{'%.4f' % fn.call}" }

  # Негативний контроль: спростована формула НЕ сміє відтворити жодного OV-прикладу.
  leaks = [ [ 5.62, 7.32, 4.18 ], [ 4.75, 8.25, 4.97 ], [ 7.15, 5.90, 3.31 ] ]
          .select { |r1, r2, want| (refuted_ov(r1, r2) - want).abs <= 0.01 }
  leaks.each { |r1, r2, want| warn "FAIL  негативний контроль: спростована формула відтворила #{want} В на #{r1}/#{r2}" }

  drift = e96_band_drift
  drift.each { |d| warn "FAIL  смуга 1 % E96 — #{d}" }

  circuit = in_circuit_drift
  circuit.each { |d| warn "FAIL  режим «у схемі» — #{d}" }

  ok = failures.empty? && leaks.empty? && drift.empty? && circuit.empty?
  puts ok ? "OK  #{TI_EXAMPLES.size} worked-прикладів SLUSBH2G відтворено; спростована формула не відтворює жодного; " \
            "смуга 1 % E96 ≡ перебір кутів і похідні; плечі «у схемі» ≡ закрита форма" : "RED"
  exit(ok ? 0 : 1)
end

# Закрита форма `e96_band` ⟷ ті самі рівняння іншим шляхом: worst-case — перебір усіх
# кутів допуску, RSS — центральні похідні. До 2026-09-27 RSS брав найгірше відношення
# плечей одним членом (2.36 % замість 2.19 %) — цей звір тоді почервонів би.
def e96_band_drift
  t = RESISTOR_TOL
  [ [ "VBAT_OV", ->(rs) { Bq25570.vbat_ov(*rs) }, [ 4.75, 7.87 ] ],
    [ "VBAT_OK ON", ->(rs) { Bq25570.vbat_ok_hyst(*rs) }, solve_ok(3.3, 3.4) ] ].filter_map do |name, f, rs|
    v0 = f.call(rs)
    b = e96_band(v0, *rs)
    corners = [ -1, 1 ].repeated_permutation(rs.size).map { |s| f.call(rs.zip(s).map { |r, d| r * (1 + (d * t)) }) / v0 - 1 }
    sens = rs.each_index.map do |i|
      up, dn = [ 1, -1 ].map { |d| rs.each_with_index.map { |r, j| j == i ? r * (1 + (d * 1e-6)) : r } }
      (f.call(up) - f.call(dn)) / (2e-6 * v0)
    end
    rss = Math.sqrt((VBAT_ACCURACY**2) + ((t**2) * sens.sum { |s| s**2 }))
    next if (corners.max - b[:arms]).abs < 1e-9 && corners.min >= -b[:arms] && (rss - b[:rss]).abs < 1e-6
    format("%s: закрита форма плечі ±%.4f %% · RSS ±%.4f %%, а перебір кутів +%.4f %% · похідні RSS ±%.4f %%",
           name, b[:arms] * 100, b[:rss] * 100, corners.max * 100, rss * 100)
  end
end

def band(nominal) = [ nominal * (1 - VBAT_ACCURACY), nominal * (1 + VBAT_ACCURACY) ]

# Внесок допуску резисторів у поріг дільника `V ∝ ΣR / R_low`. Worst-case: верхні плечі
# на +t, нижнє на −t — множник зсувається на k·((1+t)/(1−t) − 1), k = ΣR_up/ΣR. RSS:
# кожен РЕЗИСТОР — окреме незалежне джерело з чутливістю R_i/ΣR (верхні) і k (нижнє),
# а не найгірше відношення плечей одним членом. Worst-case — строга межа лише за ПОЧАТКОВИМ допуском
# (TCR, дрейф і витоки на 12.6 МΩ не моделюються); RSS — оцінка
# (незалежні джерела, допуски як межі одного рівня довіри), і Monte-Carlo лише уточнив
# би її формою розподілів, за worst-case не вийшовши. ⚠️ Паспортні ±2 % уже несуть внесок
# 0.1 %-резисторів, тож обидві суми трохи ПЕРЕраховують — консервативно.
def e96_band(nominal, low, *ups, tol: RESISTOR_TOL)
  sum = low + ups.sum
  k = ups.sum / sum
  arms = k * (((1 + tol) / (1 - tol)) - 1)
  wc = VBAT_ACCURACY + arms
  rss = Math.sqrt((VBAT_ACCURACY**2) + ((tol**2) * ((k**2) + ups.sum { |u| (u / sum)**2 })))
  { arms:, wc:, rss:, wc_band: [ nominal * (1 - wc), nominal * (1 + wc) ], rss_band: [ nominal * (1 - rss), nominal * (1 + rss) ] }
end

def report
  puts "BQ25570 — резистивні дільники (SLUSBH2G, MARCH 2019). Індекс 1 = НИЖНЄ плече (→GND)."
  puts "VBIAS = #{VBIAS_MIN}/#{VBIAS_TYP}/#{VBIAS_MAX} В · VSTOR(ABS MAX) = #{VSTOR_ABS_MAX_V} В"
  puts

  # ⚠️ РАТИФІКОВАНО founder 2026-09-09 (Derate, HW.37) — пара ЗАФІКСОВАНА, не
  # передеривається з `solve_ov` щоразу: `solve_ov(4.822)` auto-добирає ІНШУ
  # валідну пару (5.62/9.31, сума ближче до стелі 15 МΩ), що дає той самий
  # V_OV з точністю 0.3 мВ — обидві коректні, канонізовано САМЕ цю (сума 12.62
  # МΩ, ближче до "typ" 13 з Recommended Operating Conditions). Хардкод тут —
  # свідомий: report() показує ЩО ВЖЕ ВИБРАНО й запаяно, не що можна вибрати
  # (guard-craft #113: мутація-доказ є твердженням про ЦЕЙ виклик, не про
  # функцію взагалі — тут звірено окремо, щоб report() і --check-canon
  # рахували ОДНУ й ту саму пару, а не дві правдиві-кожна-по-собі).
  ov1, ov2 = 4.75, 7.87
  ov = Bq25570.vbat_ov(ov1, ov2)
  ok1, ok2, ok3 = solve_ok(3.3, 3.4)
  out1, out2 = solve_out(3.3)
  oc1, oc2 = solve_mppt(0.65)

  rows = [
    [ "VBAT_OV  (Eq.2, ×3/2)", "ROV1=#{ov1} ROV2=#{ov2}", ov, "⚖️ ратифіковано 4.82", ov1 + ov2, RSUM_SPEC[:ov] ],
    [ "VBAT_OK_PROG (Eq.3, спад)", "ROK1=#{ok1} ROK2=#{ok2}", Bq25570.vbat_ok_prog(ok1, ok2), "3.3", ok1 + ok2 + ok3, RSUM_SPEC[:ok] ],
    [ "VBAT_OK_HYST (Eq.4, зрост.)", "+ROK3=#{ok3}", Bq25570.vbat_ok_hyst(ok1, ok2, ok3), "3.4", ok1 + ok2 + ok3, RSUM_SPEC[:ok] ],
    [ "VOUT     (Eq.5)", "ROUT1=#{out1} ROUT2=#{out2}", Bq25570.vout(out1, out2), "3.3", out1 + out2, RSUM_SPEC[:out] ],
    [ "MPPT     (Eq.1)", "ROC1=#{oc1} ROC2=#{oc2}", Bq25570.mppt_fraction(oc1, oc2) * 100, "65 %", oc1 + oc2, RSUM_SPEC[:oc] ]
  ]
  printf("%-28s %-26s %10s %12s %10s\n", "поріг", "номінали (МΩ)", "розрах.", "ціль", "Σ плечей")
  rows.each do |name, nom, got, want, sum, spec|
    flag = sum.between?(spec[0], spec[2]) ? "✓" : "✗ поза #{spec[0]}..#{spec[2]}"
    printf("%-28s %-26s %10.3f %12s %6.2f %s\n", name, nom, got, want, sum, flag)
  end

  puts
  puts "── VBAT_UV: НЕ програмується (§7.3.2). Кремній: #{VBAT_UV_MIN_V}/#{VBAT_UV_TYP_V}/#{VBAT_UV_MAX_V} В при спаданні."
  puts "   Відсічення системного навантаження робить VBAT_OK, не VBAT_UV — datasheet каже це прямо."
  puts

  lo, hi = band(ov)
  puts "── Допуск OV (VBAT_ACCURACY ±#{(VBAT_ACCURACY * 100).round} %, паспорт — ДЛЯ 0.1 % резисторів):"
  puts "   номінал #{'%.3f' % ov} В → смуга #{'%.3f' % lo} .. #{'%.3f' % hi} В"
  puts "   стеля іоністора / VSTOR(ABS MAX) = #{VSTOR_ABS_MAX_V} В → " \
       "#{hi > VSTOR_ABS_MAX_V ? "🔴 верхній хвіст ПЕРЕВИЩУЄ стелю на #{'%.0f' % ((hi - VSTOR_ABS_MAX_V) * 1000)} мВ" : "✓ вкладається"}"
  max_nominal = VSTOR_ABS_MAX_V / (1 + VBAT_ACCURACY)
  puts "   ⇒ найбільша ЦІЛЬ, чий верхній хвіст ще нижчий за стелю: #{'%.2f' % max_nominal} В"
  puts

  ok_on = Bq25570.vbat_ok_hyst(ok1, ok2, ok3)
  ok_off = Bq25570.vbat_ok_prog(ok1, ok2)
  ov_e96 = e96_band(ov, ov1, ov2)
  puts "── Смуга на НАШИХ #{(RESISTOR_TOL * 100).round} % E96 (паспортні ±2 % — лише для 0.1 %, SLUSBH2G VBAT_ACCURACY):"
  [ [ "VBAT_OV", ov, ov_e96 ], [ "VBAT_OK ON", ok_on, e96_band(ok_on, ok1, ok2, ok3) ],
    [ "VBAT_OK OFF", ok_off, e96_band(ok_off, ok1, ok2) ] ].each do |name, nom, b|
    printf("   %-11s %.3f В: плечі ±%.2f %% → worst-case ±%.2f %% (%.3f .. %.3f) · RSS ±%.2f %% (%.3f .. %.3f)\n",
           name, nom, b[:arms] * 100, b[:wc] * 100, *b[:wc_band], b[:rss] * 100, *b[:rss_band])
  end
  printf("   вікно клампа HW.12 до стелі %.1f В: ±2 %% → %.0f мВ · RSS → %.0f мВ · worst-case → %.0f мВ\n",
         VSTOR_ABS_MAX_V, (VSTOR_ABS_MAX_V - band(ov)[1]) * 1000,
         (VSTOR_ABS_MAX_V - ov_e96[:rss_band][1]) * 1000, (VSTOR_ABS_MAX_V - ov_e96[:wc_band][1]) * 1000)
  puts "   ⚠️ Мультиметр міряє поріг ОДНІЄЇ плати, не смугу партії — смугу дає цей розрахунок."
  puts

  # Межа вікна — поріг ON (OK_HYST), не OFF: так рахує `02_03 §8` («3.4В→VBAT_OV»), і так порахована база
  # CANON_WINDOW_J. Від OFF тут стояло до 2026-09-25 — друк казав «ТА САМА величина», а давав на 139 мДж більше
  # і Δ проти бази, порахованої від ON (00_07 HW.37).
  v_on = Bq25570.vbat_ok_hyst(ok1, ok2, ok3)
  v_off = Bq25570.vbat_ok_prog(ok1, ok2)
  e_hyst = 0.5 * EDLC_FARAD * (v_on**2 - v_off**2)
  puts "── Опції цілі OV (⚖️ вибір — не машинний; тут лише ціна кожної):"
  puts "   Енергія робочого вікна = ½·C·(V_OV² − V_OK_ON²), C = #{EDLC_FARAD} Ф, V_OK_ON = #{'%.3f' % v_on} В."
  puts "   ⚠️ Це ТА САМА величина, яку `02_03 §8` веде як 2.75 Дж на 4.822 В (було 4.39 Дж на 5.5 В). Повне вікно"
  puts "      розряду OV→OFF більше на гістерезисне ½·C·(V_ON² − V_OFF²) = #{'%.0f' % (e_hyst * 1000)} мДж (V_OK_OFF = #{'%.3f' % v_off} В, §9.8а)."
  printf("%8s %-24s %10s %10s %9s %7s %10s\n",
         "ціль", "номінали (МΩ)", "розрах.", "верх ±2 %", "вікно, Дж", "Δ", "clamp, мВ")
  [ 5.5, 5.4, 5.3, 5.2, 5.0, 4.822 ].each do |t|
    a, b = solve_ov(t)
    v = Bq25570.vbat_ov(a, b)
    e = 0.5 * EDLC_FARAD * (v**2 - v_on**2)
    clamp_mv = (VSTOR_ABS_MAX_V - band(v)[1]) * 1000
    printf("%8.2f %-24s %10.3f %10.3f %9.2f %6.1f%% %9.0f %s\n",
           t, "ROV1=#{a} ROV2=#{b}", v, band(v)[1], e,
           (e / CANON_WINDOW_J - 1) * 100, clamp_mv,
           band(v)[1] <= VSTOR_ABS_MAX_V ? "✓" : "🔴")
  end
  puts
  puts "🔴 Колонка `clamp` — ширина вікна для ЗОВНІШНЬОГО клампа HW.12: він мусить стояти"
  puts "   ВИЩЕ за верхній хвіст OV і НЕ ВИЩЕ за стелю #{VSTOR_ABS_MAX_V} В. Порівняй її з реальним"
  puts "   розкидом деталі: стабілітрон 1 % має V_z ±1 %, тобто ≈±48 мВ на ратифікованих 4.82 В, а"
  puts "   типовий 5 %-ряд — ±240 мВ; TVS standoff нормується ще грубіше. ⚖️ **РАТИФІКОВАНО"
  puts "   founder 2026-09-09 (Derate, HW.37): ціль 4.822 В дає вікно 581 мВ на паспортних ±2 %,"
  puts "   а на наших 1 % E96 — 572 мВ (RSS) / 521 мВ (worst-case), блок «Смуга на НАШИХ» вище."
  puts "   TVS-гілку ширше вікно НЕ врятувало (вимір 2026-09-24, tvs_shortlist): кламп мусить"
  puts "   мовчати в робочому діапазоні й спрацьовувати в (4.919; 5.5] В — на 1 % (4.979; 5.5] —"
  puts "   тобто V_BR max / V_RWM ≤ 1.118 (1.105), а датащити дають 1.40-2.67. Головна гілка —"
  puts "   supervisor + MOSFET-шунт (ovp_clamp_shortlist)."
end

# ── Режим ВИМІРЯНИХ номіналів (крок чек-листа `02_03 §11`) ────────────────────
# Приймає те, що людина щойно зняла мультиметром, і друкує пороги, які ці плечі
# дають НАСПРАВДІ. Ключі — імена плечей у конвенції TI, значення в МΩ:
#   ruby tools/firmware/bq25570_dividers.rb rov1=4.75 rov2=7.87 rok3=0.348
# ⚠️ «Щойно зняла» — це плече з ПІДНЯТИМ виводом (чи до запайки): плече в схемі
# шунтоване рештою мережі `VRDIV`, і його відлік сюди підставляти не можна — `--in-circuit`.
# Незадані плечі беруться з цільового набору; `rok3=0` — легальний вхід і саме
# він друкує «гістерезис = 0», бо непопульований ROK3 виглядає як здорова плата.
def parse_arms(args) = args.to_h { |a| k, v = a.split("=", 2); [ k.downcase.to_sym, Float(v) ] }

# Цільовий набір плечей, МΩ. OV-пара — ⚖️ ратифікований дефолт (4.822 В), див. report().
def target_arms
  ok1, ok2, ok3 = solve_ok(3.3, 3.4)
  out1, out2 = solve_out(3.3)
  oc1, oc2 = solve_mppt(0.65)
  { rov1: 4.75, rov2: 7.87, rok1: ok1, rok2: ok2, rok3: ok3, rout1: out1, rout2: out2, roc1: oc1, roc2: oc2 }
end

def measured_mode(args)
  given = parse_arms(args)
  d = target_arms.merge(given)

  puts "Виміряні плечі (МΩ): #{d.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  puts "джерело значень: #{given.keys.map(&:to_s).sort.join(', ')} — з мультиметра; решта — цільові"
  puts
  ov = Bq25570.vbat_ov(d[:rov1], d[:rov2])
  prog = Bq25570.vbat_ok_prog(d[:rok1], d[:rok2])
  hyst = Bq25570.vbat_ok_hyst(d[:rok1], d[:rok2], d[:rok3])
  printf("VBAT_OV        = %6.3f В  (смуга ±2%%: %.3f .. %.3f) %s\n",
         ov, *band(ov), ov > VBAT_OV_RANGE.max ? "🔴 поза програмованим діапазоном" : "")
  printf("VBAT_OK OFF    = %6.3f В\n", prog)
  printf("VBAT_OK ON     = %6.3f В  → гістерезис %.0f мВ %s\n",
         hyst, (hyst - prog) * 1000, (hyst - prog) < 0.01 ? "🔴 практично відсутній (ROK3?)" : "")
  printf("VOUT           = %6.3f В\n", Bq25570.vout(d[:rout1], d[:rout2]))
  printf("MPPT           = %6.2f %%\n", Bq25570.mppt_fraction(d[:roc1], d[:roc2]) * 100)
  puts
  { ov: d[:rov1] + d[:rov2], ok: d[:rok1] + d[:rok2] + d[:rok3],
    out: d[:rout1] + d[:rout2], oc: d[:roc1] + d[:roc2] }.each do |key, sum|
    lo, _typ, hi = RSUM_SPEC[key]
    printf("Σ %-4s = %6.2f МΩ  %s\n", key, sum, sum.between?(lo, hi) ? "✓" : "🔴 поза #{lo}..#{hi}")
  end
end

# ── Режим «у схемі» [HW.7]: що покаже омметр на плечі, НЕ випаяному з плати ────
# Три порогові дільники мають СПІЛЬНИЙ верх (`VRDIV`, шапка `02_03 §4`) і спільний низ
# (GND), тож омметр на одному плечі бачить його паралельно з рештою мережі. На нашому
# наборі Eq.(2) на таких відліках дає майже стоковий Li-Po поріг, а стокова OV-пара
# поруч із нашими OK/OUT — «мисматч»: позитивний контроль у схемі хибить в обидва боки.
# Тому плече міряють з ПІДНЯТИМ виводом (чи до запайки); ця таблиця — лише очікування
# для звірки ПОВНОГО набору, коли всі плечі відомі (після перепайки).
# ⛔ СТЕЛЯ: модель — ідеальні резистори між вузлами. Знеструмлений BQ25570 між
# `VRDIV`/тапами/`VSTOR` і GND має власний імпеданс (ESD-діоди, внутрішній ключ `VRDIV`),
# якого паспорт не нормує, і він лише ЗНИЖУЄ відлік; накопичувач із `VSTOR` мусить бути
# знятий (0.47 Ф не дасть відліку встановитись); стокові OK/OUT CJMCU-2557 невідомі, тож
# для стокової плати таблиця ілюстративна; омметр вище ~20 МΩ на багатьох приладах грубий.
# MPPT-пара висить на `VIN_DC`, а не на `VRDIV`: за відʼєднаного джерела вона читається
# номіналом — ця мережа окрема (компонента звʼязності нижче).
ARM_EDGES = {
  rov1: %i[ov gnd], rov2: %i[vrdiv ov],
  rok1: %i[okp gnd], rok2: %i[okh okp], rok3: %i[vrdiv okh],
  rout1: %i[out gnd], rout2: %i[vrdiv out],
  roc1: %i[voc gnd], roc2: %i[vin voc]
}.freeze

# Опір плеча `arm` у схемі: вузловий аналіз (1 А у один кінець, другий — земля) над
# компонентою звʼязності цього плеча; Гаусс із вибором головного на кількох вузлах.
def in_circuit(arms, arm)
  a, b = ARM_EDGES.fetch(arm)
  edges = ARM_EDGES.map { |k, (n1, n2)| [ n1, n2, arms.fetch(k).to_f ] }
  comp = [ a ]
  loop do
    grown = comp | edges.flat_map { |n1, n2, _| comp.include?(n1) ? [ n2 ] : (comp.include?(n2) ? [ n1 ] : []) }
    break if grown.size == comp.size
    comp = grown
  end
  idx = (comp - [ b ]).each_with_index.to_h
  n = idx.size
  g = Array.new(n) { Array.new(n + 1, 0.0) }
  edges.each do |n1, n2, r|
    next unless comp.include?(n1)
    i, j = idx[n1], idx[n2]
    g[i][i] += 1.0 / r if i
    g[j][j] += 1.0 / r if j
    next unless i && j
    g[i][j] -= 1.0 / r
    g[j][i] -= 1.0 / r
  end
  g[idx[a]][n] = 1.0
  n.times do |c|
    piv = (c...n).max_by { |r| g[r][c].abs }
    g[c], g[piv] = g[piv], g[c]
    ((c + 1)...n).each do |r|
      f = g[r][c] / g[c][c]
      (c..n).each { |k| g[r][k] -= f * g[c][k] }
    end
  end
  v = Array.new(n, 0.0)
  (n - 1).downto(0) { |r| v[r] = (g[r][n] - ((r + 1)...n).sum { |k| g[r][k] * v[k] }) / g[r][r] }
  v[idx[a]]
end

# Звір вузлового розвʼязку з закритою формою на двох топологічно різних плечах
# (крайнє OV і середнє OK) і на окремій MPPT-мережі — гоняє `--assert`.
def in_circuit_drift
  a = target_arms
  par = ->(x, y) { x * y / (x + y) }
  s_ov = a[:rov1] + a[:rov2]
  s_ok = a[:rok1] + a[:rok2] + a[:rok3]
  s_out = a[:rout1] + a[:rout2]
  { rov1: par.(a[:rov1], a[:rov2] + par.(s_ok, s_out)),
    rok2: par.(a[:rok2], a[:rok3] + par.(s_ov, s_out) + a[:rok1]),
    roc1: a[:roc1] }.filter_map do |k, want|
    got = in_circuit(a, k)
    format("%s у схемі: вузловий %.6f ≠ закрита форма %.6f МΩ", k, got, want) if (got - want).abs > 1e-9
  end
end

def in_circuit_mode(args)
  arms = target_arms.merge(parse_arms(args))
  puts "Плечі В СХЕМІ (МΩ): плата знеструмлена, накопичувач із VSTOR знято, джерело з VIN_DC відʼєднано."
  puts "Набір: #{arms.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  puts
  printf("%-6s %9s %9s %8s\n", "плече", "номінал", "у схемі", "Δ")
  ARM_EDGES.each_key do |k|
    ic = in_circuit(arms, k)
    printf("%-6s %9.3f %9.3f %+7.1f%%\n", k, arms[k], ic, (ic / arms[k] - 1) * 100)
  end
  puts
  ov_nom = Bq25570.vbat_ov(arms[:rov1], arms[:rov2])
  ov_ic = Bq25570.vbat_ov(in_circuit(arms, :rov1), in_circuit(arms, :rov2))
  stock = arms.merge(rov1: 5.62, rov2: 7.32)
  st_ic = Bq25570.vbat_ov(in_circuit(stock, :rov1), in_circuit(stock, :rov2))
  printf("Eq.(2): на номіналах %.3f В · на відліках у схемі %.3f В\n", ov_nom, ov_ic)
  printf("Стокова OV-пара 5.62/7.32 (SLUSBH2G §8.2.1) поруч із цими OK/OUT: номінал %.3f В · у схемі %.3f В\n",
         Bq25570.vbat_ov(5.62, 7.32), st_ic)
  puts "⇒ Відлік у схемі в Eq.(2) НЕ підставляти: плече міряють з піднятим виводом (чи до запайки)."
  puts "  Поріг судить функціональний замір — плато VSTOR на OV (02_03 §10.4 крок 5); опір плечей судить їхній ПОРЯДОК."
  puts "  ⛔ Стеля: імпеданс знеструмленого BQ25570 і стокові OK/OUT не моделюються — див. шапку режиму."
end

# ── Гейт канону [HW.13]: `02_03 §5` ⟷ рівняння ───────────────────────────────
# Читає зведену таблицю канону, перераховує кожен рядок ЦИМИ рівняннями й вимагає
# збігу з надрукованим там порогом. Ловить рівно два класи: swap плечей (65↔35 %,
# 3.3↔1.9 В) і дрейф §4 ⟷ §5.
#
# 🔑 ЧОМУ ЦЕ НЕ «два наші доми, звірені один з одним» (guard-craft #67): ланцюг
# має ЗОВНІШНІЙ якір — рівняння, якими гейт рахує, самі пінуються worked-прикладами
# TI у `--assert`. Тобто канон звіряється не з нашою думкою, а з datasheet через
# два кроки. ⛔ Знімати `--assert` із CI, лишивши `--check-canon`, заборонено: без
# нього ця перевірка вироджується саме в те, чим здається.
#
# ⛔ ОГОЛОШЕНА СТЕЛЯ: гейт судить ЧИСЛА таблиці §5, і нічого більше. Він НЕ бачить
# прози §4, не знає, який вузол у верхнього плеча, і не перевіряє, чи ціль розумна
# — «5.5 В недосяжні» є присудом (§4.Б), а не тим, що тут почервоніє.
CANON_DOC = File.expand_path("../../docs/02_03_BQ25570_MPPT_Nano_Power.md", __dir__)
CANON_ROWS_EXPECTED = 5   # MPPT · OV · OK OFF · OK ON · VOUT — розмір множини пінується

# ⚠️ Скоуп — ЛИШЕ зведена таблиця §5. Ширший скан бере й підтаблиці §4 (там ті самі
# номінали в іншій розкладці) і перетворює гейт на шум; вузький — робить розмір
# множини осмисленим піном.
def canon_section5(text)
  lines = text.each_line.to_a
  from = lines.index { |l| l.start_with?("## ") && l.include?("5. Зведена") }
  return [] unless from
  to = lines[(from + 1)..].index { |l| l.start_with?("## ") }
  lines[from, to ? to + 1 : lines.size - from]
end

def parse_canon_table(text)
  ohms = lambda do |cell|
    m = cell.to_s.match(/\*\*([\d.]+)\s*(MΩ|kΩ)\*\*/)
    m && (m[2] == "kΩ" ? m[1].to_f / 1000 : m[1].to_f)
  end
  canon_section5(text).filter_map do |line|
    next unless line.start_with?("|")
    cells = line.split("|").map(&:strip)
    next if cells.size < 8
    label = cells[1].to_s
    next if label.empty? || label.start_with?("---") || label.include?("Параметр")
    next if label =~ /Undervoltage/    # ⛔ не програмується — резисторів нема за побудовою
    printed = cells[6].to_s[/\*\*([\d.]+)\s*(?:В|%)\*\*/, 1]
    next unless printed
    # Допуск — ОДНА одиниця останнього НАДРУКОВАНОГО розряду, а не стала: рядок у
    # вольтах і рядок у відсотках мають різну ціну поділки, і жорсткий 0.02 на
    # відсотках червонив би коректне заокруглення (65.065 → «65.1»).
    decimals = printed[/\.(\d+)/, 1].to_s.length
    { label:, r1: ohms.call(cells[3]), r2: ohms.call(cells[4]),
      r3: ohms.call(cells[5]), stated: printed.to_f, tol: 10.0**-decimals }
  end
end

def check_canon_mode
  rows = parse_canon_table(File.read(CANON_DOC))
  problems = []
  if rows.size != CANON_ROWS_EXPECTED
    problems << "розмір множини: розпізнано #{rows.size} рядків, очікувано #{CANON_ROWS_EXPECTED} " \
                "— парсер або таблиця змінились; порожня/скорочена множина проходить зеленою мовчки"
  end
  prev = nil
  rows.each do |row|
    l = row[:label]
    computed =
      case l
      when /MPPT/ then row[:r1] && row[:r2] && Bq25570.mppt_fraction(row[:r1], row[:r2]) * 100
      when /Overvoltage/ then row[:r1] && row[:r2] && Bq25570.vbat_ov(row[:r1], row[:r2])
      when /OK OFF/ then row[:r1] && row[:r2] && Bq25570.vbat_ok_prog(row[:r1], row[:r2])
      when /OK ON/ then prev && row[:r3] && Bq25570.vbat_ok_hyst(prev[:r1], prev[:r2], row[:r3])
      when /Buck/ then row[:r1] && row[:r2] && Bq25570.vout(row[:r1], row[:r2])
      end
    prev = row if l =~ /OK OFF/
    if computed.nil?
      problems << "«#{l}»: не витяглись номінали — рядок є, числа нема"
    elsif (computed - row[:stated]).abs > row[:tol]
      problems << format("«%s»: таблиця каже %.3f, рівняння дають %.3f (допуск ±%.3f)", l, row[:stated], computed, row[:tol])
    end
  end
  problems.each { |p| warn "FAIL  #{CANON_DOC.sub(Dir.pwd + '/', '')} — #{p}" }
  puts problems.empty? ? "OK  §5 (#{rows.size} рядків) збігається з рівняннями SLUSBH2G" : "RED"
  exit(problems.empty? ? 0 : 1)
end

case ARGV.first
when "--assert" then assert_mode
when "--check-canon" then check_canon_mode
when "--in-circuit" then in_circuit_mode(ARGV.drop(1))
when nil then report
when /\A[a-zA-Z_][a-zA-Z0-9_]*=/ then measured_mode(ARGV)
else
  warn "невідомий режим #{ARGV.first.inspect}; доступні: (порожньо) · --assert · --check-canon · --in-circuit [KEY=VAL…] · KEY=VAL (rov1=… rok3=…)"
  exit 2
end
