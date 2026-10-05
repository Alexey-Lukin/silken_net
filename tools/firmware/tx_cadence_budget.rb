# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.8] Каденція TX як ФУНКЦІЯ довжини кадру — і ціна кожного важеля розвилки.
#
# Канон 02_03 §9.6/§9.7 (Сценарій C) тримає ланцюг
#   payload → airtime → E_TX → E_active → H = E_active / (E_gen − E_sleep)
# ПРОЗОЮ в code-fence'ах, тобто твердженням, якому нема чим почервоніти, коли
# зрушить бодай один його вхід (`ssot-maintenance` §Guard-craft #95). Цей файл —
# дім самого ланцюга: він нічого не переписує з канону, він канон ВІДТВОРЮЄ.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/tx_cadence_budget.rb            # H для обох ер кадру + смуга m(Δt)
#   ruby tools/firmware/tx_cadence_budget.rb --levers   # запас стоку + важелі розвилки ARCH.8
#   ruby tools/firmware/tx_cadence_budget.rb --assert   # гейт: модель відтворює надруковані числа
#   ruby tools/firmware/tx_cadence_budget.rb p_gen_uw=17.13   # override будь-якого параметра
#
# ⛔ ЩО ЦЕЙ ФАЙЛ НЕ РОБИТЬ — і це не скромність, а межа мандату. Розвилка ARCH.8
# стоїть ВІДКРИТОЮ, але ⚖️ 2026-09-22 (делеговано) її звужено: (а) підняти
# DELTA_T_SLOW_S — ВІДХИЛЕНО · (б) підняти P_gen — не важіль, а ВИМІР, якого ще
# немає · (в) різати payload — ціна в байтах · (г) SF — доданий четвертий; з 2026-09-26
# ще й (д) — ворота RX-вікна. На чинних входах (без інференсу) CCM стоїть ПЕРЕД підлогою,
# тож `--levers` друкує запас стоку на VSTOR і (г)/(д), а ціни (а)–(в) — лише під override,
# що кладе CCM за підлогу (команду друкує сам); ціни (а) і там лишаються як ПІДСТАВА
# відхилення. Вибір лишається присудом.
#
# ⛔ І ДРУГЕ, чого він не робить: він не перекладає мілісекунди в БАЙТИ. ToA має
# один дім — `tools/firmware/lora_airtime.rb` (модель Semtech + профіль із
# `firmware/common/lora_phy.h`). Тут стеля airtime рахується, а перевести її в
# довжину кадру просить сусіда командою, яку сам і друкує.
#
# Ті самі під-цикли (Lorenz · η_buck) і той самий сон-стік рахує й
# `tools/firmware/boot_brownout_cycle.rb` — під ІНШЕ питання (гістерезисне вікно
# HW.44), тому прилади не злиті. Дубль-поверхню, що тут стояла [transitional],
# знято 2026-09-22: спільна арифметика живе в `lib/energy_chain.rb` (формули
# нижче), реєстр — `00_06 §3` (TX-cadence budget).
#
# ⛔ СТЕЛІ ВХОДІВ, оголошені вголос — інакше зелений прогін почне означати «правда»:
#   • `p_gen_uw = 15` — канон сам зве це «робоче число БЕЗ простежуваного джерела»
#     (02_03 §9.2), і між ним та L4-моделлю (~369 µW після переякорення 2026-09-18,
#     01_03 §3.4; до нього ~140) стоїть розрив, який тримає
#     HW.46. 🔴 Наслідок для читання важеля (б): він виглядає найдешевшим саме
#     тому, що його вхід найменш певний. Це не аргумент за нього й не проти —
#     це попередження не цитувати друковане число як інженерний запас.
#   • РАДІО-ЧЛЕНИ ЦИКЛУ — з обраного фронтенду (⚖️ 2026-09-26: SMPS + TCXO NT2016SF,
#     `docs/protocols/hardware/rf_frontend_forks.md` §2.5/§3.3), і їх ТРИ, а не один:
#     TX `RFO_LP` +14 дБм 23.5 мА (DS13105 Табл. 29, Typ 25 °C, узгодження ST — наше інше;
#     Табл. 25 тієї ж первинки каже 26 мА) · пост-TX RX-вікно 500 мс при 4.82 мА (Табл. 28),
#     яке прошивка відкриває ЩОЦИКЛУ, бо ворота `VCAP_LISTEN_THRESHOLD` вироджені (скіл
#     `firmware`, gotcha #9) · TCXO 2.11 мА, живий на TX і на RX-вікні. ⛔ Чого тут НЕМАЄ і
#     чому: холостого циклу ядра в `LORA_RX_LOOP_MS` = 600 мс (такт ядра ще не обрано; на
#     48 МГц CoreMark-струм 3.40 мА дав би ≈ 6.7 мДж більше) · TCXO під час обчислень (умова
#     «SYSCLK від MSI»; від HSE32 — ще +2.44 мДж) · самопрозряду EDLC (`02_03 §9.3`, FAE) —
#     числа для нього немає, тож модель друкує його ВПЛИВ навпаки: скільки стоку на VSTOR
#     кожна точка витримує до метаболічної підлоги (`sink_headroom_na`, звіт і `--levers`).
#     Інференсу в циклі немає: акустичного датчика на Солдаті немає (⚖️ founder 2026-09-29,
#     `02_01 §6`), тож і члена немає — не нуля.
#     Отже за цими членами H нижче — НИЖНЯ межа; але тривалість Lorenz (`lorenz_mj`) — стеля
#     й тягне навпаки, тож знак сумарної похибки не визначено, і H — сценарна точка
#     (`02_03 §9.4`). η_buck 0.88 при ~24 мА стоїть на краю діапазону, для якого канон її тримає.
#   • `t_air_ms` — транскрипція з `lora_airtime.rb` §ENERGY_ANCHORS (той самий
#     набір, що вже гейтований проти 02_03 §9.6 ВЛАСНИМ асертом сусіда). Транскрипція ЖИВА доводиться
#     нижче: `--assert` вимагає, щоб виведене E_TX збіглося з числом, надрукованим
#     у каноні — ⚠️ але це ловить дрейф МОДЕЛІ, а дрейф сусіда ловить сусідів гейт; смуга
#     тут ±0.64 мс airtime (допуск 0.05 мДж ÷ 23.5 мА × 3.3 В), тобто пін НЕ тугий.
#   • `eta_boost = 0.68` — це точка §9.1 при P_in = 15 µW, і вона є функцією ВХІДНОЇ
#     ПОТУЖНОСТІ, а не сезону (⚠️ поправка 2026-09-12: доти тут стояло «літня точка»).
#     🔴 Наслідок для важеля (б): піднімаючи `p_gen_uw` вище 15, модель тримає η на
#     значенні для 15 — тобто друковані відсотки (б) ЗАВИЩЕНІ на частку, що росте з кроком
#     (консервативно, але це не «ціна»). З тієї ж причини Сценарій D модель не відтворює.
#     Зимову η (0.65) тримає HW.44-модель,
#     і мішати їх не можна: тут питання про річну каденцію, не про виживання.
#   • Ланцюг зупиняється на `H`. Крок `H → Δt → m → GP → SCC` має власні доми
#     (`scc_rate.rb` для значення, `uncertainty_budget.rb` для точності), і цей
#     файл їх НАЗИВАЄ в `--levers` (друкує команду), а не кличе й не переписує — ⚠️ поправка
#     2026-09-12: доти шапка казала «КЛИЧЕ», і це було твердженням про механізм, якого немає.

require_relative "lib/energy_chain"
EC = SilkenEnergyChain

CANON_DOC = File.expand_path("../../docs/02_03_BQ25570_MPPT_Nano_Power.md", __dir__)

# ГРОШОВА робоча точка живе в двох сусідах, і вони НЕ кличуть цей файл (прилади свідомо не злиті).
# Тому її читають звідси, щоб розбіжність ставала видимою: 2026-09-26 вона тихо відстала на +10 %
# (ланцюг без RX-вікна й на струмі чужого підсилювача), і помітило її лише статичне «0.4 %»,
# яке брехало. Дефолт тепер = ця модель (⚖️ founder 2026-09-26); зріз пʼєзо прибрав інференс із
# циклу, і точка пішла за ланцюгом, як велить той самий присуд (⚖️ делеговано 2026-09-29, 02_06 §7.1).
# 🔴 Судимо її ГРОШИМА, не відсотком Δt (адверсарне ревʼю 2026-09-26 · ⚖️ делеговано 2026-09-27,
# 00_07 ARCH.8): wire-GP квантований, і біля 7027 с сходинка wire 6 → 5 (stored-GP 12 → 10) лежить за 46 с, тож доти
# чинні «±8 % Δt» пропускали −23…+45 % SCC. Тепер: та сама сходинка wire-GP, що в ECB-точки, і SCC
# у межах невизначеності Δt ПІСЛЯ EMA — прошивка подає в `m` саме EMA, а ±8 % є сирим джитером
# ДО фільтра (та сама підміна сиділа й у «боці підлоги» нижче; лікована тим самим допуском).
# Виміряно: ±8 % Δt біля 7027 с = 7.80…4.16 SCC. (Складники ±8 % — джитер RTC, дрейф кварцу,
# нерегулярні прокидання; EMA гасить лише некорельовану частину, тож 2.67 % — нижня межа u_Δt,
# і похибка тягне гейт у суворіший бік.) ЦІНА присуду — гейт тугіший: розбіжність енергомоделі
# з грошовою точкою на > u_Δt у SCC або через сходинку червонить CI, і зняти її можна лише
# свідомим рухом грошової точки (VARIANT_C_S · delta_t_s) — код присуду не вимагає, він
# вимагає правки, яку видно в діфі; мовчки вона більше не проходить. НАЙСЛАБША
# ЛАНКА — межі сходинок стоять на placeholder-смузі DELTA_T_FAST_S/SLOW_S (E.63): калібрування
# їх зсуне, і гейт піде за ними сам, але відстань до сходинки — число сьогоднішньої смуги й
# точки; друкує її сам зелений рядок.
# Числа смуги — у домі грошей (scc_rate.rb), допуск — у домі точності (uncertainty_budget.rb):
# цей файл їх ЧИТАЄ, як доти читав VARIANT_C_S, а арифметика — спільна (lib/growth_steps.rb).
require_relative "lib/growth_steps"
GS = SilkenGrowthSteps

def neighbour_number(file, name)
  v = File.read(File.expand_path(file, __dir__))[/^\s*#{name}\s*[=:]\s*([\d._]+)/, 1]
  v && Float(v.delete("_"))
end

def money_model
  scc = ->(n) { neighbour_number("scc_rate.rb", n) }
  unc = ->(n) { neighbour_number("uncertainty_budget.rb", n) }
  { point_s: scc.call("VARIANT_C_S"), unc_point_s: unc.call("delta_t_s"),
    band: { fast_s: scc.call("DELTA_T_FAST_S"), slow_s: scc.call("DELTA_T_SLOW_S"),
            gp_min: scc.call("GP_HOMEO_MIN"), gp_max: scc.call("GP_HOMEO_MAX") },
    upscale: scc.call("BACKEND_UPSCALE"), threshold: scc.call("EMISSION_THRESHOLD"),
    u_raw_pct: unc.call("u_delta_t_raw_pct"), ema_alpha: unc.call("ema_alpha") }
end

def money_model_complete?(mm) = (mm.values - [ mm[:band] ] + mm[:band].values).none?(&:nil?)

# Невизначеність Δt ПІСЛЯ EMA: σ_out/σ_in = sqrt(α / (2−α)) — та сама формула, що в uncertainty_budget.rb.
def dt_tolerance_pct(mm) = mm[:u_raw_pct] * Math.sqrt(mm[:ema_alpha] / (2.0 - mm[:ema_alpha]))

def money_scc(mm, delta_t_s)
  GS.scc_per_tree_year(delta_t_s: delta_t_s, threshold: mm[:threshold],
                       stored_gp: mm[:upscale] * GS.wire_gp(delta_t_s: delta_t_s, **mm[:band]))
end

def money_verdict(mm, energy_s)
  w_money = GS.wire_gp(delta_t_s: mm[:point_s], **mm[:band])
  w_energy = GS.wire_gp(delta_t_s: energy_s, **mm[:band])
  gap = 100.0 * (money_scc(mm, energy_s) / money_scc(mm, mm[:point_s]) - 1.0)
  { same_step: w_money == w_energy, w_money: w_money, w_energy: w_energy, gap_pct: gap,
    scc_money: money_scc(mm, mm[:point_s]), scc_energy: money_scc(mm, energy_s), tol_pct: dt_tolerance_pct(mm) }
end

# Де грошова точка стоїть на сходинці і що коштує крок униз.
def money_step_note(mm)
  e = GS.step_edges(delta_t_s: mm[:point_s], **mm[:band])
  parts = []
  parts << format("−%.0f с до %d→%d", mm[:point_s] - e[:up_s], e[:wire], e[:wire] + 1) if e[:up_s]
  if e[:down_s]
    drop = 100.0 * (1.0 - money_scc(mm, e[:down_s] + 1.0) / money_scc(mm, mm[:point_s]))
    parts << format("+%.0f с до %d→%d (−%.0f %% SCC)", e[:down_s] - mm[:point_s], e[:wire], e[:wire] - 1, drop)
  else
    parts << "підлога — нижче сходинок немає"
  end
  "сходинка wire-GP #{e[:wire]}: #{parts.join(' · ')}"
end

PARAMS = {
  # ── активний цикл на VOUT (02_03 §9.4 / §9.6 Сценарій C) ──────────────────
  lorenz_mj: 3.96,
  i_tx_ma: 23.5,            # STM32WL RFO_LP +14 dBm, SMPS — DS13105 Табл. 29 (⚖️ SMPS 2026-09-26)
  i_rx_ma: 4.82,            # RX LoRa 125 кГц, SMPS — DS13105 Табл. 28
  t_rx_ms: 500.0,           # LORA_RX_TIMEOUT_MS — пост-TX вікно, відкрите ЩОЦИКЛУ (soldier/main.c, Фаза 4.5)
  i_tcxo_ma: 2.11,          # NT2016SF max 2.0 + Iq 0.07 + 2 % (⚖️ TCXO 2026-09-26) — живий на TX і на RX
  v_out: 3.3,
  eta_buck_active: 0.88,
  # ── сон (Сценарій C, §9.6) ───────────────────────────────────────────────
  # ⚠️ 300 нА — ЦІЛЬ ратифікованого Сценарію C, і на STM32WLE5 цей клас струму дає лише Standby
  # (без утримання SRAM2), не STOP2: прапорця «STOP2 RTC-only» і біта RRSTP у WL немає, а прошивка
  # входить у STOP2 (`HAL_PWREx_EnterSTOP2Mode`, firmware/soldier/main.c). Відвантажений режим
  # друкується другим прочитанням (`SLEEP_READINGS` нижче), дефолт лишається присудом — 00_07 FW.54.
  i_stm32_sleep_na: 300.0,
  eta_buck_sleep: 0.50,
  i_bq_quiescent_na: 488.0,
  v_vstor_avg: 4.5,
  # ── генерація ────────────────────────────────────────────────────────────
  p_gen_uw: 15.0,
  eta_boost: 0.68,
  # ── метаболічна смуга (firmware/bio_contracts/bio_contract.rb, E.63) ──────
  delta_t_fast_s: 600.0,
  delta_t_slow_s: 7200.0
}.freeze

# (мітка, payload Б, airtime мс, як це число НАПИСАНЕ в 02_03 §9.6)
# ⛔ Літерал у четвертій колонці — не оздоба: він і є доказом, що транскрипція
# airtime ще жива. Без нього модель відтворювала б саму себе.
WIRE_ERAS = [
  [ "ECB 16 Б (відвантажено сьогодні)", 16, 164.9, "12.79" ],
  [ "CCM 30 Б (wire-rev2.1, FW.2 bench-gated)", 30, 226.3, "17.55" ]
].freeze

# Сон за ПАСПОРТОМ режимів, яких прошивка входить або мусила б входити (00_07 FW.54, 2026-10-05):
# друге прочитання поруч із ціллю, не дефолт — дефолт є присудом (02_03 §9.8), і рухає його власник.
# Typ при 25 °C. STOP2 — титульне число при 3 В (Табл. 43 на LSI: 1.00 / 1.10 µA при 3.0 / 3.6 В); Standby —
# Табл. 49 (0.445 / 0.535 µA при 3.0 / 3.6 В), інтерпольовано на шину 3.3 В. При 55 °C паспорт дає 2.90 µA (STOP2,
# RTC на LSI) і 1.25 µA (Standby з SRAM2), тож літо під радомом тягне сон угору, а модель цього не несе. Радіо —
# окремий член поза обома числами: `Radio.Sleep()` прошивки — warm start, 140 нА лише радіо (Табл. 28; cold — 50).
SLEEP_READINGS = [
  [ "STOP2 + RTC — режим відвантаженої прошивки (DS13105 Rev 12, титульна)", 1070.0 ],
  [ "Standby + RTC на LSE low drive + SRAM2 (DS13105 Rev 12, Табл. 49, на 3.3 В)", 490.0 ]
].freeze

params = PARAMS.dup
mode = ARGV.delete("--levers") ? :levers : (ARGV.delete("--assert") ? :assert : :report)
ARGV.each do |arg|
  key, val = arg.split("=", 2)
  key = key.to_s.to_sym
  abort("невідомий параметр: #{key} (є: #{PARAMS.keys.join(', ')})") unless PARAMS.key?(key)
  params[key] = Float(val)
end

def e_tx_mj(p, t_air_ms) = p[:i_tx_ma] * p[:v_out] * t_air_ms / 1000.0
def e_rx_mj(p) = p[:i_rx_ma] * p[:v_out] * p[:t_rx_ms] / 1000.0
# TCXO живе рівно стільки, скільки живе радіо: кадр + RX-вікно (умова «SYSCLK від MSI» — шапка).
def e_tcxo_mj(p, t_air_ms) = p[:i_tcxo_ma] * p[:v_out] * (t_air_ms + p[:t_rx_ms]) / 1000.0

# ⛔ Чотири формули нижче живуть у спільному `lib/energy_chain.rb` (ARCH.8) — той
# самий ланцюг рахує й `boot_brownout_cycle.rb` під питання HW.44. Прилади
# свідомо НЕ злиті (різні питання, різні стелі), злито рівно арифметику.
def e_active_from_vstor_mj(p, t_air_ms)
  EC.active_cycle_from_vstor_mj(lorenz_mj: p[:lorenz_mj],
                                tx_mj: e_tx_mj(p, t_air_ms), rx_mj: e_rx_mj(p),
                                tcxo_mj: e_tcxo_mj(p, t_air_ms), eta_buck_active: p[:eta_buck_active])
end

def sleep_drain_uw(p)
  EC.sleep_drain_uw(i_stm32_sleep_na: p[:i_stm32_sleep_na], v_out: p[:v_out],
                    eta_buck_sleep: p[:eta_buck_sleep],
                    i_bq_quiescent_na: p[:i_bq_quiescent_na], v_vstor_avg: p[:v_vstor_avg])
end

def e_sleep_mj_h(p) = EC.mj_per_hour(sleep_drain_uw(p))
def e_gen_mj_h(p) = EC.gen_mj_per_hour(p_gen_uw: p[:p_gen_uw], eta_boost: p[:eta_boost])
def net_mj_h(p) = e_gen_mj_h(p) - e_sleep_mj_h(p)

# H — інтервал між пакетами, за якого баланс рівно нульовий. ⚠️ Це БЕЗЗАПАСНА
# точка — і саме її канон бере за каденцію C (`02_03 §9.7`: «≈0», `m` ≈ 0.03).
# Нетто ≤ 0 = вузол не накопичує на жоден пакет: H = ∞, а m тоді 0. Ділення без
# цієї гілки давало від'ємне H, і m затискалось на 1.0 — повний метаболізм на
# вузлі, що не заряджається (HW.12, 2026-09-24).
def interval_h(p, t_air_ms)
  net = net_mj_h(p)
  net.positive? ? e_active_from_vstor_mj(p, t_air_ms) / net : Float::INFINITY
end

# m(Δt) — метаболічне відображення (bio_contract.rb). Нижче нуля воно не
# опускається: GP сідає на підлогу, і саме тому «H зріс» і «мінт упав» — різні
# твердження з різними порогами.
def metabolic_m(p, delta_t_s)
  span = p[:delta_t_slow_s] - p[:delta_t_fast_s]
  [ [ (p[:delta_t_slow_s] - delta_t_s) / span, 0.0 ].max, 1.0 ].min
end

# Скільки ДОДАТКОВОГО стоку на VSTOR (нА, поверх 488 нА BQ25570) точка витримує, перш ніж
# сісти на метаболічну підлогу (Δt = DELTA_T_SLOW_S, m = 0). Закрита форма тієї самої H:
# підлога вимагає чистого прибутку E_active·3600/SLOW, а кожен нА на VSTOR забирає
# V_VSTOR·3.6/1000 мДж/год. Сюди лягають члени, яких модель НЕ несе, бо числа для них немає
# або деталь не обрано: самопрозряд EDLC (HW.37) · струм спокою клампа VSTOR (HW.12) — обидва
# стоки саме цієї шини. ⚠️ Стік рахується на СЕРЕДНІЙ напрузі VSTOR (`v_vstor_avg`), а флоат-
# витік EDLC міряють на 4.8 В — різниця ≈ 7 % у бік, що запас ЗАВИЩУЄ. Відʼємне значення:
# точка вже за підлогою без жодного додаткового стоку.
def sink_headroom_na(p, t_air_ms)
  need_net = e_active_from_vstor_mj(p, t_air_ms) * 3600.0 / p[:delta_t_slow_s]
  (net_mj_h(p) - need_net) / EC.mj_per_hour(p[:v_vstor_avg] / 1000.0)
end

def era_rows(p)
  # Каденція-референс для колонки `e_net`: ПЕРША ера переліку, тобто та, що
  # відвантажена. Питання, на яке ця колонка відповідає, — «що станеться, якщо
  # кадр підмінити, а каденцію лишити», і воно не те саме, що `H`: сам `H` є
  # беззапасною точкою й дає нуль за побудовою для КОЖНОЇ ери.
  ref_h = interval_h(p, WIRE_ERAS.first[2])
  WIRE_ERAS.map do |label, pl, t_air, literal|
    h = interval_h(p, t_air)
    { label: label, payload_b: pl, t_air_ms: t_air, canon_literal: literal,
      e_tx_mj: e_tx_mj(p, t_air), e_rx_mj: e_rx_mj(p), e_tcxo_mj: e_tcxo_mj(p, t_air),
      e_active_mj: e_active_from_vstor_mj(p, t_air),
      h_hours: h, delta_t_s: h * 3600.0, m: metabolic_m(p, h * 3600.0),
      sink_headroom_na: sink_headroom_na(p, t_air),
      e_net_at_ref_cadence_mj_h: net_mj_h(p) - e_active_from_vstor_mj(p, t_air) / ref_h }
  end
end

def report(p)
  puts "ARCH.8 — каденція TX як функція ДОВЖИНИ КАДРУ (02_03 §9.6 Сценарій C)"
  puts format("  E_gen = %.2f · E_sleep = %.2f · чистий прибуток = %.2f мДж/год  (P_gen %.1f µW, η_boost %.2f)",
              e_gen_mj_h(p), e_sleep_mj_h(p), net_mj_h(p), p[:p_gen_uw], p[:eta_boost])
  puts
  puts format("  %-42s %6s %9s %8s %10s %8s %6s", "ера кадру", "PL, Б", "T_air, мс", "E_TX", "E_active", "H, год", "m")
  puts "  #{'-' * 96}"
  rows = era_rows(p)
  rows.each do |r|
    puts format("  %-42s %6d %9.1f %6.2f мДж %7.2f мДж %7.3f %6.3f",
                r[:label], r[:payload_b], r[:t_air_ms], r[:e_tx_mj], r[:e_active_mj], r[:h_hours], r[:m])
  end
  unless net_mj_h(p).positive?
    puts "\n  ⚠️ баланс ≤ 0: вузол не накопичує на жоден TX — H = ∞, m = 0; робочої точки, про яку далі, немає."
    return 0
  end
  ecb, ccm = rows
  puts
  puts format("  → Перехід 16 Б → 30 Б коштує +%.1f %% airtime і +%.1f %% активної енергії,",
              100.0 * (ccm[:t_air_ms] / ecb[:t_air_ms] - 1.0),
              100.0 * (ccm[:e_active_mj] / ecb[:e_active_mj] - 1.0))
  puts format("    звідки H %.2f → %.2f год. ⚠️ Але вирішує не H, а ПОРІГ: m сідає на нуль на Δt = %.0f с",
              ecb[:h_hours], ccm[:h_hours], p[:delta_t_slow_s])
  if ccm[:m].zero?
    puts format("    (%.2f год), тобто ДО точки CCM — отже GP падає на підлогу, а не пропорційно.",
                p[:delta_t_slow_s] / 3600.0)
  else
    puts format("    (%.2f год), а CCM-точка стоїть ПЕРЕД ним (m = %.3f) — перехід коштує частину GP, не підлогу.",
                p[:delta_t_slow_s] / 3600.0, ccm[:m])
  end
  puts "    «H зріс» і «мінт упав» — різні твердження з різними порогами."
  puts format("  → Якщо кадр підмінити, а КАДЕНЦІЮ лишити на %.2f год: баланс %+.2f мДж/год.",
              ecb[:h_hours], ccm[:e_net_at_ref_cadence_mj_h])
  puts format("  → Запас чинної робочої точки до підлоги: %.0f с (%.1f хв); перехід просить %.0f с (%.1f хв).",
              p[:delta_t_slow_s] - ecb[:delta_t_s], (p[:delta_t_slow_s] - ecb[:delta_t_s]) / 60.0,
              ccm[:delta_t_s] - ecb[:delta_t_s], (ccm[:delta_t_s] - ecb[:delta_t_s]) / 60.0)
  puts format("  → Стік на VSTOR, який точки витримують до підлоги (самопрозряд EDLC · кламп — чисел немає): " \
              "ECB %s · CCM %s.", headroom_note(ecb), headroom_note(ccm))
  sleep_readings(p)
  puts
  mm = money_model
  unless money_model_complete?(mm)
    puts "  ⚠️ числа грошової моделі (scc_rate.rb / uncertainty_budget.rb) не знайдено — грошового вироку нема."
    return 0
  end
  v = money_verdict(mm, ecb[:delta_t_s])
  puts format("  Грошові моделі (scc_rate.rb, uncertainty_budget.rb) беруть дефолтом %.0f с; ця модель дає"\
              " %.0f с — SCC %.2f ⊥ %.2f/дерево/рік (%+.1f %%).", mm[:point_s], ecb[:delta_t_s],
              v[:scc_money], v[:scc_energy], v[:gap_pct])
  if v[:same_step] && v[:gap_pct].abs <= v[:tol_pct]
    puts format("     Та сама сходинка wire-GP (%d) і в межах ±%.2f %% u_Δt після EMA: округлення, не розбіжність.",
                v[:w_money], v[:tol_pct])
  else
    puts format("     🔴 Розбіжність у ГРОШАХ: сходинка wire-GP %d ⊥ %d, SCC %+.1f %% (допуск ±%.2f %% u_Δt після EMA) —",
                v[:w_money], v[:w_energy], v[:gap_pct], v[:tol_pct])
    puts "     дефолт відстає від ланцюга, який виконує прошивка. ⛔ Рухати його можна лише присудом"
    puts "     (⚖️ founder 2026-09-26, повна форма — 02_06 §7.1; стан — 00_07 ARCH.8): від нього залежать гроші,"
    puts "     а не лише цей звіт."
  end
  puts "  → Грошова точка: #{money_step_note(mm)}."
  puts format("  → ECB-точка стоїть %s (%.1f %% від Δt) — %s.", *floor_side(p, ecb, v[:tol_pct]))
  0
end

# Друге прочитання сну (`SLEEP_READINGS`): той самий ланцюг, змінено лише `i_stm32_sleep_na`.
def sleep_readings(p)
  if p[:i_stm32_sleep_na] == PARAMS[:i_stm32_sleep_na]
    puts format("  ⚠️ Сон %.0f нА — ціль класу Standby, а прошивка спить у STOP2 (00_07 FW.54). Той самий ланцюг " \
                "із паспортним сном:", p[:i_stm32_sleep_na])
  else
    puts "  Для порівняння — той самий ланцюг із паспортним сном:"
  end
  SLEEP_READINGS.each do |label, na|
    q = p.merge(i_stm32_sleep_na: na)
    unless net_mj_h(q).positive?
      puts format("     %s, %.0f нА: баланс ≤ 0 — H = ∞, m = 0", label, na)
      next
    end
    ecb, ccm = era_rows(q)
    puts format("     %s, %.0f нА: H %.2f / %.2f год (ECB / CCM) · m %.3f / %.3f · стік ECB %s · CCM %s",
                label, na, ecb[:h_hours], ccm[:h_hours], ecb[:m], ccm[:m], headroom_note(ecb), headroom_note(ccm))
  end
end

def headroom_note(row)
  na = row[:sink_headroom_na]
  na.negative? ? format("уже за підлогою (бракує %.0f нА)", -na) : format("≤ %.0f нА", na)
end

# Бік метаболічної підлоги і чи він доведений. Вердикт стежить за ЗНАКОМ і за смугою невизначеності
# Δt ПІСЛЯ EMA (доти — сирі ±8 %, тобто підміна тієї самої величини, що й у грошовому гейті):
# під override точка лягає і далеко перед підлогою, і за нею, а статичний текст брехав би в
# обидва боки (однобічне `<= 0.08` друкувало «−31.8 % — ВСЕРЕДИНІ ±8 %»).
def floor_side(p, ecb, tol_pct)
  gap_s = p[:delta_t_slow_s] - ecb[:delta_t_s]
  gap_pct = 100.0 * gap_s / ecb[:delta_t_s]
  where = gap_s >= 0 ? format("за %.0f с ДО підлоги", gap_s) : format("на %.0f с ЗА підлогою", -gap_s)
  band = format("±%.2f %% Δt після EMA", tol_pct)
  verdict =
    if gap_pct.abs <= tol_pct then "у межах #{band}, тобто бік підлоги не доведено"
    elsif gap_pct.positive? then "поза #{band} — точка перед підлогою"
    else "поза #{band} — m = 0 тут не шум"
    end
  [ where, gap_pct.abs, verdict ]
end

def levers(p)
  rows = era_rows(p)
  ecb, ccm = rows
  floor_s = p[:delta_t_slow_s]
  puts "ARCH.8 — ЦІНА ВАЖЕЛІВ РОЗВИЛКИ (вимір, НЕ вибір)"
  if ccm[:m].positive?
    # На цих входах дефіциту немає, тож ціни (а)–(в) описували б ремонт того, що не зламано:
    # їхні формули дають від'ємні відсотки. Друкуємо те, що справді судить розвилку, — запас у
    # неміряних входах, — і лишаємо (г)–(д), бо вони від стану точки не залежать.
    puts format("  На цих входах CCM-кадр 30 Б ставить Δt на %.0f с — ПЕРЕД підлогою %.0f с (m = %.3f),",
                ccm[:delta_t_s], floor_s, ccm[:m])
    puts "  тож НА МОДЕЛІ жоден важіль не потрібен. Розвилку тримають входи, яких модель не міряла,"
    puts "  і найдешевше з'їсти запас — стоком на VSTOR, для якого чисел немає:"
    puts format("      CCM-точка витримує ≤ %.0f нА додаткового стоку · ECB-точка — ≤ %.0f нА.",
                ccm[:sink_headroom_na], ecb[:sink_headroom_na])
    puts "      Сюди лягають струм спокою клампа VSTOR (HW.12) і самопрозряд EDLC (HW.37) — число"
    puts "      першого дає аркуш клампа, другого не нормує паспорт; кожен окремо може з'їсти запас CCM."
    puts "  Ціни (а)–(в) мають сенс лише на входах, що кладуть CCM за підлогу, напр.:"
    puts format("      ruby tools/firmware/tx_cadence_budget.rb --levers i_bq_quiescent_na=%.0f",
                p[:i_bq_quiescent_na] + ccm[:sink_headroom_na].ceil + 50)
    puts
    levers_sf_and_rx(p, ecb, ccm, floor_s)
    return 0
  end
  puts format("  Предмет: CCM-кадр 30 Б штовхає Δt на %.0f с, а метаболічна підлога стоїть на %.0f с.",
              ccm[:delta_t_s], floor_s)
  puts "  Кожен важіль нижче повертає робочу точку всередину смуги. Ціни НЕ однорідні."
  puts
  # ── (а) підняти стелю метаболічного відображення ────────────────────────
  need_alive = ccm[:delta_t_s]
  m_target = ecb[:m]
  # m(Δt) = (SLOW − Δt)/(SLOW − FAST) = m_target  ⇒  SLOW = (Δt − m·FAST)/(1 − m)
  need_same_gp = (ccm[:delta_t_s] - m_target * p[:delta_t_fast_s]) / (1.0 - m_target)
  puts format("  (а) DELTA_T_SLOW_S: %.0f с сьогодні.", floor_s)
  puts "      ⛔ ВІДХИЛЕНО ⚖️ 2026-09-22 (делеговано, 00_07 ARCH.8; дім заборони — 03_04 §4.3):"
  puts "         це placeholder БІОЛОГІЧНОЇ калібрації, і радіо-число його не заселяє."
  puts "         Числа нижче — підстава відхилення, не меню."
  puts format("      щоб m лишалось > 0 . . . . . . . . . > %.0f с  (+%.1f %%)",
              need_alive, 100.0 * (need_alive / floor_s - 1.0))
  puts format("      щоб m ЛИШИЛОСЬ тим самим (%.3f) . . . %.0f с  (+%.1f %%)",
              m_target, need_same_gp, 100.0 * (need_same_gp / floor_s - 1.0))
  puts "      🔴 Перший рядок — пастка: він рятує ПРАПОРЕЦЬ, не гроші. Ледь вище за Δt"
  puts "         дає m ≈ 0, тобто ту саму підлогу GP."
  puts "      🔴 АЛЕ Й ДРУГИЙ грошової лінії НЕ ТРИМАЄ — виправлено 2026-09-12 адверсарним ревʼю."
  puts "         Бали нараховуються НА ПАКЕТ, а SCC = пакети/добу × GP/пакет (`scc_rate.rb`)."
  puts "         Важіль (а) повертає ДРУГИЙ множник і не може торкнутись ПЕРШОГО: частота"
  puts "         пакетів упала разом із Δt і лишається впалою."
  puts "      ⛔ І ЦЕЙ ВАЖІЛЬ СЬОГОДНІ НЕ ПРАЦЮЄ ЖОДНИМ ПРИЛАДОМ. Щоб його оцінити, треба"
  puts format("         рухати ДВА числа — робочу точку (Δt=%.0f) І стелю (DELTA_T_SLOW_S=%.0f), —",
              ccm[:delta_t_s], need_same_gp)
  puts "         а `scc_rate.rb` override має лише для першого й бере стелю з константи."
  puts format("         ⚠️ Тому `scc_rate.rb variant_c_s=%.0f` моделює «Δt поїхав, стеля лишилась»,", need_same_gp)
  puts "         тобто протилежне до важеля. Не цитувати як його ціну."
  puts "      ціна, якою він коштував би: SHA-пін `metabolic_gp_core` + чотири дзеркала руками."
  puts
  # ── (б) підняти генерацію ───────────────────────────────────────────────
  puts format("  (б) P_gen: %.1f µW сьогодні.", p[:p_gen_uw])
  [ [ "щоб H лишився на точці ECB", ecb[:h_hours] ],
    [ "щоб Δt не вийшов за підлогу", floor_s / 3600.0 ] ].each do |why, h_target|
    need_pgen = (ccm[:e_active_mj] / h_target + e_sleep_mj_h(p)) / (3600.0 * p[:eta_boost] / 1000.0)
    puts format("      %-34s %6.1f µW  (+%.1f %%)", "#{why} . . . . . . . . . ."[0, 34],
                need_pgen, 100.0 * (need_pgen / p[:p_gen_uw] - 1.0))
  end
  puts "      ⛔ Читати з застереженням шапки: 15 µW сам канон зве числом без джерела,"
  puts "         тож цей важіль дешевий почасти тому, що його вхід найменш певний."
  puts
  # ── (в) різати ефір ─────────────────────────────────────────────────────
  puts format("  (в) стеля airtime: кадр сьогодні %.1f мс.", ccm[:t_air_ms])
  [ [ "щоб H лишився на точці ECB", ecb[:h_hours] ],
    [ "щоб Δt не вийшов за підлогу", floor_s / 3600.0 ] ].each do |why, h_target|
    # Кадр платить TX і TCXO на своєму ефірі; RX-вікно й TCXO на ньому — фіксовані.
    allowed_tx = h_target * net_mj_h(p) * p[:eta_buck_active] - p[:lorenz_mj] -
                 e_rx_mj(p) - e_tcxo_mj(p, 0.0)
    allowed_ms = allowed_tx / ((p[:i_tx_ma] + p[:i_tcxo_ma]) * p[:v_out]) * 1000.0
    puts format("      %-34s ≤ %.1f мс", "#{why} . . . . . . . . . ."[0, 34], allowed_ms)
  end
  puts "      → перевести стелю в БАЙТИ просить сусіда, бо ToA має один дім:"
  puts "        ruby tools/firmware/lora_airtime.rb      (таблиця символьних блоків)"
  puts "      ⚠️ ToA ступінчаста, тож стеля між блоками не купує нічого — платить"
  puts "         лише перехід у нижчий блок."
  puts "      🔴 А віддавати нема чого: 30 Б = DID 4 (незнімний) + gossip 1 + FC 3 + sensor 14 + MIC 8"
  puts "         (03_05 §2.1), і кожен набір байтів, що переводить кадр у нижчий блок, — несучий:"
  puts "         автентифікація (MIC) ⊥ анти-реплей (FC, та сама вісь, що born-vuln-нога ARCH.8) ⊥"
  puts "         самі поля свідчення (device_z → DCI, ema_delta_t → вхід GP, temp/vpd → confounder)."
  puts "         Тобто (в) не «зріз payload», а вибір, ЯКУ ногу критерію місії зрізати."
  puts
  levers_sf_and_rx(p, ecb, ccm, floor_s)
  0
end

# (г)–(д) від стану точки не залежать: SF міняє ефір, а не енергобаланс, а RX-вікно — член циклу,
# який прошивка задумала гейтувати, — тож друкуються й тоді, коли дефіциту на моделі немає.
def levers_sf_and_rx(p, ecb, ccm, floor_s)
  puts "  (г) SF: SF9 сьогодні — ВАЖІЛЬ, якого розвилка не називала до 2026-09-22."
  puts "      Формула Semtech параметризована ним, тож ціна рахується без жодної зміни"
  puts "      профілю: ruby tools/firmware/lora_airtime.rb sf-sweep=30"
  puts "      Виміряно: SF8 з ПОВНИМ 30-байтним кадром коштує 123.4 мс — менше, ніж"
  puts "      сьогоднішній 16-байтний ECB-кадр на SF9 (164.9 мс). Тобто цей важіль закрив би"
  puts "      дефіцит, щойно вимір його покаже, не торкнувшись ані грошей, ані свідчення."
  puts "      🔴 Його валюта — ЗАПАС ЗВ'ЯЗКУ, і саме тому він не дешевий, а ІНШИЙ:"
  puts "         SF9 обрано як КОМПЕНСАЦІЮ зниження TX +22 → +14 дБм (02_03 §9.6),"
  puts "         і накладено її на запас, який 02_01 §5.3 рахує як +47 дБ у найгіршому"
  puts "         випадку при НАЙСУВОРІШОМУ SF7."
  puts "      ⛔ Але той +47 дБ — ДЕСКТОПНИЙ розрахунок, і 02_03 §9.8 сам каже, що"
  puts "         справжній link budget потребує польового виміру; §5.3 при цьому"
  puts "         чутливості для SF9 навіть не наводить. Отже (г) НЕ ратифікується"
  puts "         сьогодні — він чекає того самого RF-макета, що й HW.33, якщо той"
  puts "         прогнати на ДВОХ SF замість одного (макет дає ЧУТЛИВІСТЬ/PER на SF8;"
  puts "         запас лінка з втратами шляху лишається польовим виміром)."
  puts
  # ── (д) ворота RX-вікна ──────────────────────────────────────────────────
  no_rx = p.merge(t_rx_ms: 0.0)
  puts "  (д) RX-вікно: прошивка ЗАДУМАЛА його енергетичні ворота («слухаємо, лише якщо багаті"
  puts "      на енергію», vcap > 2800), але `vcap` читає VDDA, тож вікно відкрите щоциклу."
  puts format("      Воно коштує %.2f мДж RX + %.2f мДж TCXO на VOUT, тобто %.0f %% E_active ECB-ери.",
              e_rx_mj(p), e_tcxo_mj(p, 0.0), 100.0 * (e_rx_mj(p) + e_tcxo_mj(p, 0.0)) / p[:eta_buck_active] / ecb[:e_active_mj])
  puts format("      Без нього: H ECB %.2f → %.2f год, H CCM %.2f → %.2f год (підлога %.2f).",
              ecb[:h_hours], interval_h(no_rx, WIRE_ERAS[0][2]), ccm[:h_hours], interval_h(no_rx, WIRE_ERAS[1][2]),
              floor_s / 3600.0)
  puts "      🔴 Валюта — ДОСЯЖНІСТЬ вузла: це вікно несе маяк часу, OTA й команди Королеви, тож"
  puts "         пропуск його — вибір, що саме перестає чути вузол у дефіциті. Справжні ворота"
  puts "         потребують справжнього каналу запасу енергії — топологію присуджено (FW.50: TPS22860-гейт,"
  puts "         ⚖️ делеговано 2026-09-27), а каналу ще нема: розводка й прошивка на новому піні."
  puts
  puts "  ⛔ ВИБОРУ ТУТ НЕМАЄ І НЕ БУДЕ: розвилка є присудом (00_07 ARCH.8), і поки"
  puts "     вона відкрита, CCM не відвантажується. Значення й точність робочої точки"
  puts "     міряють сусіди: scc_rate.rb variant_c_s=<с> · uncertainty_budget.rb delta_t_s=<с>."
  0
end

def assert_mode(p)
  problems = []
  canon = File.read(CANON_DOC)
  rows = era_rows(p)
  rows.each do |r|
    # 1. Транскрипція airtime ЖИВА: виведене E_TX мусить дослівно стояти в каноні.
    unless canon.include?(r[:canon_literal])
      problems << "E_TX-літерал #{r[:canon_literal]} (#{r[:payload_b]} Б) зник із 02_03 — " \
                  "або канон переписали, або транскрипція airtime протухла"
    end
    unless (r[:e_tx_mj] - Float(r[:canon_literal])).abs < 0.05
      problems << format("E_TX(%d Б) модель %.2f ≠ канон %s", r[:payload_b], r[:e_tx_mj], r[:canon_literal])
    end
  end
  ecb, ccm = rows
  # 2. Модель відтворює надруковані в §9.6 проміжні числа Сценарію C.
  { "E_RX (§9.4, 7.95 мДж)" => (ecb[:e_rx_mj] - 7.95).abs < 0.01 && canon.include?("7.95 мДж"),
    "E_TCXO ECB (§9.4, 4.63 мДж)" => (ecb[:e_tcxo_mj] - 4.63).abs < 0.01 && canon.include?("4.63 мДж"),
    "E_TCXO CCM (§9.6 врізка, 5.06 мДж)" => (ccm[:e_tcxo_mj] - 5.06).abs < 0.01 && canon.include?("5.06 мДж"),
    "E_active ECB (§9.6, 33.33 мДж)" => (ecb[:e_active_mj] - 33.33).abs < 0.05 && canon.include?("33.33 мДж"),
    "E_active CCM (§9.6 врізка, 39.23 мДж)" => (ccm[:e_active_mj] - 39.23).abs < 0.05 && canon.include?("39.23 мДж"),
    "E_sleep (§9.6, 15.04 мДж/год)" => (e_sleep_mj_h(p) - 15.04).abs < 0.02,
    "E_gen (§9.6, 36.7 мДж/год)" => (e_gen_mj_h(p) - 36.7).abs < 0.05,
    "H ECB (§9.6, 1.54 год)" => (ecb[:h_hours] - 1.54).abs < 0.02,
    "H CCM (§9.6 врізка, 1.81 год)" => (ccm[:h_hours] - 1.81).abs < 0.02,
    # ⚠️ Доданий 2026-09-12, і не для повноти: рядок CCM-ери в таблиці §9.7 несе саме це
    # число, а врізка над таблицею обіцяла, що «числа звідси HARD-гейтовані проти моделі» —
    # обіцянка була ШИРША за реалізацію (клас сліпоти #5 `ssot-maintenance`: гейт недовиконує оголошений
    # контракт). «≈0» рядка C окремо не пінеться: на беззапасній каденції баланс нуль за
    # визначенням `H`, тож його тримає пін `H ECB` вище.
    "E_net CCM на каденції ECB (§9.7 рядок CCM-ери, −3.84 мДж/год)" =>
      (ccm[:e_net_at_ref_cadence_mj_h] + 3.84).abs < 0.05,
    # Запас стоку VSTOR — нова вісь розвилки після зрізу пʼєзо: канон цитує його поруч із
    # typ клампа й самопрозрядом EDLC, тож число мусить стояти в каноні дослівно.
    "запас стоку VSTOR до підлоги CCM (§9.7, ≤ 128 нА)" =>
      (ccm[:sink_headroom_na] - 128).abs < 1.0 && canon.include?("128 нА"),
    "запас стоку VSTOR до підлоги ECB (§9.7, ≤ 310 нА)" =>
      (ecb[:sink_headroom_na] - 310).abs < 1.0 && canon.include?("310 нА") }.each do |label, ok|
    problems << "не відтворюється: #{label}" unless ok
  end
  # 3. Предмет, заради якого модель існує, — бік метаболічної підлоги для кожної ери кадру.
  #    ECB-точка (відвантажена ера) мусить стояти перед нею; половина про CCM — інваріант 5.
  problems << "ECB-точка вже за підлогою m — предмет розвилки змінився" unless ecb[:m] > 0.0
  # 4. Грошова робоча точка сусідів не сміє відстати від ланцюга, який виконує прошивка, — судимо
  #    ГРОШИМА: та сама сходинка wire-GP і SCC у межах u_Δt після EMA (⚖️ делеговано 2026-09-27,
  #    00_07 ARCH.8); і обидва сусіди мусять стояти на ОДНІЙ точці (⚖️ founder 2026-09-26).
  mm = money_model
  if money_model_complete?(mm)
    problems << format("грошові дефолти розійшлись між собою: scc_rate %.0f с ⊥ uncertainty_budget %.0f с",
                       mm[:point_s], mm[:unc_point_s]) unless mm[:point_s] == mm[:unc_point_s]
    # Смуга підлоги тут (PARAMS) і смуга сходинок у домі грошей — одна: інакше «бік підлоги» й
    # «сходинка» рахувались би з різних чисел і суперечили б одне одному без жодного сигналу.
    unless PARAMS[:delta_t_fast_s] == mm[:band][:fast_s] && PARAMS[:delta_t_slow_s] == mm[:band][:slow_s]
      problems << format("смуга m розійшлась: PARAMS %.0f/%.0f с ⊥ scc_rate.rb DELTA_T_FAST_S/SLOW_S %.0f/%.0f с",
                         PARAMS[:delta_t_fast_s], PARAMS[:delta_t_slow_s], mm[:band][:fast_s], mm[:band][:slow_s])
    end
    v = money_verdict(mm, ecb[:delta_t_s])
    if !v[:same_step]
      problems << format("грошова точка %.0f с і енергомодель %.0f с стоять на РІЗНИХ сходинках wire-GP (%d ⊥ %d): "\
                         "SCC %.2f ⊥ %.2f/дерево/рік — рухати точку присудом (00_07 ARCH.8)", mm[:point_s],
                         ecb[:delta_t_s], v[:w_money], v[:w_energy], v[:scc_money], v[:scc_energy])
    elsif v[:gap_pct].abs > v[:tol_pct]
      problems << format("грошова точка %.0f с ⊥ енергомодель %.0f с: SCC розійшлись на %+.1f %% — поза ±%.2f %% "\
                         "u_Δt після EMA; рухати точку присудом (00_07 ARCH.8)", mm[:point_s], ecb[:delta_t_s],
                         v[:gap_pct], v[:tol_pct])
    end
  else
    problems << "не знайдено числа грошової моделі (scc_rate.rb: VARIANT_C_S · DELTA_T_* · GP_HOMEO_* · "\
                "BACKEND_UPSCALE · EMISSION_THRESHOLD; uncertainty_budget.rb: delta_t_s · u_delta_t_raw_pct · ema_alpha)"
  end
  # 5. Предмет розвилки після зрізу пʼєзо (⚖️ 2026-09-29): на моделі CCM-точка стоїть ПЕРЕД підлогою,
  #    і розвилку тримають лише неміряні входи. Точка, що знову лягла за підлогу, означає, що якийсь
  #    вхід моделі змінив предмет розвилки назад — канон тоді бреше, а не «розвилку закрито».
  problems << "CCM-точка знову за підлогою m — вхід моделі повернув розвилку ARCH.8 на моделі" unless ccm[:m].positive?
  problems.each { |x| warn "FAIL  #{x}" }
  if problems.empty?
    where, gap_pct, verdict = floor_side(p, ecb, dt_tolerance_pct(mm))
    puts format("✅ tx_cadence_budget: H %.2f год (ECB 16 Б) → %.2f год (CCM 30 Б); підлога m на %.0f с — "\
                "CCM-точка перед нею (стік VSTOR ≤ %.0f нА), ECB-точка стоїть %s (%.1f %% від Δt — %s); "\
                "розвилка ARCH.8 — очікування вимірів, не важеля; гроші: %s", ecb[:h_hours], ccm[:h_hours],
                p[:delta_t_slow_s], ccm[:sink_headroom_na], where, gap_pct, verdict, money_step_note(mm))
  end
  problems.empty? ? 0 : 1
end

exit(case mode
when :levers then levers(params)
when :assert then assert_mode(params)
else report(params)
end)
