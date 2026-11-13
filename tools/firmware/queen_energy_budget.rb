# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "date"

# [HW.39] Queen energy-budget — параметрична модель, single-source чисел.
# Канон (02_05 §4/§4а/§Зимовий · 02_06 §4) ПОСИЛАЄТЬСЯ сюди, не restate'ить:
# редагуєш число — тут, канон тримає лише висновки.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/queen_energy_budget.rb                # повний звіт (обидві фази + panel-матриця)
#   ruby tools/firmware/queen_energy_budget.rb panel_w=10     # override будь-якого параметра KEY=VAL
#   ruby tools/firmware/queen_energy_budget.rb --assert       # deploy-гейт: код виходу судить ЛИШЕ сталу
#                                                             # `sun_h` (Phase 1/2.5 winter-balance ≥ margin)
#                                                             # і дзеркала канону на defaults; ряд сонця й
#                                                             # Phase 3 — попередження; відсутній чи битий
#                                                             # ряд — exit 1
#
# Фізика моделі (стелі позначені):
#   спожив  = Σ компонент-рядків (I×U×t) + DC-DC втрати на 3.3/3.7V-гілках
#   генер   = panel_w × sun_h × panel_eff × canopy_factor   ← canopy МНОЖИТЬСЯ на
#             panel_eff, не замінює його (стара таблиця §Зимовий мовчки викидала 0.8)
#   autonomy = usable-батарея / |дефіцит| (при мінусі) або dark-days (при плюсі)
# Наївна стеля [HW.39]: добове усереднення, без температурної деградації LiFePO4; формула на сталій
# `sun_h` — без місячного профілю інсоляції й без заборони заряду на морозі: обидва несе блок
# «ряд сонця й температури» ↓ ([HW.14]) — ревізія при bench-даних (RUNBOOK).

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
  sun_h: 3.0,              # ⚠️ джерела немає; на ряді це березень (блок «ряд сонця» ↓); гейт досі судить нею — 00_07 HW.14
  panel_eff: 0.80,         # кут/бруд/сніг/MPPT-втрати
  canopy_pct: 12.5,        # хвойний ліс взимку: 10–15% інсоляції під кронами
  # ── батарея / гейт ────────────────────────────────────────────────────────
  battery_ah: 20.0,        # LiFePO4 12V (02_05 §7 поз.7; 02_06 §4 брав 6 Ah)
  battery_v: 12.0,
  dod: 0.80,               # LiFePO4 usable depth-of-discharge
  charge_min_c: 1.0,       # заряд LiFePO4 заблоковано нижче цієї температури (02_05 §4а.5); читає лише блок ряду
  margin_pct: 20.0         # ДВА пороги одним числом: (стала) winter-balance ≥ 20 % споживання;
  # (ряд) найглибша точка проходу акумулятора ≥ 20 % корисної ємності
}.freeze

params = PARAMS.dup
assert_mode = ARGV.delete("--assert")
ARGV.each do |arg|
  key, val = arg.split("=", 2)
  key = key.to_sym
  abort("невідомий параметр: #{key} (є: #{PARAMS.keys.join(', ')})") unless PARAMS.key?(key)
  params[key] = Float(val)
end
# Область моделі: поза нею формули друкують числа, які нічого не означають (firmware-скіл #15 а).
abort("canopy_pct поза 0…100: #{params[:canopy_pct]}") unless (0.0..100.0).cover?(params[:canopy_pct])
abort("dod поза 0…1: #{params[:dod]}") unless (0.0..1.0).cover?(params[:dod])
abort("panel_w або battery_ah від'ємні") if params[:panel_w].negative? || params[:battery_ah].negative?
abort("від'ємний струм або margin") if %i[quiescent_ma mcu_ma modem_idle_ma tx_session_ma margin_pct].any? { |k| params[k].negative? }
abort("panel_eff поза 0…1: #{params[:panel_eff]}") unless (0.0..1.0).cover?(params[:panel_eff])

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

# ── ряд сонця й температури ──────────────────────────────────────────────────
# [HW.14] `sun_h` у формулі генерації — добовий потік у площині панелі в кВт·год/м² (еквівалентні
# години при 1 кВт/м²). Ряд дає його для ГОРИЗОНТАЛЬНОЇ поверхні по добах 2001–2020: CERES SYN1deg
# через NASA POWER, клітинка Черкас — провенанс і стелі в data/README.md. Стала `sun_h` = 3.0 джерела
# не має й відповідає березню; доки рішення про залізо не змінило defaults, ряд судить поруч із нею,
# warn-only (00_07 HW.14).
SERIES_FILE = File.expand_path("data/power_cherkasy_sw_daily_2001_2020.csv", __dir__)
SERIES_DAYS = 7305
# Добова середня температура повітря тієї ж точки (ERA5, провенанс — README каталогу): заряд LiFePO4
# канон блокує нижче +1 °C (02_05 §4а.5), а корпус узимку тримає зовнішню температуру (там само).
TEMP_FILE = File.expand_path("../in_silico/data/era5_cherkasy/daily_t2m_mean_1991_2020.csv", __dir__)
# Доба, на якій заряд заблоковано, читається двома названими способами, і жоден не обрано:
#   :direct — панель живить навантаження напряму, але лише у світлу частку доби; надлишок нікуди
#             покласти, а нічну частку споживання акумулятор віддає безповоротно (верхня межа:
#             зранку й увечері панель слабша за навантаження);
#   :lost   — генерація цієї доби втрачена цілком (зарядний тракт розімкнено разом із навантаженням).
FROST_READINGS = { direct: "панель живить напряму вдень", lost: "генерацію втрачено" }.freeze
SITE_LAT_DEG = 49.44

# Світла частка доби на широті ділянки: астрономічна довжина дня за схиленням сонця (Купер) —
# без рельєфу, крони й сутінків.
def daylight_fraction(date)
  n = Date.strptime(date, "%Y-%m-%d").yday
  decl = 23.44 * Math::PI / 180.0 * Math.sin(2.0 * Math::PI * (284 + n) / 365.0)
  Math.acos(-Math.tan(SITE_LAT_DEG * Math::PI / 180.0) * Math.tan(decl)) / Math::PI
end

def sun_series
  temps = File.readlines(TEMP_FILE, chomp: true).filter_map do |line|
    date, t = line.split(",")
    [ date, Float(t) ] if date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
  end.to_h
  rows = File.readlines(SERIES_FILE, chomp: true).drop(1).map do |line|
    date, ghi, = line.split(",")
    [ date, Float(ghi), temps[date] ]
  end
  abort("ряд сонця неповний: #{rows.size} діб із #{SERIES_DAYS}") unless rows.size == SERIES_DAYS
  abort("ряд сонця не впорядкований за датою") unless rows.each_cons(2).all? { |x, y| x[0] < y[0] }
  abort("потік поза 0…12 кВт·год/м²/добу — не ті одиниці?") if rows.any? { |_, ghi, _| ghi.negative? || ghi > 12.0 }
  abort("для #{rows.count { |r| r[2].nil? }} діб ряду немає температури") if rows.any? { |r| r[2].nil? }
  rows
end

def series_generation_wh(p, ghi) = p[:panel_w] * ghi * p[:panel_eff] * (p[:canopy_pct] / 100.0)

# Найдовша смуга діб поспіль, коли заряд заблоковано морозом.
def longest_frost_streak(rows, charge_min_c)
  rows.chunk_while { |x, y| x[2] < charge_min_c && y[2] < charge_min_c }
      .select { |run| run.first[2] < charge_min_c }.map(&:size).max || 0
end

# Місяць → середній добовий потік за всі роки ряду, середній за найтемніший рік цього місяця й
# частка діб, коли заряд заблоковано морозом.
def monthly_sun(rows, charge_min_c)
  by_month = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
  frost = Hash.new { |h, k| h[k] = [ 0, 0 ] }
  rows.each do |date, ghi, temp|
    mo = date[5, 2].to_i
    by_month[mo][date[0, 4]] << ghi
    frost[mo][0] += 1 if temp < charge_min_c
    frost[mo][1] += 1
  end
  by_month.to_h do |mo, years|
    all = years.values.flatten
    [ mo, { mean: all.sum / all.size, worst: years.values.map { |v| v.sum / v.size }.min,
            frost_share: frost[mo][0].to_f / frost[mo][1] } ]
  end
end

# Прохід акумулятора по ряду: заряд росте генерацією доби й падає споживанням; стеля — корисна
# ємність, підлога — нуль, і доба, на якій заряду не вистачило, — доба відсічки. Зима = липень…червень.
# `frost:` — nil (заряд дозволено завжди; лише для порівняння зі старим читанням) або ключ
# FROST_READINGS: на добі з середньою нижче `charge_min_c` заряд заблоковано.
# Стелі: (1) старт із повного акумулятора 1 січня першого року — перша пів-зима ряду м'якша за
# справжню; (2) споживання стале, ємність без морозної деградації; (3) температура комірки = добова
# середня повітря ERA5 — а ERA5 у морозні ночі тепліший за станцію (00_07 HW.37), і корпус на сонці
# тепліший за повітря: похибка має обидва знаки; (4) добовий крок ночі не бачить; (5) РОЗРЯДУ на
# морозі прохід не судить: заводський поріг розряду BMS гасить Королеву вже при −15…−17 °C
# (02_05 §4а.5), тож «без відсічок» тут означає лише «без відсічок за зарядом».
def battery_walk(p, rows, frost: nil, phase3: false)
  usable = p[:battery_ah] * p[:battery_v] * p[:dod]
  cons = daily_consumption_wh(p, phase3: phase3)
  soc = min_soc = usable
  min_date = rows.first.first
  blackout = Hash.new(0)
  winter_of = ->(date) { date[5, 2].to_i >= 7 ? date[0, 4].to_i : date[0, 4].to_i - 1 }
  rows.each do |date, ghi, temp|
    gen = series_generation_wh(p, ghi)
    net = gen - cons
    if frost && temp < p[:charge_min_c]
      day = cons * daylight_fraction(date)
      net = frost == :lost ? -cons : -(cons - day) - [ day - gen, 0.0 ].max
    end
    soc += net
    if soc.negative?
      blackout[winter_of.(date)] += 1
      soc = 0.0
    end
    soc = usable if soc > usable
    min_soc, min_date = soc, date if soc < min_soc
  end
  full = rows.map { |date, _, _| winter_of.(date) }.tally.select { |_, n| n >= 365 }.keys
  { usable: usable, cons: cons, min_soc: min_soc, min_date: min_date, blackout_days: blackout.values.sum,
    blackout_full: (blackout.keys & full).size, winters_full: full.size }
end

def walk_text(walk, reserve)
  if walk[:blackout_days].positive?
    "діб відсічки %d; у %d повних зимах із %d" % [ walk[:blackout_days], walk[:blackout_full], walk[:winters_full] ]
  else
    "відсічок немає, найглибша точка %.0f Вт·год із %.0f (%s), запас %s %.0f" %
      [ walk[:min_soc], walk[:usable], walk[:min_date], walk[:min_soc] >= reserve ? "≥" : "<", reserve ]
  end
end

# Питання ряду — ОДНЕ: чи переживає конфігурація кожну зиму ряду без відсічки і з запасом `margin_pct`
# корисної ємності на найглибшій точці — в ОБОХ прочитаннях морозної доби.
def series_verdict(p, rows, phase3: false)
  walks = FROST_READINGS.keys.to_h { |rd| [ rd, battery_walk(p, rows, frost: rd, phase3: phase3) ] }
  first = walks.values.first
  if first[:usable] < first[:cons]
    return [ false, "акумулятор (%.1f Вт·год корисних) менший за добове споживання %.2f — добовий прохід ночі " \
                    "не бачить, вердикту немає" % [ first[:usable], first[:cons] ] ]
  end
  reserve = first[:usable] * p[:margin_pct] / 100.0
  ok = walks.values.all? { |w| w[:blackout_days].zero? && w[:min_soc] >= reserve }
  [ ok, FROST_READINGS.map { |rd, name| "#{name} — #{walk_text(walks[rd], reserve)}" }.join(" · ") ]
end

def series_report(p, rows)
  cons = daily_consumption_wh(p, phase3: false)
  sun = monthly_sun(rows, p[:charge_min_c])
  puts "  %-7s %12s %13s %10s %9s %22s" % [ "місяць", "потік середн.", "найтемн. рік", "генерація", "баланс", "діб без заряду" ]
  [ 10, 11, 12, 1, 2, 3 ].each do |mo|
    gen = series_generation_wh(p, sun[mo][:mean])
    puts "  %-7d %12.2f %13.2f %10.2f %+9.2f %21.0f%%" % [ mo, sun[mo][:mean], sun[mo][:worst], gen, gen - cons, sun[mo][:frost_share] * 100 ]
  end
  ok, text = series_verdict(p, rows)
  puts "  Phase 1/2.5 на ряді (споживання %.2f Вт·год/добу): #{ok ? '✓' : '✗'} #{text}" % cons
  plain = battery_walk(p, rows)
  puts "  без заборони заряду на морозі (лише для порівняння): #{walk_text(plain, plain[:usable] * p[:margin_pct] / 100.0)}"
  puts "  найдовша смуга діб без заряду (середня доби нижче +%.0f °C): %d" % [ p[:charge_min_c], longest_frost_streak(rows, p[:charge_min_c]) ]
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
       [ "Генерація (стала sun_h, під кронами)", gen, p[:panel_w], p[:sun_h],
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
  rows = sun_series
  sun = monthly_sun(rows, p[:charge_min_c])
  walks = [ nil, *FROST_READINGS.keys ].map { |rd| battery_walk(p, rows, frost: rd) }
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
    "02_06 · добова глибина розряду" => [ "02_06", "(%.2f Вт·год/добу споживання" % p1 ],
    "02_05 §Зимовий ⊕ · потік ряду за місяцями" =>
      [ "02_05", "%.2f у листопаді, %.2f у грудні, %.2f у січні, %.2f у лютому й %.2f у березні" %
                 [ 11, 12, 1, 2, 3 ].map { |mo| sun[mo][:mean] } ],
    "02_05 §Зимовий ⊕ · груднева генерація на ряді" =>
      [ "02_05", "дає в грудні %.1f Вт·год/добу проти ~%.1f споживання" % [ series_generation_wh(p, sun[12][:mean]), p1 ] ],
    "02_05 §Зимовий ⊕ · відкрите місце на ряді" =>
      [ "02_05", "— %.1f Вт·год/добу в грудні замість" % (p[:panel_w] * sun[12][:mean] * p[:panel_eff]) ],
    "02_05 §Зимовий ⊕ · доби без заряду" =>
      [ "02_05", "у %.0f %% діб грудня, %.0f %% січня й %.0f %% лютого" % [ 12, 1, 2 ].map { |mo| sun[mo][:frost_share] * 100 } ],
    "02_05 §Зимовий ⊕ · найдовша морозна смуга" => [ "02_05", "найдовша така смуга в ряді — %d діб" % longest_frost_streak(rows, p[:charge_min_c]) ],
    "02_05 §Зимовий ⊕ · доби відсічки в трьох проходах" =>
      [ "02_05", "діб відсічки за 20 років: %d ⊥ %d і %d без заборони" % walks.values_at(1, 2, 0).map { |w| w[:blackout_days] } ],
    "02_05 §Зимовий ⊕ · відсічки в кожній повній зимі" =>
      [ "02_05", walks.all? { |w| w[:blackout_full] == w[:winters_full] } ? "дає відсічки в кожній повній зимі" : "⟂ ⊕ про кожну повну зиму застарів" ]
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
  # [transitional] Ряд сонця й температури судить поруч зі сталою `sun_h`, warn-only: на defaults він
  # червоний, і жорстким гейтом стане разом із рішенням про залізо, яке змінить defaults (00_07 HW.14).
  series_ok, series_text = series_verdict(params, sun_series)
  puts "queen_energy_budget ✓ — Phase 1/2.5 на СТАЛІЙ sun_h=%.1f: баланс %+.2f Wh/добу ≥ margin %.2f%s" %
       [ params[:sun_h], balance, need, series_ok ? "" : " — ⚠ ряд сонця цього НЕ підтверджує" ]
  $stdout.flush
  unless series_ok
    warn "::warning title=queen_energy_budget::(warn-only до рішення про залізо, 00_07 HW.14) на ряді сонця " \
         "CERES 2001–2020 Phase 1/2.5: #{series_text}; стала sun_h=#{format('%.1f', params[:sun_h])} джерела не має"
  end
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

puts "\n── Ряд сонця CERES 2001–2020, кВт·год/м²/добу на горизонтальну поверхню (data/README.md) ──"
series_report(params, sun_series)

puts "\n── ⚖️ Panel-матриця Phase 1/2.5 НА СТАЛІЙ sun_h=#{params[:sun_h]} (джерела не має; на ряді — блок ↑) — balance Wh/добу; canopy 10 / 12.5 / 15% ──"
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
