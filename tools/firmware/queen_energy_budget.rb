# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [HW.39] Queen energy-budget — параметрична модель, single-source чисел.
# Канон (02_05 §4/§4а/§Зимовий · 02_06 §4) ПОСИЛАЄТЬСЯ сюди, не restate'ить:
# редагуєш число — тут, канон тримає лише висновки.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/queen_energy_budget.rb                # повний звіт (обидві фази + panel-матриця)
#   ruby tools/firmware/queen_energy_budget.rb panel_w=10     # override будь-якого параметра KEY=VAL
#   ruby tools/firmware/queen_energy_budget.rb --assert       # deploy-гейт: Phase 1/2.5 winter-balance
#                                                             # ≥ margin → exit 0, інакше exit 1;
#                                                             # Phase 3 = warn-only до Starlink bring-up;
#                                                             # на defaults — ще й дзеркала канону
#
# Фізика моделі (стелі позначені):
#   спожив  = Σ компонент-рядків (I×U×t) + DC-DC втрати на 3.3/3.7V-гілках
#   генер   = panel_w × sun_h × panel_eff × canopy_factor   ← canopy МНОЖИТЬСЯ на
#             panel_eff, не замінює його (стара таблиця §Зимовий мовчки викидала 0.8)
#   autonomy = usable-батарея / |дефіцит| (при мінусі) або dark-days (при плюсі)
# Наївна стеля [HW.39]: добове усереднення, без температурної деградації LiFePO4
# і без місячного профілю інсоляції — ревізія при bench-даних (RUNBOOK).

PARAMS = {
  # ── споживачі (canonical-джерела в коментарях) ────────────────────────────
  mcu_ma: 7.0,             # STM32WLE5JC continuous RX @3.3V (02_05 §2.1)
  mcu_v: 3.3,
  modem_idle_ma: 10.0,     # SIM7070G idle @3.7V (datasheet; PSM/eDRX знизить — bench)
  modem_v: 3.7,
  tx_sessions_per_day: 24, # CoAP flush 1×/год
  tx_session_s: 30.0,      # LTE-M сесія з RRC-хвостом, не чиста TX-мить
  tx_session_ma: 150.0,    # avg за сесію (peak 2A — то HW.15/BMS, не бюджет)
  quiescent_ma: 20.0,      # Victron 75/15 self-consumption @12V ONLY (manual Rev 10 p.66) — the BMS row is NOT in this model yet (00_07 HW.15)
  # (HW.15, 2026-07-03); стара таблиця брала 5 мА — 4× оптимізм
  quiescent_v: 12.0,
  dcdc_eff: 0.88,          # buck 12V→3.7/3.3V на ЛЕГКОМУ навантаженні (~10–20 мА гілки):
  # TI SNVSB99C (LMR33640, поз. 9, PFM-auto) Figure 9-6 — VOUT 3.3 V, 400 кГц, VIN 12 V:
  # ≈ 88 % при 10 мА (зчитано з кривої оком, ±1 п.п.; для 3.74 В крива ще трохи вища —
  # Figure 9-5, 5 V ≈ 90 %), тож 0.88 — консервативна межа, а не пік «> 95 %».
  # Стеля: поз. 10 (12→3.3 V) — лише клас «≥ 500 мА», даташиту немає → та сама 0.88
  # ПРИПУЩЕНА й для неї; канон 02_05 §4а.2 бере ті самі 88 %.
  # ── Phase 3 додатки ───────────────────────────────────────────────────────
  starlink_w: 25.0,        # Starlink Mini active — нижній край average 25–40 Вт (⚖️ 2026-10-01; присуд і ціна — 02_05 §4)
  starlink_min_per_h: 5.0, # duty-cycle 5 хв/год
  starlink_psu_eff: 0.90,
  esp32_w: 0.5,            # ESP32-S3 ACTIVE (WiFi-STA до Mini) — лише у вікні Starlink:
  # memo HW.18 у 02_05 §Starlink DTC — active 80–240 мА (~0.3–0.9 Вт)
  esp32_sleep_ua: 10.0,    # deep-sleep поза вікном — memo HW.18 («~10 µA між погодинними TX»)
  esp32_v: 3.3,
  # ── генерація ─────────────────────────────────────────────────────────────
  panel_w: 50.0,           # ⚖️ panel-decision Phase 1/2.5: 10 vs 50 (02_06 §4 ↔ 02_05)
  sun_h: 3.0,              # зимовий день, низьке сонце
  panel_eff: 0.80,         # кут/бруд/сніг/MPPT-втрати
  canopy_pct: 12.5,        # хвойний ліс взимку: 10–15% інсоляції під кронами
  # ── батарея / гейт ────────────────────────────────────────────────────────
  battery_ah: 20.0,        # LiFePO4 12V (02_05 §7 поз.7; 02_06 §4 брав 6 Ah)
  battery_v: 12.0,
  dod: 0.80,               # LiFePO4 usable depth-of-discharge
  margin_pct: 20.0         # deploy-гейт: winter-balance ≥ 20% споживання
}.freeze

params = PARAMS.dup
assert_mode = ARGV.delete("--assert")
ARGV.each do |arg|
  key, val = arg.split("=", 2)
  key = key.to_sym
  abort("невідомий параметр: #{key} (є: #{PARAMS.keys.join(', ')})") unless PARAMS.key?(key)
  params[key] = Float(val)
end

def wh(ma, volts, hours) = ma / 1000.0 * volts * hours

# Рядки-споживачі: [назва, Wh/добу, через_DC-DC?]; quiescent сидить на 12V-шині —
# повз buck, тому втрати DC-DC застосовуються лише до 3.3/3.7V-гілок.
# Phase 3 НЕ несе SIM7070G: BOM 02_05 §7 поз. 2 (і її buck поз. 9) — фаза «1/2.5», а
# 02_06 §4а рядок 2 міняє uplink на «ESP32-S3 + WiFi». ESP32 активний лише у вікні Starlink
# (присуд HW.18 обрав його саме за deep-sleep), решту доби спить.
# Стеля: бут Mini (30–60 с на сесію, 02_05 §2.3) — частина хвилин starlink_min_per_h, окремо
# не рахується; ESP32, що прокидається трохи раніше за Mini, теж сидить у тому ж вікні.
def consumption_rows(p, phase3:)
  tx_h = p[:tx_sessions_per_day] * p[:tx_session_s] / 3600.0
  rows = [ [ "STM32WLE5JC continuous RX", wh(p[:mcu_ma], p[:mcu_v], 24.0), true ] ]
  unless phase3
    rows << [ "SIM7070G idle", wh(p[:modem_idle_ma], p[:modem_v], 24.0 - tx_h), true ]
    rows << [ "SIM7070G LTE-M flush-сесії", wh(p[:tx_session_ma], p[:modem_v], tx_h), true ]
  end
  rows << [ "MPPT quiescent (12V; BMS not modelled)", wh(p[:quiescent_ma], p[:quiescent_v], 24.0), false ]
  if phase3
    starlink_h = p[:starlink_min_per_h] / 60.0 * 24.0
    rows << [ "Starlink Mini (%.1fхв/год)" % p[:starlink_min_per_h],
             p[:starlink_w] * starlink_h / p[:starlink_psu_eff], false ]
    rows << [ "ESP32-S3 (active у вікні Starlink)", p[:esp32_w] * starlink_h, true ]
    rows << [ "ESP32-S3 deep-sleep", wh(p[:esp32_sleep_ua] / 1000.0, p[:esp32_v], 24.0 - starlink_h), true ]
  end
  rows
end

def daily_consumption_wh(p, phase3:)
  consumption_rows(p, phase3: phase3)
    .sum { |_, raw_wh, bucked| bucked ? raw_wh / p[:dcdc_eff] : raw_wh }
end

def daily_generation_wh(p)
  p[:panel_w] * p[:sun_h] * p[:panel_eff] * (p[:canopy_pct] / 100.0)
end

def report(p, phase3:)
  cons = daily_consumption_wh(p, phase3: phase3)
  gen = daily_generation_wh(p)
  balance = gen - cons
  usable = p[:battery_ah] * p[:battery_v] * p[:dod]
  puts "  %-34s %8s %s" % [ "компонент", "Wh/добу", "(через DC-DC)" ]
  consumption_rows(p, phase3: phase3).each do |name, raw_wh, bucked|
    eff_wh = bucked ? raw_wh / p[:dcdc_eff] : raw_wh
    puts "  %-34s %8.2f %s" % [ name, eff_wh, bucked ? "✓" : "—" ]
  end
  puts "  %-34s %8.2f" % [ "РАЗОМ споживання", cons ]
  puts "  %-34s %8.2f  (%.0fW × %.1fгод × %.0f%% × %.1f%%)" %
       [ "Генерація (зима, під кронами)", gen, p[:panel_w], p[:sun_h],
        p[:panel_eff] * 100, p[:canopy_pct] ]
  puts "  %-34s %+8.2f Wh/добу" % [ "БАЛАНС", balance ]
  if balance.negative?
    puts "  %-34s %8.1f днів (батарея %.0fAh, DoD %.0f%%)" %
         [ "Автономність до відмови", usable / -balance, p[:battery_ah], p[:dod] * 100 ]
  else
    puts "  %-34s %8.1f днів (0 генерації, хмарна смуга)" %
         [ "Dark-автономність", usable / cons ]
  end
  balance
end

# ── дзеркала канону ──────────────────────────────────────────────────────────
# 02_05 §4 · §Зимовий і 02_06 §4 цитують прогін на defaults («правити модель, не таблицю»), а пін на
# це дзеркало не стояв: зміна dcdc_eff 0.95 → 0.88 лишила в каноні старі 7.39 і «26 днів» мовчки.
# Пін ловить дрейф канону від моделі, але не помилку самої моделі (клас дзеркал board_area_budget);
# судиться лише на defaults — override міняє модель, а не канон.
CANON_DOCS = %w[02_05_Queen_Hardware_and_Starlink.md 02_06_Unit_Economics_and_BOM.md].freeze

def canon_mirrors(p)
  text = CANON_DOCS.to_h { |name| [ name[0, 5], File.read(File.expand_path("../../docs/#{name}", __dir__)) ] }
  p1 = daily_consumption_wh(p, phase3: false)
  p3 = daily_consumption_wh(p, phase3: true)
  gen = daily_generation_wh(p)
  usable = ->(ah) { ah * p[:battery_v] * p[:dod] }
  bat = p[:battery_ah]
  {
    "02_05 §4 · разом Phase 1/2.5" => [ "02_05", "**~%.1f Вт·год/добу**" % p1 ],
    "02_05 §4 · генерація" => [ "02_05", "**%.1f Вт·год/добу**" % gen ],
    "02_05 §4 · баланс і dark-автономність" =>
      [ "02_05", "**+%.1f Вт·год/добу ✅** (dark-автономність %.1f днів на %.0fAh)" % [ gen - p1, usable.(bat) / p1, bat ] ],
    "02_05 §4 · разом Phase 3" => [ "02_05", "**~%.1f Вт·год/добу**" % p3 ],
    "02_05 §4 · баланс Phase 3" =>
      [ "02_05", "**−%.1f Вт·год ⚠️** (автономність %.1f дні на %.0fAh)" % [ p3 - gen, usable.(bat) / (p3 - gen), bat ] ],
    "02_05 §Зимовий · Phase 1/2.5" => [ "02_05", "%.1f Вт·год генерації vs ~%.1f Вт·год споживання" % [ gen, p1 ] ],
    "02_05 §Зимовий · профіцит" => [ "02_05", "**профіцит +%.1f Вт·год/добу ✅**" % (gen - p1) ],
    "02_05 §Зимовий · Phase 3" =>
      [ "02_05", "%.1f Вт·год vs ~%.1f Вт·год → дефіцит ~%.1f Вт·год → автономність **%.1f дні**" %
                 [ gen, p3, p3 - gen, usable.(bat) / (p3 - gen) ] ],
    # 6 Ah — відхилений варіант, з яким 02_06 §4 рядок 4 порівнює дефолт.
    "02_06 §4 · 6 Ah проти дефолту" =>
      [ "02_06", "%.1f днів dark-автономності проти %.1f" % [ usable.(6.0) / p1, usable.(bat) / p1 ] ],
    "02_06 · добова глибина розряду" => [ "02_06", "(%.2f Вт·год/добу споживання" % p1 ]
  }.map { |name, (doc, needle)| [ "#{name}: «#{needle}»", text.fetch(doc).include?(needle) ] }
end

# ── deploy-гейт ──────────────────────────────────────────────────────────────
if assert_mode
  cons = daily_consumption_wh(params, phase3: false)
  balance = daily_generation_wh(params) - cons
  need = cons * params[:margin_pct] / 100.0
  if balance < need
    warn "queen_energy_budget ✗ — Phase 1/2.5 winter-balance %+.2f Wh/добу < margin %.2f " \
         "(%.0f%% споживання %.2f); panel_w=%.0f canopy=%.1f%% quiescent=%.0fмА" %
         [ balance, need, params[:margin_pct], cons,
          params[:panel_w], params[:canopy_pct], params[:quiescent_ma] ]
    exit 1
  end
  p3_balance = daily_generation_wh(params) - daily_consumption_wh(params, phase3: true)
  if p3_balance.negative?
    warn "queen_energy_budget ⚠ (warn-only до Starlink bring-up) — Phase 3 winter-balance " \
         "%+.2f Wh/добу: потрібен більший акум/панель/duty-cycle (02_05 §4)" % p3_balance
  end
  puts "queen_energy_budget ✓ — Phase 1/2.5 winter-balance %+.2f Wh/добу ≥ margin %.2f" %
       [ balance, need ]
  if params == PARAMS
    mirrors = canon_mirrors(params)
    mirrors.each { |name, ok| puts "#{ok ? 'OK  ' : 'FAIL'} дзеркало #{name}" }
    exit 1 unless mirrors.all? { |_, ok| ok }
  else
    puts "дзеркала канону не судяться: override міняє модель, а канон цитує defaults"
  end
  exit 0
end

# ── повний звіт ──────────────────────────────────────────────────────────────
puts "═══ Queen energy budget — зима, хвойний ліс (canopy #{params[:canopy_pct]}%) ═══"
puts "\n── Phase 1/2.5 (SIM7070G LTE-M / DTC) ──"
report(params, phase3: false)
puts "\n── Phase 3 (Starlink Mini + ESP32-S3 замість SIM7070G) ──"
report(params, phase3: true)

puts "\n── ⚖️ Panel-матриця Phase 1/2.5 (balance Wh/добу; canopy 10 / 12.5 / 15%) ──"
puts "  %-8s %10s %10s %10s" % [ "panel_w", "10%", "12.5%", "15%" ]
[ 10.0, 30.0, 50.0 ].each do |pw|
  balances = [ 10.0, 12.5, 15.0 ].map do |canopy|
    pp2 = params.merge(panel_w: pw, canopy_pct: canopy)
    daily_generation_wh(pp2) - daily_consumption_wh(pp2, phase3: false)
  end
  # rubocop:disable Lint/FormatParameterMismatch -- коп не рахує splat: `balances`
  # це три елементи, тож аргументів рівно чотири, як і полів.
  puts "  %-8.0f %+10.2f %+10.2f %+10.2f" % [ pw, *balances ]
  # rubocop:enable Lint/FormatParameterMismatch
end
