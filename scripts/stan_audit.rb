#!/usr/bin/env ruby
# frozen_string_literal: true

# [DOC-T.35 + DOC-T.36] On-demand «Стан-лід» audit — ADVISORY, НЕ CI-gate.
# Запускати на цемент/vilize-сесії: ruby scripts/stan_audit.rb
#
# Дві осі по `- **Стан:**`-рядках registry-айтемів 00_07:
#
# 1. CANON-CLAIM (DOC-T.36): код-символ зі Стану (snake_case / Class#method /
#    fn() у code-span) має зустрічатись хоч в ОДНОМУ заявленому канон-домі
#    айтема (`NN_NN`-рефи зі Стан-рядка + meta canon-ref) — ловить клейм
#    «Механіка — 03_02 §4», де механіки нема (§-ref резолвиться, зміст
#    відсутній → жоден HARD-гейт не бачить; клас FW.58/MRV.1/CoapGate,
#    цемент 07-12). Semantic → FP можливі (символ живе лише в коді, канон
#    описує прозою) — тому advisory: кожен хіт розібрати очима.
#
# 2. VOLATILE-NUMBERS (DOC-T.35): число біля лічильного слова — розібрати
#    КЛАС очима (нора 07-12 довела: класи лексично нерозрізнимі → HARD-lint
#    = FP-шторм, відхилено):
#      [C] поточний-код лічильник («13 host-тестів») → прибрати число,
#          рефнути джерело (suite/grep) — ЄДИНИЙ клас-порушник;
#      [B] event-history («176 спек тихо жили…») — число вморожене в
#          закриту подію, не дрейфує → ок;
#      [D] скоуп-оцінка/вимога відкритої роботи («~31 приклад», «усі 12
#          call-sites у 7 сервісах») — специфікація задачі → ок;
#      [A] ID-число (FW.2, PATH 2, §4) — виключено механічно.
#
# Pure Ruby (no Rails); реюзить Tracker::Dashboard-константи парсингу.

require_relative "../lib/tracker/dashboard"

md = File.read(Tracker::Dashboard::DEFAULT_PATH)
docs_dir = Tracker::Dashboard::DOCS_DIR

doc_texts = Dir.glob(File.join(docs_dir, "*.md")).each_with_object({}) do |f, h|
  id = File.basename(f, ".md")[0, 5]
  h[id] = File.read(f) if id =~ /\A\d\d_\d\d\z/
end

# --- зібрати айтеми: ID → {stan:, docs: [NN_NN…]} (registry-скоуп як parse) ---
items = {}
current = nil
in_registry = false
md.each_line do |line|
  if line.start_with?("## ")
    in_registry = line.match?(Tracker::Dashboard::REGISTRY_SECTION) &&
                  !line.match?(Tracker::Dashboard::SKIP_SECTION)
    current = nil
    next
  end
  next unless in_registry

  if (m = line.match(Tracker::Dashboard::ITEM_HEAD))
    current = m[1]
    items[current] = { stan: nil, docs: [] }
    next
  end
  next unless current

  items[current][:docs] |= line.scan(/\b(\d\d_\d\d)\b/).flatten if line.match?(/\*\*P[0-3]\*\*/)
  next unless line.start_with?("- **Стан:**") && items[current][:stan].nil?

  items[current][:stan] = line
  items[current][:docs] |= line.scan(/\b(\d\d_\d\d)\b/).flatten
end

# --- вісь 1: canon-claim ---
# код-токен = code-span, що виглядає символом: snake_case (≥1 «_»), Class#method,
# або fn(); пошук у домі — по голому стему (Class#-префікс геть, тіло до першої
# дужки). Negation-exempt: токен, який Стан називає ВИДАЛЕНИМ/фантомним
# («вичищено X», «X = 0 hits»), — легітимна drift-fix згадка (клас
# chain_hash-guard'а), не клейм. Дві категорії хітів:
#   (а) ∉ заявлені доми, АЛЕ ∈ інший канон-док → підозра wrong-дім клейму;
#   (б) ∉ жоден док → або код-only контекст-згадка (FP), або фантом.
NEGATION = /вичищ|видален|не існу|ніколи не існу|фантом|мертв|знят|спростован|0 hits|= 0\b|нема|відхилен/i
puts "── Вісь 1 · canon-claim: код-символ зі Стану відсутній у заявлених домах ──"
claim_hits = 0
items.each do |id, it|
  next unless it[:stan] && it[:docs].any?

  tokens = it[:stan].scan(/`([^`\s]+)`/).flatten.select do |t|
    t.match?(/\A[\w:#.!?()\[\]]+\z/) && (t.include?("_") || t.include?("#") || t.end_with?("()"))
  end
  tokens.uniq.each do |tok|
    stem = tok.sub(/\A[A-Z]\w*(?:::\w+)*#/, "")[/\A[\w:.]+/].to_s
    next if stem.length < 4
    next if it[:docs].any? { |d| doc_texts[d]&.include?(stem) }
    # negation у ±60 символах довкола токена → drift-fix згадка, skip
    ctx = it[:stan][/.{0,60}#{Regexp.escape(tok)}.{0,60}/m].to_s
    next if ctx.match?(NEGATION)

    # 00_07 не рахується «знайдено» — Стан-рядок сам там живе
    elsewhere = doc_texts.select { |d, txt| d != "00_07" && txt.include?(stem) }.keys
    claim_hits += 1
    hint = elsewhere.any? ? "∈ #{elsewhere.join(', ')} — wrong-дім?" : "канон НІДЕ не називає (діра або код-only згадка)"
    puts "  #{id}: `#{tok}` ∉ {#{it[:docs].join(', ')}} · #{hint}"
  end
end
puts "  (чисто ✓)" if claim_hits.zero?

# --- вісь 2: volatile-numbers ---
COUNT_WORDS = /(?:host-)?тест\p{L}*|spec\p{L}*(?:-кейс\p{L}*)?|спек\p{L}*|examples?|KAT\b|golden\p{L}*|кейс\p{L}*|файл\p{L}*|сервіс\p{L}*|воркер\p{L}*|guard\p{L}*|гейт\p{L}*|модел\p{L}*/u
puts "\n── Вісь 2 · volatile-numbers: число+лічильне слово (розібрати клас A/B/C/D очима) ──"
num_hits = 0
items.each do |id, it|
  next unless it[:stan]

  it[:stan].scan(/(.{0,28})(?<![A-Za-z.§v])\b(\d[\d  ]*(?:\/\d+)?)\s*(#{COUNT_WORDS})(.{0,22})/u) do |pre, num, word, post|
    num_hits += 1
    puts "  #{id}: …#{pre}[#{num} #{word}]#{post}…"
  end
end
puts "  (чисто ✓)" if num_hits.zero?

puts "\nadvisory: хіти розібрати очима — [C]-клас лікується прибиранням числа + рефом джерела."
