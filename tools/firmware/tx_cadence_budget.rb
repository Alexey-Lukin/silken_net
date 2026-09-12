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
#   ruby tools/firmware/tx_cadence_budget.rb --levers   # ціна трьох важелів розвилки ARCH.8
#   ruby tools/firmware/tx_cadence_budget.rb --assert   # гейт: модель відтворює надруковані числа
#   ruby tools/firmware/tx_cadence_budget.rb p_gen_uw=17.13   # override будь-якого параметра
#
# ⛔ ЩО ЦЕЙ ФАЙЛ НЕ РОБИТЬ — і це не скромність, а межа мандату. Розвилка ARCH.8
# («підняти DELTA_T_SLOW_S ⊥ підняти P_gen ⊥ різати payload») стоїть ВІДКРИТОЮ з
# приписом «жодного з трьох не обирати до виміру». Тут — саме той вимір: кожен
# важіль отримує ЧИСЛО і названу ціну. Вибір лишається присудом.
#
# ⛔ І ДРУГЕ, чого він не робить: він не перекладає мілісекунди в БАЙТИ. ToA має
# один дім — `tools/firmware/lora_airtime.rb` (модель Semtech + профіль із
# `firmware/common/lora_phy.h`). Тут стеля airtime рахується, а перевести її в
# довжину кадру просить сусіда командою, яку сам і друкує.
#
# ⚠️ СВІДОМА ДУБЛЬ-ПОВЕРХНЯ, названа вголос [transitional]. Ті самі під-цикли
# (TinyML · Lorenz · η_buck) і той самий сон-стік живуть у
# `tools/firmware/boot_brownout_cycle.rb` — під ІНШЕ питання (гістерезисне вікно
# HW.44), тому файли не злиті. Стеля: третьої копії бути не повинно, а другу
# знімає винесення ланцюга у спільний `lib/` — ⛔ не робити цього тим самим
# комітом, що заводить модель: `boot_brownout_cycle.rb` сам себе звіряє з
# надрукованими в 02_03 числами, тож рефактор без окремої мутаційної перевірки
# роззброїть його мовчки. Шлях апгрейпу → `00_07` ARCH.8.
#
# ⛔ СТЕЛІ ВХОДІВ, оголошені вголос — інакше зелений прогін почне означати «правда»:
#   • `p_gen_uw = 15` — канон сам зве це «робоче число БЕЗ простежуваного джерела»
#     (02_03 §9.2), і між ним та L4-моделлю (~140 µW) стоїть розрив, який тримає
#     HW.46. 🔴 Наслідок для читання важеля (б): він виглядає найдешевшим саме
#     тому, що його вхід найменш певний. Це не аргумент за нього й не проти —
#     це попередження не цитувати «+5.6 %» як інженерний запас.
#   • `t_air_ms` — транскрипція з `lora_airtime.rb` §ENERGY_ANCHORS (той самий
#     набір, що вже гейтований проти 02_03 §9.6). Транскрипція ЖИВА доводиться
#     нижче: `--assert` вимагає, щоб виведене E_TX збіглося з числом, надрукованим
#     у каноні. Дрейф сусіда й дрейф моделі ловляться одним і тим самим асертом.
#   • `eta_boost = 0.68` — літня точка §9.1. Зимову (0.65) тримає HW.44-модель,
#     і мішати їх не можна: тут питання про річну каденцію, не про виживання.
#   • Ланцюг зупиняється на `H`. Крок `H → Δt → m → GP → SCC` має власні доми
#     (`scc_rate.rb` для значення, `uncertainty_budget.rb` для точності), і цей
#     файл їх КЛИЧЕ в `--levers`, а не переписує.

CANON_DOC = File.expand_path("../../docs/02_03_BQ25570_MPPT_Nano_Power.md", __dir__)

PARAMS = {
  # ── активний цикл на VOUT (02_03 §9.4 / §9.6 Сценарій C) ──────────────────
  tinyml_mj: 7.92,
  lorenz_mj: 3.96,
  i_tx_ma: 40.0,            # SX1262 @ +14 dBm (§9.6 Сценарій B, datasheet)
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
  [ "ECB 16 Б (відвантажено сьогодні)", 16, 164.9, "21.78" ],
  [ "CCM 30 Б (wire-rev2.1, FW.2 bench-gated)", 30, 226.3, "29.9" ]
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

def e_active_from_vstor_mj(p, t_air_ms)
  (p[:tinyml_mj] + p[:lorenz_mj] + e_tx_mj(p, t_air_ms)) / p[:eta_buck_active]
end

def sleep_drain_uw(p)
  p[:i_stm32_sleep_na] * 1e-9 * p[:v_out] / p[:eta_buck_sleep] * 1e6 +
    p[:i_bq_quiescent_na] * 1e-9 * p[:v_vstor_avg] * 1e6
end

def e_sleep_mj_h(p) = sleep_drain_uw(p) * 3600.0 / 1000.0
def e_gen_mj_h(p) = p[:p_gen_uw] * 3600.0 * p[:eta_boost] / 1000.0
def net_mj_h(p) = e_gen_mj_h(p) - e_sleep_mj_h(p)

# H — інтервал між пакетами, за якого баланс рівно нульовий. ⚠️ Це БЕЗЗАПАСНА
# точка: канон бере трохи довший інтервал і тому друкує «+1.4 мДж/год».
def interval_h(p, t_air_ms) = e_active_from_vstor_mj(p, t_air_ms) / net_mj_h(p)

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
      e_tx_mj: e_tx_mj(p, t_air), e_active_mj: e_active_from_vstor_mj(p, t_air),
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
  puts format("  ⚠️ Канон друкує робочу точку як 1.77 год = 6372 с (округлена проза); модель дає"\
              " %.0f с.", ecb[:delta_t_s])
  puts "     Різниця 0.4 % лежить глибоко всередині ±8 % `u_delta_t_raw_pct` (STK.5) — це"
  puts "     округлення, не розбіжність. ⛔ Не «виправляти» канон під цей рядок: 6372 стоїть"
  puts "     дефолтом у scc_rate.rb і uncertainty_budget.rb, і рухати його можна лише присудом."
  0
end

def levers(p)
  rows = era_rows(p)
  ecb, ccm = rows
  floor_s = p[:delta_t_slow_s]
  puts "ARCH.8 — ЦІНА ТРЬОХ ВАЖЕЛІВ РОЗВИЛКИ (вимір, НЕ вибір)"
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
  puts format("      щоб m лишалось > 0 . . . . . . . . . > %.0f с  (+%.1f %%)",
              need_alive, 100.0 * (need_alive / floor_s - 1.0))
  puts format("      щоб m ЛИШИЛОСЬ тим самим (%.3f) . . . %.0f с  (+%.1f %%)",
              m_target, need_same_gp, 100.0 * (need_same_gp / floor_s - 1.0))
  puts "      🔴 Перший рядок — пастка: він рятує ПРАПОРЕЦЬ, не гроші. Ледь вище за Δt"
  puts "         дає m ≈ 0, тобто ту саму підлогу GP. Грошову лінію тримає ДРУГИЙ рядок."
  puts "      ціна: SHA-пін `metabolic_gp_core` + чотири дзеркала руками (00_07 ARCH.8)."
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
    allowed_tx = h_target * net_mj_h(p) * p[:eta_buck_active] - p[:tinyml_mj] - p[:lorenz_mj]
    allowed_ms = allowed_tx / (p[:i_tx_ma] * p[:v_out]) * 1000.0
    puts format("      %-34s ≤ %.1f мс", "#{why} . . . . . . . . . ."[0, 34], allowed_ms)
  end
  puts "      → перевести стелю в БАЙТИ просить сусіда, бо ToA має один дім:"
  puts "        ruby tools/firmware/lora_airtime.rb      (таблиця символьних блоків)"
  puts "      ⚠️ ToA ступінчаста, тож стеля між блоками не купує нічого — платить"
  puts "         лише перехід у нижчий блок."
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
  { "E_active ECB (§9.6, 38.25 мДж)" => (ecb[:e_active_mj] - 38.25).abs < 0.05,
    "E_sleep (§9.6, 15.04 мДж/год)" => (e_sleep_mj_h(p) - 15.04).abs < 0.02,
    "E_gen (§9.6, 36.7 мДж/год)" => (e_gen_mj_h(p) - 36.7).abs < 0.05,
    "H ECB (§9.6, 1.77 год)" => (ecb[:h_hours] - 1.77).abs < 0.02,
    "H CCM (§9.6 врізка, 2.19 год)" => (ccm[:h_hours] - 2.19).abs < 0.02 }.each do |label, ok|
    problems << "не відтворюється: #{label}" unless ok
  end
  # 3. Присуд, заради якого модель існує: CCM-точка лежить ЗА метаболічною підлогою,
  #    а ECB-точка — перед нею. Порушення будь-якої половини робить розвилку іншою.
  problems << "ECB-точка вже за підлогою m — предмет розвилки змінився" unless ecb[:m] > 0.0
  problems << "CCM-точка більше НЕ за підлогою m — розвилка ARCH.8 може бути закрита" unless ccm[:m].zero?
  problems.each { |x| warn "FAIL  #{x}" }
  if problems.empty?
    puts format("✅ tx_cadence_budget: H %.2f год (ECB 16 Б) → %.2f год (CCM 30 Б); підлога m на %.0f с — "\
                "CCM-точка за нею, розвилка ARCH.8 відкрита", ecb[:h_hours], ccm[:h_hours], p[:delta_t_slow_s])
  end
  problems.empty? ? 0 : 1
end

exit(case mode
when :levers then levers(params)
when :assert then assert_mode(params)
else report(params)
end)
