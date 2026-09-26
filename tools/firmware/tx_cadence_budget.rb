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
#   ruby tools/firmware/tx_cadence_budget.rb --levers   # ціна кожного важеля розвилки ARCH.8
#   ruby tools/firmware/tx_cadence_budget.rb --assert   # гейт: модель відтворює надруковані числа
#   ruby tools/firmware/tx_cadence_budget.rb p_gen_uw=17.13   # override будь-якого параметра
#
# ⛔ ЩО ЦЕЙ ФАЙЛ НЕ РОБИТЬ — і це не скромність, а межа мандату. Розвилка ARCH.8
# стоїть ВІДКРИТОЮ, але ⚖️ 2026-09-22 (делеговано) її звужено: (а) підняти
# DELTA_T_SLOW_S — ВІДХИЛЕНО · (б) підняти P_gen — не важіль, а ВИМІР, якого ще
# немає · (в) різати payload — ціна в байтах · (г) SF — доданий четвертий. Тут —
# ціна кожного; ціни (а) лишаються як ПІДСТАВА відхилення. Вибір лишається присудом.
#
# ⛔ І ДРУГЕ, чого він не робить: він не перекладає мілісекунди в БАЙТИ. ToA має
# один дім — `tools/firmware/lora_airtime.rb` (модель Semtech + профіль із
# `firmware/common/lora_phy.h`). Тут стеля airtime рахується, а перевести її в
# довжину кадру просить сусіда командою, яку сам і друкує.
#
# Ті самі під-цикли (TinyML · Lorenz · η_buck) і той самий сон-стік рахує й
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
#     «SYSCLK від MSI»; від HSE32 — ще +2.44 мДж) · самопрозряду EDLC (`02_03 §9.3`, FAE).
#     Отже H нижче — НИЖНЯ межа цього ж ланцюга, а η_buck 0.88 при ~24 мА стоїть на краю
#     діапазону, для якого канон її тримає.
#   • `t_air_ms` — транскрипція з `lora_airtime.rb` §ENERGY_ANCHORS (той самий
#     набір, що вже гейтований проти 02_03 §9.6 ВЛАСНИМ асертом сусіда). Транскрипція ЖИВА доводиться
#     нижче: `--assert` вимагає, щоб виведене E_TX збіглося з числом, надрукованим
#     у каноні — ⚠️ але це ловить дрейф МОДЕЛІ, а дрейф сусіда ловить сусідів гейт; смуга
#     тут ±0.64 мс airtime (допуск 0.05 мДж ÷ 23.5 мА × 3.3 В), тобто пін НЕ тугий.
#   • `eta_boost = 0.68` — це точка §9.1 при P_in = 15 µW, і вона є функцією ВХІДНОЇ
#     ПОТУЖНОСТІ, а не сезону (⚠️ поправка 2026-09-12: доти тут стояло «літня точка»).
#     🔴 Наслідок для важеля (б): піднімаючи `p_gen_uw` до 15.8/17.1, модель тримає η на
#     значенні для 15 — тобто друковані +5.5 %/+14.2 % ЗАВИЩЕНІ приблизно на 0.6-1.6 в.п.
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

PARAMS = {
  # ── активний цикл на VOUT (02_03 §9.4 / §9.6 Сценарій C) ──────────────────
  tinyml_mj: 7.92,
  lorenz_mj: 3.96,
  i_tx_ma: 23.5,            # STM32WL RFO_LP +14 dBm, SMPS — DS13105 Табл. 29 (⚖️ SMPS 2026-09-26)
  i_rx_ma: 4.82,            # RX LoRa 125 кГц, SMPS — DS13105 Табл. 28
  t_rx_ms: 500.0,           # LORA_RX_TIMEOUT_MS — пост-TX вікно, відкрите ЩОЦИКЛУ (soldier/main.c, Фаза 4.5)
  i_tcxo_ma: 2.11,          # NT2016SF max 2.0 + Iq 0.07 + 2 % (⚖️ TCXO 2026-09-26) — живий на TX і на RX
  v_out: 3.3,
  eta_buck_active: 0.88,
  # ── сон (Сценарій C: STOP2 RTC-only, §9.6) ───────────────────────────────
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
  EC.active_cycle_from_vstor_mj(tinyml_mj: p[:tinyml_mj], lorenz_mj: p[:lorenz_mj],
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
# точка: канон бере трохи довший інтервал і тому друкує «+1.4 мДж/год».
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
  puts format("    звідки H %.2f → %.2f год. ⚠️ Але вирішує не H, а ПОРІГ: m сідає на нуль на",
              ecb[:h_hours], ccm[:h_hours])
  puts format("    Δt = %.0f с (%.2f год), тобто ДО точки CCM — отже GP падає на підлогу, а не",
              p[:delta_t_slow_s], p[:delta_t_slow_s] / 3600.0)
  puts "    пропорційно. «H зріс» і «мінт упав» — різні твердження з різними порогами."
  puts format("  → Якщо кадр підмінити, а КАДЕНЦІЮ лишити на %.2f год: баланс %+.2f мДж/год.",
              ecb[:h_hours], ccm[:e_net_at_ref_cadence_mj_h])
  puts format("  → Запас чинної робочої точки до підлоги: %.0f с (%.1f хв); перехід просить %.0f с (%.1f хв).",
              p[:delta_t_slow_s] - ecb[:delta_t_s], (p[:delta_t_slow_s] - ecb[:delta_t_s]) / 60.0,
              ccm[:delta_t_s] - ecb[:delta_t_s], (ccm[:delta_t_s] - ecb[:delta_t_s]) / 60.0)
  puts
  money_default_s = 6372.0 # дефолт `scc_rate.rb` / `uncertainty_budget.rb` — ГРОШОВА робоча точка
  gap_pct = 100.0 * (ecb[:delta_t_s] / money_default_s - 1.0)
  puts format("  ⚠️ Грошові моделі (scc_rate.rb, uncertainty_budget.rb) беруть дефолтом %.0f с; ця модель дає"\
              " %.0f с — різниця %+.1f %%.", money_default_s, ecb[:delta_t_s], gap_pct)
  if gap_pct.abs <= 8.0
    puts "     Це всередині ±8 % `u_delta_t_raw_pct` (STK.5): округлення, не розбіжність."
  else
    puts "     🔴 Це ПОЗА ±8 % `u_delta_t_raw_pct` (STK.5): уже не округлення, а розбіжність — дефолт"
    puts "     відстає від ланцюга, який виконує прошивка. ⛔ Рухати його можна лише присудом"
    puts "     (00_07 ARCH.8, ⚖️-нога): від нього залежать гроші, а не лише цей звіт."
  end
  puts format("  → ECB-точка стоїть за %.0f с до підлоги (%.1f %% від Δt) — %s.",
              p[:delta_t_slow_s] - ecb[:delta_t_s],
              100.0 * (p[:delta_t_slow_s] - ecb[:delta_t_s]) / ecb[:delta_t_s],
              (p[:delta_t_slow_s] - ecb[:delta_t_s]) / ecb[:delta_t_s] <= 0.08 ?
                "ВСЕРЕДИНІ ±8 % невизначеності Δt, тобто «перед підлогою» тут не доведено" :
                "поза смугою невизначеності Δt")
  0
end

def levers(p)
  rows = era_rows(p)
  ecb, ccm = rows
  floor_s = p[:delta_t_slow_s]
  puts "ARCH.8 — ЦІНА ВАЖЕЛІВ РОЗВИЛКИ (вимір, НЕ вибір)"
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
    allowed_tx = h_target * net_mj_h(p) * p[:eta_buck_active] - p[:tinyml_mj] - p[:lorenz_mj] -
                 e_rx_mj(p) - e_tcxo_mj(p, 0.0)
    allowed_ms = allowed_tx / ((p[:i_tx_ma] + p[:i_tcxo_ma]) * p[:v_out]) * 1000.0
    puts format("      %-34s ≤ %.1f мс", "#{why} . . . . . . . . . ."[0, 34], allowed_ms)
  end
  puts "      → перевести стелю в БАЙТИ просить сусіда, бо ToA має один дім:"
  puts "        ruby tools/firmware/lora_airtime.rb      (таблиця символьних блоків)"
  puts "      ⚠️ ToA ступінчаста, тож стеля між блоками не купує нічого — платить"
  puts "         лише перехід у нижчий блок."
  puts "      🔴 І СХОДИНКА ПЕРЕКЛАДАЄ ЦЮ СТЕЛЮ В БАЙТИ ЖОРСТКО (вимір 2026-09-26, з RX-вікном і TCXO):"
  puts "         щоб утриматись у підлозі, кадр мусить стати ≤ 17 Б (блок 13..17 = 164.9 мс;"
  puts "         18..21 = 185.3 мс уже за стелею), тобто ВІДДАТИ 13 — а це й є ECB-довжина."
  puts "         А віддавати нема чого: 30 Б = DID 4 (незнімний) + gossip 1 + FC 3 +"
  puts "         sensor 14 + MIC 8 (03_05 §2.1). Кожен можливий набір із 13 байтів —"
  puts "         несучий: автентифікація (MIC) ⊥ анти-реплей (FC, та сама вісь, що"
  puts "         born-vuln-нога ARCH.8) ⊥ самі поля свідчення (device_z → DCI,"
  puts "         ema_delta_t → вхід GP, acoustic → пилка, temp/vpd → confounder)."
  puts "         Тобто (в) не «зріз payload», а вибір, ЯКУ ногу критерію місії зрізати."
  puts
  puts "  (г) SF: SF9 сьогодні — ВАЖІЛЬ, якого розвилка не називала до 2026-09-22."
  puts "      Формула Semtech параметризована ним, тож ціна рахується без жодної зміни"
  puts "      профілю: ruby tools/firmware/lora_airtime.rb sf-sweep=30"
  puts "      Виміряно: SF8 з ПОВНИМ 30-байтним кадром коштує 123.4 мс — менше, ніж"
  puts "      сьогоднішній 16-байтний ECB-кадр на SF9 (164.9 мс). Тобто цей важіль"
  puts "      закриває дефіцит, не торкнувшись ані грошової лінії, ані свідчення."
  puts "      🔴 Його валюта — ЗАПАС ЗВ'ЯЗКУ, і саме тому він не дешевий, а ІНШИЙ:"
  puts "         SF9 обрано як КОМПЕНСАЦІЮ зниження TX +22 → +14 дБм (02_03 §9.6),"
  puts "         і накладено її на запас, який 02_01 §5.3 рахує як +47 дБ у найгіршому"
  puts "         випадку при НАЙСУВОРІШОМУ SF7."
  puts "      ⛔ Але той +47 дБ — ДЕСКТОПНИЙ розрахунок, і 02_03 §9.8 сам каже, що"
  puts "         справжній link budget потребує польового виміру; §5.3 при цьому"
  puts "         чутливості для SF9 навіть не наводить. Отже (г) НЕ ратифікується"
  puts "         сьогодні — він чекає того самого RF-макета, що й HW.33, якщо той"
  puts "         прогнати на ДВОХ SF замість одного."
  puts
  # ── (д) ворота RX-вікна ──────────────────────────────────────────────────
  no_rx = p.merge(t_rx_ms: 0.0)
  puts "  (д) RX-вікно: прошивка ЗАДУМАЛА його енергетичні ворота («слухаємо, лише якщо багаті"
  puts "      на енергію», vcap > 2800), але `vcap` читає VDDA, тож вікно відкрите щоциклу."
  puts format("      Воно коштує %.2f мДж RX + %.2f мДж TCXO на VOUT, тобто %.0f %% E_active ECB-ери.",
              e_rx_mj(p), e_tcxo_mj(p, 0.0), 100.0 * (e_rx_mj(p) + e_tcxo_mj(p, 0.0)) / p[:eta_buck_active] / ecb[:e_active_mj])
  puts format("      Без нього в дефіцитному циклі: H ECB %.2f → %.2f год, H CCM %.2f → %.2f год (підлога %.2f).",
              ecb[:h_hours], interval_h(no_rx, WIRE_ERAS[0][2]), ccm[:h_hours], interval_h(no_rx, WIRE_ERAS[1][2]),
              floor_s / 3600.0)
  puts "      🔴 Валюта — ДОСЯЖНІСТЬ вузла: це вікно несе маяк часу, OTA й команди Королеви, тож"
  puts "         пропуск його — вибір, що саме перестає чути вузол у дефіциті. Справжні ворота"
  puts "         потребують справжнього каналу запасу енергії — відкрита ⚖️ топології Vcap (FW.50)."
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
    "E_active ECB (§9.6, 42.33 мДж)" => (ecb[:e_active_mj] - 42.33).abs < 0.05,
    "E_active CCM (§9.6 врізка, 48.23 мДж)" => (ccm[:e_active_mj] - 48.23).abs < 0.05,
    "E_sleep (§9.6, 15.04 мДж/год)" => (e_sleep_mj_h(p) - 15.04).abs < 0.02,
    "E_gen (§9.6, 36.7 мДж/год)" => (e_gen_mj_h(p) - 36.7).abs < 0.05,
    "H ECB (§9.6, 1.95 год)" => (ecb[:h_hours] - 1.95).abs < 0.02,
    "H CCM (§9.6 врізка, 2.22 год)" => (ccm[:h_hours] - 2.22).abs < 0.02,
    # ⚠️ Доданий 2026-09-12, і не для повноти: рядок CCM-ери в таблиці §9.7 несе саме це
    # число, а врізка над таблицею обіцяла, що «числа звідси HARD-гейтовані проти моделі» —
    # обіцянка була ШИРША за реалізацію (клас сліпоти #5 `ssot-maintenance`: гейт недовиконує оголошений
    # контракт). Пін вужчий за обіцянку лише в один бік: `+1.4` рядка C НЕ пінеться тут і не
    # може — воно взяте на трохи довшій каденції, ніж беззапасне `H`, тож належить §9.6.
    "E_net CCM на каденції ECB (§9.7 рядок CCM-ери, −3.0 мДж/год)" =>
      (ccm[:e_net_at_ref_cadence_mj_h] + 3.0).abs < 0.05 }.each do |label, ok|
    problems << "не відтворюється: #{label}" unless ok
  end
  # 3. Присуд, заради якого модель існує: CCM-точка лежить ЗА метаболічною підлогою,
  #    а ECB-точка — перед нею. Порушення будь-якої половини робить розвилку іншою.
  problems << "ECB-точка вже за підлогою m — предмет розвилки змінився" unless ecb[:m] > 0.0
  problems << "CCM-точка більше НЕ за підлогою m — розвилка ARCH.8 може бути закрита" unless ccm[:m].zero?
  problems.each { |x| warn "FAIL  #{x}" }
  if problems.empty?
    puts format("✅ tx_cadence_budget: H %.2f год (ECB 16 Б) → %.2f год (CCM 30 Б); підлога m на %.0f с — "\
                "CCM-точка за нею, ECB перед нею на %.0f с (у межах ±8 %% Δt — номінально), розвилка ARCH.8 відкрита",
                ecb[:h_hours], ccm[:h_hours], p[:delta_t_slow_s], p[:delta_t_slow_s] - ecb[:delta_t_s])
  end
  problems.empty? ? 0 : 1
end

exit(case mode
when :levers then levers(params)
when :assert then assert_mode(params)
else report(params)
end)
