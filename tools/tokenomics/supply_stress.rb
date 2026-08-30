#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [E.67] Стрес-тест СТАБІЛЬНОСТІ SUPPLY протоколу — параметрична модель, single-source.
# Канон (05_03 · 05_06 §7) ПОСИЛАЄТЬСЯ сюди, не restate'ить magnitude:
# редагуєш число — тут, канон тримає лише висновки.
# Дзеркало scc_rate.rb (E.63) / queen_energy_budget.rb (HW.39).
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/tokenomics/supply_stress.rb                    # звіт: baseline + активований + стрес
#   ruby tools/tokenomics/supply_stress.rb trees=2000000      # override PARAMS-ключа
#     ⚠️ «будь-якого» тут стояло й було НЕПРАВДОЮ для двох ключів із сімнадцяти —
#     `scc_per_tree_year` і `slash_gamma_voted` кожен сценарій задає явно, тож їхній
#     override мовчки не робив нічого (виміряно вичерпно 2026-08-30). Тепер вони
#     відмовляють ГУЧНО — підстава й перелік у `MATRIX_OWNED` наприкінці файлу.
#   ruby tools/tokenomics/supply_stress.rb --assert           # гейт: інваріанти в assert_run
# ⚠️ Кількість інваріантів тут СВІДОМО не названа: попередня редакція казала «5»,
# коли їх стало шість, тобто шапка описувала власне тіло хибно. Лік — не оновити
# число (воно протухне на наступному доданому), а не мати його: перелік читається
# з `assert_run`, і він там пронумерований.
#
# ⛔ ПРЕДМЕТ — стабільність емісії протоколу, НЕ дохідність токена. Формулювання
# несуче, не стилістичне: [BIZ.22] вимагає прибрати investor-лексику й мову
# очікуваного доходу з продуктових артефактів (Howey fact-pattern). Модель відповідає
# на «чи впирається supply у стелю і коли», ніколи на «скільки заробить власник».
#
# ЧОМУ guard: канон 05_03 виводить MAX_SUPPLY з ланцюга «10k GP=1 SCC · 2k SCC=1 tCO₂
# ≈ 20M дерево-років (≈2M дерев × 10 р.)». Цей ланцюг живе ПРОЗОЮ в одному рядку і
# ніде не перерахований — тобто будь-яка зміна emission_threshold або MAX_SUPPLY
# лишає його правдоподібним і хибним. Інваріант 1 нижче ВІДТВОРЮЄ деривацію
# чисельно: модель мусить дати 10 років на канонічному вході, інакше розійшлись
# або константи, або сама деривація.
#
# Джерела (де живуть вхідні числа):
#   MAX_SUPPLY · конверсія GP→SCC · деривація 20M дерево-років — 05_03 (контракт-SSOT
#     contracts/SilkenCarbonCoin.sol: MAX_SUPPLY = constant, НЕ DAO-параметр)
#   emission_threshold · dynamic_tax_rate · slash_gamma · bounds — 05_06 §7
#     (⚠️ bounds валідує БЕКЕНД Governance::ParameterSyncWorker при читанні назад;
#      ProtocolParameters.setParameter не валідує значення взагалі — лише key != 0)
#   scc_per_tree_year — tools/firmware/scc_rate.rb (E.63, calibration-pending)
#   slash-формула damage^gamma × min(pf, pf_max) — 05_05 §3
#
# СТЕЛІ [E.67] — що модель НЕ стверджує:
#   • Ціни й попиту тут немає ЗА ПОБУДОВОЮ: канон їх не має (00_04 «не зафіксовано»,
#     00_01 «фіатні суми НЕ фіксуються»), тож будь-яка цінова крива була б нашою
#     вигадкою з виглядом специфікації. Модель міряє КІЛЬКІСТЬ, не вартість.
#   • scc_per_tree_year — calibration-pending [E.63]: realistic 7.92 ⊥ фізична стеля
#     326 ⊥ канон-арбітр 50. Розкид 40× у центральному вході; сценарії нижче беруть
#     усі три, і саме тому вихід подається діапазоном, а не числом.
#   • Крива флоту — НАШЕ припущення (канон моделі учасників не має): лінійний ramp
#     до trees за ramp_years, далі плато.
#   • Retirement supply НЕ зменшує (retire() — чужий ABI KlimaDAO після approve, не
#     _burn нашого контракту), тож у моделі його немає взагалі. Єдиний механізм
#     звільнення cap — slash.

PARAMS = {
  # ── горизонт і флот (НАШЕ припущення — канон моделі учасників не має) ────────
  trees: 2_000_000,       # канонічний pilot-флот деривації 05_03
  ramp_years: 0,          # 0 = флот одразу повний (форма канон-деривації)
  horizon_years: 100,     # стеля симуляції; horizon > цього = "не впирається"
  # ── емісія ──────────────────────────────────────────────────────────────────
  scc_per_tree_year: 50.0, # канон-арбітр 05_03; realistic 7.92, стеля 326 [E.63]
  max_supply: 1_000_000_000.0, # SilkenCarbonCoin.sol MAX_SUPPLY — constant
  # ── dynamic tax (05_03 · 05_06 §7) ──────────────────────────────────────────
  dynamic_tax_rate: 0.02,          # bounds 0 .. 0.10
  insurance_pool_threshold: 100_000.0, # SCC; податок ON поки treasury нижче
  # ── slashing (05_05 §3) ─────────────────────────────────────────────────────
  slash_gamma: 1.3,           # bounds 1.0 .. 3.0
  penalty_factor: 1.0,        # відвантажений стан: uplift інертний → рівно 1.0
  penalty_factor_max: 2.0,    # bounds 1.0 .. 5.0
  # 🔴 [E.67] Що DAO НАПИСАВ у контракт — на відміну від `slash_gamma`, який є
  # ЕФЕКТИВНИМ значенням після бекенд-перевірки. Розрив не гіпотетичний:
  # `ProtocolParameters.setParameter` не валідує значення ВЗАГАЛІ (лише `key != 0`),
  # тож голос за γ=3.5 лягає on-chain успішно, а `Governance::ParameterSyncWorker`
  # ВІДКИДАЄ позамежне при читанні назад і лишає попереднє. Стан «ланцюг каже одне,
  # протокол робить інше» стійкий — і саме він є економічним предметом, а не багом.
  # Дефолт = `slash_gamma` ⇒ розриву немає (відвантажений стан).
  slash_gamma_voted: 1.3,
  degradation_rate: 0.0,      # частка флоту/рік, що дає ПІДТВЕРДЖЕНИЙ Кат-A доказ
  damage_ratio_mean: 0.30,    # середня частка стресованих дерев у такій події
  # ── страхові виплати (00_04 §7 · INS.2) ─────────────────────────────────────
  payout_rate: 0.0,           # подій/рік на 1000 дерев (baseline: kill-switch off)
  payout_amount: 1_000.0,     # SCC на подію — СТАТИЧНА колонка поліса, не ∝ шкоді
  # ── симуляція ───────────────────────────────────────────────────────────────
  n_trials: 2_000,
  seed: 42
}.freeze

MONTHS = 12

# Флот на місяць m: лінійний ramp до PARAMS[:trees], далі плато.
def fleet_at(prm, month)
  ramp_months = prm[:ramp_years] * MONTHS
  return prm[:trees] if ramp_months <= 0 || month >= ramp_months

  prm[:trees] * (month + 1).to_f / ramp_months
end

# Один місячний крок. Повертає оновлений стан (supply/treasury у МОНЕТАХ SCC).
#
# ⚠️ Одиниця тут МОНЕТИ, і це не деталь: wallets.balance у проді — БАЛИ, а курс
# 10 000:1. Модель, що змішала б їх, помилилась би рівно в emission_threshold разів
# (той самий клас, що [ARCH.88]/[ARCH.95]). Тому emission_threshold у крок не
# входить взагалі — scc_per_tree_year уже виражений у монетах (scc_rate.rb робить
# конверсію GP→SCC на своєму боці).
def step(state, prm, rng, month)
  trees = fleet_at(prm, month)

  # 1. Емісія. Податок ТЕЖ мінтиться (окремим елементом батча на treasury),
  #    тож у supply йде повний gross — 05_03 §Dynamic Tax.
  gross = trees * prm[:scc_per_tree_year] / MONTHS
  taxing = state[:treasury] < prm[:insurance_pool_threshold]
  tax = taxing ? gross * prm[:dynamic_tax_rate] : 0.0
  state[:supply] += gross
  state[:treasury] += tax

  # 2. Slash — ЄДИНИЙ механізм, що зменшує on-chain totalSupply (_burn).
  #    Гейтований прямим доказом Кат-A [SLASH-1]; degradation_rate і є частотою
  #    ТАКИХ подій, а не частотою деградації взагалі.
  events = rng.rand < (prm[:degradation_rate] / MONTHS) ? 1 : 0
  if events.positive?
    damage = [ rng.rand * 2 * prm[:damage_ratio_mean], 1.0 ].min
    pf = [ prm[:penalty_factor], prm[:penalty_factor_max] ].min
    slash_ratio = [ (damage**prm[:slash_gamma]) * pf, 1.0 ].min
    burn = state[:supply] * slash_ratio * prm[:damage_ratio_mean]
    state[:supply] = [ state[:supply] - burn, 0.0 ].max
    state[:burned] += burn
  end

  # 3. Страхова виплата — Internal-mode МІНТИТЬ новий SCC (інфляція, пул не
  #    дебетується). Розмір статичний: all-or-nothing, не ∝ шкоді.
  expected = trees / 1_000.0 * prm[:payout_rate] / MONTHS
  if expected.positive? && rng.rand < expected
    state[:supply] += prm[:payout_amount]
    state[:minted_insurance] += prm[:payout_amount]
  end

  state
end

# Одна траєкторія. Повертає місяць пробиття cap або nil (не впирається).
def run_trial(prm, rng)
  state = { supply: 0.0, treasury: 0.0, burned: 0.0, minted_insurance: 0.0 }
  months = prm[:horizon_years] * MONTHS
  months.to_i.times do |m|
    step(state, prm, rng, m)
    return { month: m + 1, state: state } if state[:supply] >= prm[:max_supply]
  end
  { month: nil, state: state }
end

def run(prm)
  rng = Random.new(prm[:seed].to_i)
  trials = Array.new(prm[:n_trials].to_i) { run_trial(prm, rng) }
  breached = trials.filter_map { |t| t[:month] }.sort
  {
    n: trials.size,
    breached_n: breached.size,
    breach_share: breached.size.to_f / trials.size,
    years_p50: breached.empty? ? nil : breached[breached.size / 2] / 12.0,
    years_min: breached.empty? ? nil : breached.first / 12.0,
    final_supply: trials.sum { |t| t[:state][:supply] } / trials.size,
    burned: trials.sum { |t| t[:state][:burned] } / trials.size,
    insurance: trials.sum { |t| t[:state][:minted_insurance] } / trials.size,
    treasury: trials.sum { |t| t[:state][:treasury] } / trials.size
  }
end

def scenario(prm, over)
  run(prm.merge(over))
end

# [E.67] Governance-розрив: скільки коштує те, що ланцюг прийняв значення, яке
# бекенд відкинув. Обидва прогони беруть ОДИН seed, тож послідовність подій
# тотожна й різниця чисто параметрична, не стохастична.
#
# 🔴 Напрямок ВИМІРЯНО, а не виведено — і перша спроба записати його «з голови»
# була ХИБНОЮ, гейт її й зловив. Крива `damage^γ` при `damage < 1` УБУВАЄ по γ:
# `0.3^1.3 = 0.215`, `0.3^3.5 = 0.0044`. Тобто ВИЩА γ ПОМʼЯКШУЄ вирок, а не
# жорсткішає — інтуїція «більший показник = суворіше» тут просто хибна.
#
# Звідси форма розриву: бекенд ВІДКИДАЄ позамежне (лишає попереднє), а не КЛАМПИТЬ
# до межі, тож ефективним лишається СТАРЕ значення в обох випадках. Знак шкоди
# задає те, ЧЕРЕЗ ЯКУ межу перелетів голос:
#   γ > 3.0 (голос ПОМʼЯКШИТИ, відкинутий) → палимо БІЛЬШЕ, ніж ухвалено;
#   γ < 1.0 (голос ПОСИЛИТИ, відкинутий)   → палимо МЕНШЕ, ніж ухвалено.
# Спільне й головне: governance вважає, що зрушив важіль, а не зрушило НІЩО.
def governance_divergence(prm, over)
  effective = scenario(prm, over)
  intended  = scenario(prm, over.merge(slash_gamma: prm.merge(over)[:slash_gamma_voted]))
  { effective: effective, intended: intended,
    burn_gap: intended[:burned] - effective[:burned] }
end

def fmt_years(value)
  value.nil? ? "не впирається" : format("%.1f р.", value)
end

def report(prm)
  puts "SUPPLY-стрес [E.67] — MAX_SUPPLY=#{(prm[:max_supply] / 1e9).round(2)}B SCC · " \
       "флот=#{prm[:trees]} · #{prm[:n_trials]} траєкторій (seed=#{prm[:seed]})"
  puts

  rows = [
    [ "канон-арбітр (50 SCC/дерево/рік)", { scc_per_tree_year: 50.0 } ],
    [ "realistic Δt=1.77h (7.92)",        { scc_per_tree_year: 7.92 } ],
    [ "фізична стеля Δt=600s (326)",      { scc_per_tree_year: 326.0 } ],
    [ "realistic + активований slash",    { scc_per_tree_year: 7.92, degradation_rate: 0.05 } ],
    [ "realistic + страхові виплати",     { scc_per_tree_year: 7.92, payout_rate: 0.5 } ]
  ]

  printf("%-34s %14s %8s %12s %12s\n", "сценарій", "cap за", "частка", "спалено", "страх.емісія")
  rows.each do |name, over|
    r = scenario(prm, over)
    printf("%-34s %14s %7.0f%% %12s %12s\n",
           name, fmt_years(r[:years_p50]), r[:breach_share] * 100,
           r[:burned].positive? ? "#{(r[:burned] / 1e6).round(1)}M" : "—",
           r[:insurance].positive? ? "#{(r[:insurance] / 1e6).round(1)}M" : "—")
  end

  puts
  base = scenario(prm, { scc_per_tree_year: 7.92 })
  puts "Treasury (dynamic tax) на кінець realistic-прогону: " \
       "#{(base[:treasury] / 1e3).round(1)}k SCC — поріг вимкнення " \
       "#{(prm[:insurance_pool_threshold] / 1e3).round(0)}k"
  puts "⚠️ Retirement supply НЕ зменшує (чужий ABI, не _burn) — у моделі його немає."
  puts "⚠️ Baseline burn = 0 за конструкцією: A-сет порожній, uplift інертний [SLASH-1]."

  puts
  puts "Governance-розрив [E.67] — ланцюг прийняв, `ParameterSyncWorker` відкинув " \
       "(ефективна γ лишається #{prm[:slash_gamma]}):"
  base_over = { scc_per_tree_year: 7.92, degradation_rate: 0.05 }
  [ [ 3.5, "вище межі 3.0 — голос ПОМʼЯКШИТИ" ],
    [ 0.5, "нижче межі 1.0 — голос ПОСИЛИТИ"  ] ].each do |voted, label|
    d = governance_divergence(prm, base_over.merge(slash_gamma_voted: voted))
    puts "  γ=#{voted} (#{label}): ефективно #{(d[:effective][:burned] / 1e6).round(2)}M ⊥ " \
         "за ухваленим #{(d[:intended][:burned] / 1e6).round(2)}M SCC → палимо " \
         "#{d[:burn_gap].negative? ? 'БІЛЬШЕ' : 'МЕНШЕ'} за ухвалене на " \
         "#{(d[:burn_gap].abs / 1e6).round(2)}M"
  end
  puts "  ⚠️ Знак задає межа, через яку перелетів голос; спільне — що governance " \
       "вважає важіль зрушеним, а не зрушило НІЩО."
end

def assert_run(prm)
  errors = []

  # 1. КАНОН-АРБІТР: 05_03 виводить MAX_SUPPLY як ≈2M дерев × 10 років × 50
  #    SCC/дерево/рік. Модель мусить відтворити саме 10 років — інакше розійшлись
  #    константи або сама деривація.
  # ⚠️ horizon_years ПРИБИТО явно, не успадковується: інакше легітимний override
  # (`horizon_years=5` для звіту) робить канонічні 10 р. недосяжними, і гейт
  # червоніє на КОРЕКТНОМУ коді — а найдешевша реакція на такий гейт послабити його.
  arb = scenario(prm, { trees: 2_000_000, scc_per_tree_year: 50.0, degradation_rate: 0.0,
                        payout_rate: 0.0, ramp_years: 0, horizon_years: 30 })
  if arb[:years_p50].nil? || !(9.5..10.5).cover?(arb[:years_p50])
    errors << "канон-арбітр 05_03 (2M дерев × 50 SCC/рік) дав #{fmt_years(arb[:years_p50])}, " \
              "очікується ≈10 р. — MAX_SUPPLY↔деривація розійшлись"
  end

  # 2. МОНОТОННІСТЬ: без slash і виплат supply не може спадати, тож cap пробивається
  #    у 100% траєкторій (детерміновано, стохастики немає взагалі).
  errors << "burn=0 дав #{arb[:breached_n]}/#{arb[:n]} пробиттів — supply не монотонний" \
    unless arb[:breached_n] == arb[:n]

  # 3. BASELINE BURN = 0: відвантажений стан не палить нічого (A-сет порожній).
  #    Ловить помилку, де модель почала б палити повз positive-A гейт.
  #    ⚖️ РАТИФІКОВАНО 2026-08-30 (E.67, делеговано) як ACCEPTANCE-поріг:
  #    «burn без positive-A неможливий» — червоне тут означає «протокол зламано»,
  #    не «модель розійшлась». Безпековий род, чисел економіки не називає.
  base = scenario(prm, { scc_per_tree_year: 7.92, degradation_rate: 0.0 })
  errors << "baseline спалив #{base[:burned].round(2)} SCC при degradation_rate=0" \
    unless base[:burned].zero?

  # 4. ОДИНИЦЯ: supply у МОНЕТАХ. Якби модель десь застосувала курс 10 000:1
  #    (бали замість монет), річна емісія розійшлась би на 4 порядки.
  #    ⚖️ РАТИФІКОВАНО 2026-08-30 (E.67, делеговано) як ACCEPTANCE-поріг:
  #    «supply деномінований у МОНЕТАХ» — клас одиниці, що вже двічі коштував
  #    грошей на живому шляху (ARCH.95; скіл web3-pipeline #20).
  one_year = scenario(prm, { trees: 1_000, scc_per_tree_year: 10.0, horizon_years: 1,
                             degradation_rate: 0.0, payout_rate: 0.0 })
  expected = 10_000.0
  unless (one_year[:final_supply] - expected).abs < expected * 0.02
    errors << "одиниця supply зламана: 1000 дерев × 10 SCC/рік дало " \
              "#{one_year[:final_supply].round} замість ≈#{expected.round} (бали⊥монети?)"
  end

  # 5. TAX-ГІСТЕРЕЗИС: податок мусить ВИМКНУТИСЬ, щойно treasury дійде порога —
  #    це негативний зворотний зв'язок, а не постійний збір.
  taxed = scenario(prm, { scc_per_tree_year: 7.92, horizon_years: 5 })
  ceiling = prm[:insurance_pool_threshold] * 1.5
  errors << "treasury=#{taxed[:treasury].round} перевищив #{ceiling.round} — " \
            "гістерезис податку не спрацював" if taxed[:treasury] > ceiling

  # 6. GOVERNANCE-РОЗРИВ [E.67]: on-chain безмежний ⊥ off-chain обмежений. Голос за
  #    γ поза бекенд-межею лягає в контракт успішно (`setParameter` не валідує
  #    значення взагалі), а `ParameterSyncWorker` відкидає його на читанні назад —
  #    тож ефективним лишається СТАРЕ значення. Інваріант пінить і ІСНУВАННЯ розриву,
  #    і те, що його ЗНАК визначає перелетіла межа — обидві половини несучі:
  #    ⚖️ РАТИФІКОВАНО 2026-08-30 (E.67, делеговано) як ACCEPTANCE-поріг:
  #    «голос поза бекенд-межею не сміє тихо набути чинності» — розрив мусить
  #    лишатись ВИДИМИМ (модель бачить клас) і НЕДІЄВИМ (бекенд відкидає).
  #    без першої модель не бачить класу взагалі, без другої вона пропустила б
  #    «спрощення» опуклої кривої, що перевернуло б економіку вироку мовчки.
  #    ⚠️ Знак виведено ВИМІРОМ: `damage^γ` при damage<1 УБУВАЄ по γ, тож вища γ
  #    ПОМʼЯКШУЄ. Перша редакція цього інваріанта стверджувала протилежне — і саме
  #    він її й зловив, що й є найкращим сортом доказу живості гейта.
  softer = governance_divergence(prm, { scc_per_tree_year: 7.92, degradation_rate: 0.05,
                                        slash_gamma_voted: 3.5 })
  harder = governance_divergence(prm, { scc_per_tree_year: 7.92, degradation_rate: 0.05,
                                        slash_gamma_voted: 0.5 })
  if softer[:burn_gap].zero? || harder[:burn_gap].zero?
    errors << "governance-розрив не виражається (γ=3.5 → #{softer[:burn_gap].round(2)}, " \
              "γ=0.5 → #{harder[:burn_gap].round(2)}) — модель не бачить стану " \
              "«ланцюг прийняв, бекенд відкинув»"
  elsif !(softer[:burn_gap].negative? && harder[:burn_gap].positive?)
    errors << "знак governance-розриву перевернувся: відкинутий голос ПОМʼЯКШИТИ (γ=3.5) " \
              "мусить лишати спалення БІЛЬШИМ за ухвалене, а ПОСИЛИТИ (γ=0.5) — меншим; " \
              "дістали #{softer[:burn_gap].round(2)} / #{harder[:burn_gap].round(2)} — " \
              "опукла крива 05_05 §3 зламана"
  end

  if errors.empty?
    puts "✅ supply_stress: канон-арбітр=#{fmt_years(arb[:years_p50])} · " \
         "realistic=#{fmt_years(scenario(prm, { scc_per_tree_year: 7.92 })[:years_p50])} · " \
         "baseline burn=0 · одиниця=монети (magnitude calibration-pending, E.63)"
    exit 0
  end
  warn "❌ supply_stress FAIL:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
end

# 🔴 [E.67] Ключі, чий CLI-override НІЧОГО НЕ РОБИТЬ — і мовчати про це не можна,
# бо шапка вище обіцяє «override будь-якого PARAMS-ключа». Виміряно вичерпно
# 2026-08-30 (кожен із 17 ключів прогнано з абсурдним значенням проти базового
# виводу): інертні рівно ДВА, і це не збіг — обидва називають ту саму вісь, задля
# показу якої модель і існує, тож КОЖЕН її споживач задає їх ЯВНО:
#   · scc_per_tree_year — матриця сценаріїв бере всі три канонічні магнітуди
#     (7.92 ⊥ 50 ⊥ 326) поіменно; глобальний override схлопнув би саме те
#     порівняння, заради якого вихід подається діапазоном, а не числом;
#   · slash_gamma_voted — governance-зонд свідомо ганяє ОБИДВА боки межі
#     (пом'якшити ⊥ посилити), бо інваріант 6 пінить і існування розриву, і знак.
# ⛔ Тому лік — не «зробити їх живими» (це зламало б обидва вимірювачі), а гучна
# межа: мовчазний no-op тут гірший за відмову, бо повний правдоподібний звіт
# відповідає на питання, якого читач НЕ ставив. Клас — оголошення без механізму
# (сиблінг інертних kwargs у SEC.17): знак того, що поверхня рекламує важіль,
# якого за нею немає.
MATRIX_OWNED = {
  scc_per_tree_year: "вісь матриці сценаріїв (7.92 ⊥ 50 ⊥ 326) — правити самі сценарії",
  slash_gamma_voted: "вісь governance-зонда (обидва боки межі) — правити сам зонд"
}.freeze

params = PARAMS.dup
assert_mode = ARGV.delete("--assert")
ARGV.each do |arg|
  key, val = arg.split("=", 2)
  key = key.to_sym
  abort("невідомий параметр: #{key} (є: #{PARAMS.keys.join(', ')})") unless PARAMS.key?(key)
  if MATRIX_OWNED.key?(key)
    abort("❌ #{key}= НЕ впливає ні на що: #{MATRIX_OWNED[key]}. " \
          "Кожен сценарій задає цей ключ явно, тож override мовчки дав би той самий звіт " \
          "про ІНШЕ питання. Дефолт (#{PARAMS[key]}) лишається лише як fallback. [E.67]")
  end
  params[key] = val.include?(".") ? Float(val) : Integer(val)
end
params.freeze

assert_mode ? assert_run(params) : report(params)
