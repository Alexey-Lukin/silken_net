#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SLASH-1] Чутливість ВИРОКУ до вибору ЗНАМЕННИКА — параметрична модель, single-source.
# Дзеркало supply_stress.rb (E.67) / scc_rate.rb (E.63) / uncertainty_budget.rb (STK.5):
# канон посилається сюди, magnitude живе тут.
#
# ⛔ ПРЕДМЕТ — розмір вироку за ОДНІЄЇ події масової вирубки. Модель НЕ вирішує, чи
# слешити (це positive-A gate, 05_05 §3.2) і не рахує грошей: вона рахує ЧАСТКУ.
#
# ЧОМУ ВОНА ІСНУЄ. `00_07` SLASH-1 несе відкритий ⚖️: «чи мовчання ≥ порога є підставою
# вважати дерево вибулим для РОЗМІРУ вироку». Присуд не заблокований нічим зовнішнім —
# він заблокований тим, що НІХТО НЕ ЗНАВ ЙОГО ЦІНИ: єдина модель слешингу в дереві
# (`supply_stress.rb`) бере `damage_ratio` екзогенним випадковим кидком, тобто ніколи не
# будує популяцію й на питання про знаменник відповісти не здатна ЗА ПОБУДОВОЮ.
#
# 🔴 НАПРУГА ДВОСТОРОННЯ, І ОБИДВА БОКИ ВЖЕ ЗАПИСАНІ В КОДІ — модель лише дає їм числа:
#   • не виключати тишу → суцільна вирубка приходить МОВЧАННЯМ, трупи лишаються
#     «вцілілими» й РОЗБАВЛЯЮТЬ вирок (`00_07` SLASH-1, відкритий ⚖️);
#   • виключати тишу → «кластер зі здорових, але мовчазних дерев дав би за одну смерть
#     1/1 = 100%» (`app/services/daily_health_router.rb`, коментар над `witnessing_trees`).
# Обидва боки — over/under-burn класу ARCH.46, лише з різних кінців.
#
# ЯКУ ГІЛКУ МОДЕЛЮЄМО. Гілку СМЕРТІ (`source_tree`), не статистичну. Статистична вже
# поїхала на свідків (`witnessing_trees`, ⚖️ 2026-08-26) і мовчазних не рахує з ОБОХ
# частин дробу; гілка смерті лишилась на `@cluster.trees.active.count` — свідомо, з
# названою підставою, і саме її ця модель зважує.
#
# ДЖЕРЕЛА ФОРМУЛИ (значення читай ТАМ, не звідси):
#   slash_ratio = clamp(damage_ratio**GAMMA * min(pf, PF_MAX), 0, 1.0)   — 05_05 §3
#   GAMMA 1.3 · PF_MAX 2.0 · PF 1.0                                      — BlockchainBurningService
#   гілка смерті: victims / (active + dead)                              — 05_05 §3, [SLASH-1]
#
# СТЕЛІ — що модель НЕ стверджує:
#   • Розподілу мовчання в полі в нас НЕМА (SILENCE-1: розкид `delta_t` ×35-190 не
#     зміряний), тож `silent_healthy` є ВХОДОМ СЦЕНАРІЮ, а не виміряною величиною.
#     Модель відповідає «якою буде помилка ПРИ такій частці», ніколи «яка вона є».
#   • Поріг виродження (`N < 1/slash_threshold` → freeze) стереже СТАТИСТИЧНУ гілку;
#     на гілці смерті його немає, і модель це відтворює, а не лагодить.
#   • Грошей тут немає: `net_minted_scc` кластера й підлога 1 SCC — інший ярус.
#
# Виклик:
#   ruby tools/tokenomics/verdict_sensitivity.rb                  # звіт по сценаріях
#   ruby tools/tokenomics/verdict_sensitivity.rb trees=500 cut=400
#   ruby tools/tokenomics/verdict_sensitivity.rb --assert          # гейт: інваріанти нижче

PARAMS = {
  trees: 101,           # дерев у кластері ДО події
  cut: 100,             # скільки насправді зрубано
  status_rate: 0.0,     # частка зрубаних, що дістала `removed`/`deceased` у добі source_tree
  silent_healthy: 0,    # ЗДОРОВІ дерева, що мовчать (енергетична тиша) — хибнопозитивна популяція
  gamma: 1.3,
  penalty_factor: 1.0,
  penalty_factor_max: 2.0
}.freeze

POLICIES = %i[current exclude_silent silent_as_victim].freeze

# ⚠️ Структура ВІРНА ДО КОДУ, а не спрощена: `source_tree.active?` тут несуча гілка, і
# перша чернетка цієї моделі її випустила — вирок за суцільну вирубку тишею вийшов 0.0%
# замість реальних 0.2%, тобто спрощення прибрало ЄДИНОГО зарахованого потерпілого.
# Оригінал (`BlockchainBurningService#source_tree_damage_ratio`):
#   dead    = [dead_tree_count, source_tree.active? ? 0 : 1].max
#   victims = source_tree.active? ? dead + 1 : dead
#   ratio   = min(victims / (active_count + dead), 1.0)
Population = Struct.new(:trees, :cut, :marked, :silent_healthy, keyword_init: true) do
  # Трігерне дерево оформлене статусом лише тоді, коли оформлення взагалі відбувалось.
  def source_active? = marked.zero?
  def dead = [ marked, source_active? ? 0 : 1 ].max
  def victims = source_active? ? dead + 1 : dead
  # Зрубане, але не оформлене, лишається `active` — саме тому воно й невидиме.
  def active_now = trees - dead
  # Усе, що впіймав би `Tree.silent`: невиданий труп + здорове мовчазне дерево.
  def silent = (cut - marked) + silent_healthy
  # Ґрунтова правда, з якою порівнюємо кожну політику.
  def true_damage = cut.to_f / trees
end

def build_population(prm)
  Population.new(
    trees: prm[:trees], cut: prm[:cut],
    marked: (prm[:cut] * prm[:status_rate]).floor,
    silent_healthy: prm[:silent_healthy]
  )
end

# 🔴 Три політики — це і є ⚖️ у трьох формах, а не три реалізації однієї.
#   current          — знаменник «ліс ДО події» (як сьогодні)
#   exclude_silent   — мовчазне дерево ВИБУВАЄ зі знаменника (перестає бути вцілілим)
#   silent_as_victim — мовчання САМЕ Є свідченням загибелі (їде в чисельник)
def damage_ratio(pop, policy)
  case policy
  when :current          then ratio(pop.victims, pop.active_now + pop.dead)
  when :exclude_silent   then ratio(pop.victims, (pop.active_now - pop.silent) + pop.dead)
  # ⚠️ Тут `victims` НЕ додається до `silent`: трігерне дерево, якщо воно не оформлене,
  # уже входить у `silent` — інакше вийшов би подвійний рахунок того самого стовбура.
  when :silent_as_victim then ratio([ pop.dead + pop.silent, pop.trees ].min, pop.active_now + pop.dead)
  else raise ArgumentError, "невідома політика: #{policy.inspect}"
  end
end

# ⚠️ Знаменник ≤ 0 не «нуль шкоди», а ВИРОДЖЕННЯ вибірки: усі свідки зникли. Повертаємо
# nil, щоб звіт назвав це станом, а не надрукував 0.0 як вимір.
def ratio(numerator, denominator)
  return nil if denominator <= 0

  [ numerator.to_f / denominator, 1.0 ].min
end

def slash_ratio(dr, prm)
  return nil if dr.nil?
  return 0.0 if dr <= 0.0

  ((dr**prm[:gamma]) * [ prm[:penalty_factor], prm[:penalty_factor_max] ].min).clamp(0.0, 1.0)
end

def verdict(prm, policy)
  pop = build_population(prm)
  dr = damage_ratio(pop, policy)
  { damage_ratio: dr, slash_ratio: slash_ratio(dr, prm), true_damage: pop.true_damage }
end

SCENARIOS = [
  { name: "суцільна вирубка, ОФОРМЛЕНА статусами",
    over: { trees: 101, cut: 100, status_rate: 1.0, silent_healthy: 0 } },
  { name: "суцільна вирубка, що прийшла ТИШЕЮ",
    over: { trees: 101, cut: 100, status_rate: 0.0, silent_healthy: 0 } },
  { name: "суцільна вирубка, оформлена НАПОЛОВИНУ",
    over: { trees: 101, cut: 100, status_rate: 0.5, silent_healthy: 0 } },
  { name: "ЗДОРОВИЙ кластер, одна смерть, більшість мовчить",
    over: { trees: 101, cut: 1, status_rate: 1.0, silent_healthy: 80 } },
  { name: "здоровий кластер, одна смерть, мовчання відсутнє",
    over: { trees: 101, cut: 1, status_rate: 1.0, silent_healthy: 0 } },
  { name: "ВИРОДЖЕНИЙ край: мовчать УСІ, крім трігерного",
    over: { trees: 101, cut: 1, status_rate: 1.0, silent_healthy: 100 } }
].freeze

def fmt(value) = value.nil? ? "  вирод." : format("%7.1f%%", value * 100)

def report(prm)
  puts "[SLASH-1] Чутливість вироку до знаменника — гілка СМЕРТІ (source_tree)"
  puts "γ=#{prm[:gamma]} · pf=#{prm[:penalty_factor]} (стеля #{prm[:penalty_factor_max]})"
  puts
  puts format("%-46s %8s %9s %9s %9s", "сценарій", "правда", "чинна", "виключ.", "як жертв")
  puts "-" * 86
  SCENARIOS.each do |scenario|
    prm_s = prm.merge(scenario[:over])
    row = POLICIES.map { |p| fmt(verdict(prm_s, p)[:slash_ratio]) }
    truth = fmt(build_population(prm_s).true_damage)
    puts format("%-46s %8s %9s %9s %9s", scenario[:name], truth, *row)
  end
  puts
  puts "«правда» — частка справді зрубаного; решта — slash_ratio за кожної політики."
  puts "⚠️ `silent_healthy` — ВХІД сценарію: розподілу мовчання в полі не зміряно (SILENCE-1)."
end

# ---------------------------------------------------------------------------
# --assert: інваріанти. Кожен відтворює твердження, яке ВЖЕ записане в коді або
# в трекері, — тобто модель має чим спростувати присуд, а не лише переказати його.
# ---------------------------------------------------------------------------
def assertions(prm)
  marked    = prm.merge(trees: 101, cut: 100, status_rate: 1.0, silent_healthy: 0)
  silenced  = prm.merge(trees: 101, cut: 100, status_rate: 0.0, silent_healthy: 0)
  healthy   = prm.merge(trees: 101, cut: 1,   status_rate: 1.0, silent_healthy: 80)
  degenerate = prm.merge(trees: 101, cut: 1,  status_rate: 1.0, silent_healthy: 100)

  [
    [ "оформлена суцільна вирубка дає ≈100% (обіцянка 05_05 §2 виконується)",
      -> { verdict(marked, :current)[:slash_ratio] >= 0.95 } ],

    [ "та сама вирубка ТИШЕЮ недокарює більш ніж на 90 п.п. — дефект, який називає ⚖️, реальний",
      -> { (verdict(silenced, :current)[:true_damage] - verdict(silenced, :current)[:slash_ratio]) > 0.90 } ],

    [ "виключення тиші зі знаменника ЛІКУЄ цей випадок (≈100%)",
      -> { verdict(silenced, :exclude_silent)[:slash_ratio] >= 0.95 } ],

    [ "…і при ЧАСТКОВОМУ мовчанні здоровий кластер НЕ карається (<5%) — застереження роутера тут не спрацьовує",
      -> { verdict(healthy, :exclude_silent)[:slash_ratio] < 0.05 } ],

    [ "…але на ВИРОДЖЕНОМУ краї (мовчать усі) воно спрацьовує рівно як записано: 1/1 = 100%",
      -> { verdict(degenerate, :exclude_silent)[:slash_ratio] >= 0.99 } ],

    [ "«мовчання = жертва» карає здоровий кластер уже при частковому мовчанні (>50%)",
      -> { verdict(healthy, :silent_as_victim)[:slash_ratio] > 0.50 } ]
  ]
end

def run_assertions(prm)
  checks = assertions(prm)
  failures = checks.reject do |(_label, check)|
    ok = check.call
    puts "#{ok ? '✅' : '❌'} #{_label}"
    ok
  end
  if failures.empty?
    # ⚠️ Лічильник ВИВОДИТЬСЯ з масиву: перша чернетка друкувала «5/5» при шести
    # інваріантах — той самий клас волатильного числа, який ця смуга й ловить.
    puts "\n✅ #{checks.size}/#{checks.size} інваріантів тримаються"
    0
  else
    puts "\n❌ #{failures.size} інваріант(и) впали — модель розійшлася з кодом або каноном"
    1
  end
end

if $PROGRAM_NAME == __FILE__
  overrides = ARGV.reject { |a| a.start_with?("--") }.to_h { |a| a.split("=", 2) }
  prm = PARAMS.merge(
    overrides.to_h { |k, v| [ k.to_sym, v.include?(".") ? v.to_f : v.to_i ] }
  )
  exit(ARGV.include?("--assert") ? run_assertions(prm) : (report(prm) || 0))
end
