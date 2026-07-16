#!/usr/bin/env ruby
# frozen_string_literal: true

# [DOC-T.35 + DOC-T.36 + DOC-T.37] On-demand «Стан-лід» audit — ADVISORY, НЕ CI-gate.
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
#    FP-класи, вбиті у скрипт historical sweep'ом (DOC-T.37, 2026-07-12):
#      • negation-exempt розширено: «зрізано/прибрано/вилучено/неіснуючий/
#        retired/не читають…» — drift-fix мусить назвати хибний токен;
#      • «memory-дім X» — токен = слаг пам'яті Claude, живе поза docs/;
#      • токен на «_» (суфікс-скорочення `_CHATID` / toolchain `__stack_chk_guard`);
#      • ALL_CAPS-стем (ENV / регістр кремнію / C-константа) — spec-at-source:
#        перевіряється кодом/deploy-конфігом, не каноном. Свідома стеля
#        (рев'ю DOC-T.37): ALL_CAPS не перевіряється навіть на wrong-дім;
#        Lorenz-родину тримає 03_04-inline-реф-дисципліна Стан-рядків
#        (E.63/E.64 вже так) + HARD lorenz_formula_drift (value-restatement);
#      • file-токен (розширення + файл реально існує в репо) — клейм
#        «файл X» перевіряється існуванням, не згадкою в домі (чек на СИРОМУ
#        токені — стем-стрип відкушує цифрові префікси `05_parity_dump.py`);
#      • object-chain цитата (≥3 сегментів або виклик з дужками:
#        `tx.wallet.broadcast_update`) — діагностична цитата коду; але
#        2-сегментний `table.column`-клейм ПЕРЕВІРЯЄТЬСЯ (повний стем або
#        правий сегмент у домі — клас chain_hash-дрейфу, рев'ю DOC-T.37);
#      • діалект-нормалізація пошуку: case-insensitive + underscore↔hyphen↔
#        space (канон пише `allow-iap-ssh`/«growth_points clamp drift») +
#        CamelCase case-sensitive (`coap_smoke`→`CoapSmoke`; substring-склейку
#        delete("_") знято — префікс-колізія hardwarekeys⊂HardwareKeyService);
#      • `Class#method`: якщо КЛАС названий у домі (case-sensitive \b-слово —
#        прозове «wallet» ≠ клас `Wallet`) — метод = деталь, OK. Свідома
#        стеля: конкретний метод при цемент-розборі перевіряй очима;
#      • `00_06` = universal-дім (guard-table §3 + home-registry §2 легітимно
#        реєструють будь-який символ);
#      • статуси ⚪/⚫/🌿/🔗 → поза основним рахунком (дім у мета-рядку =
#        ПРИЗНАЧЕННЯ майбутньої роботи, не клейм на наявний зміст; lifecycle:
#        айтем стає 🟢/🟡 — клейм активується сам). ⚠️ НЕ глушаться: друкуються
#        ПОВНИМИ хітами окремою секцією (§00-рев'ю 07-16 — раніше був ID×count,
#        і око не бачило ТОКЕН). Причина: vilize-Стани несуть факти-про-код
#        («X захардкоджено», «Y у коді не існує»), а для них вісь «канон НІДЕ
#        не називає» = перевірка ІСНУВАННЯ, від lifecycle незалежна; глушився
#        і цей клас теж. Читай у muted-секції саме «канон НІДЕ не називає»;
#        «wrong-дім?» там — очікуваний FP.
#
#    Відомі стелі (задокументовані, не баги — advisory читається очима):
#      • NEGATION-вікно двобічне (±90): «squash'нуто X в Y» гасить і Y
#        (результат, не жертву) — при розборі перевіряй напрямок дієслова;
#      • Class#-правило зараховує метод за наявністю КЛАСУ в домі.
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
#      [A] ID-число (FW.2, PATH 2, §4) — виключено механічно
#          (+ DOC-T.37: «PATH 2»/«Фаза 3» перед лічильним словом).
#
# Pure Ruby (no Rails); реюзить Tracker::Dashboard-константи парсингу.

require_relative "../lib/tracker/dashboard"

REPO_ROOT = File.expand_path("..", __dir__)

md = File.read(Tracker::Dashboard::DEFAULT_PATH)
docs_dir = Tracker::Dashboard::DOCS_DIR

doc_texts = Dir.glob(File.join(docs_dir, "*.md")).each_with_object({}) do |f, h|
  id = File.basename(f, ".md")[0, 5]
  h[id] = File.read(f) if id =~ /\A\d\d_\d\d\z/
end
doc_texts_lc = doc_texts.transform_values(&:downcase)

# --- зібрати айтеми: ID → {stan:, docs:, status:} (registry-скоуп як parse) ---
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
    items[current] = { stan: nil, docs: [], status: nil }
    next
  end
  next unless current

  if line.match?(/\*\*P[0-3]\*\*/)
    items[current][:docs] |= line.scan(/\b(\d\d_\d\d)\b/).flatten
    items[current][:status] ||= line[/[🟢🟡🔴⚪⚫🌿🔗]/]
  end
  next unless line.start_with?("- **Стан:**") && items[current][:stan].nil?

  items[current][:stan] = line
  items[current][:docs] |= line.scan(/\b(\d\d_\d\d)\b/).flatten
end

# --- вісь 1: canon-claim ---
NEGATION = /вичищ|видален|не існу|неіснуюч|ніколи не існу|фантом|мертв|знят|зрізан|прибран|вилучен|скасован|retired|спростован|squash|0 hits|= 0\b|нема|відхилен|не чита/i
MEMORY_CTX = /memory[-\s]?дім|пам['ʼ]ят/i
FILE_EXT = /\.(?:md|rb|yml|yaml|rake|c|h|sol|json|toml|tf|tpl|js|css|erb|sql|py|sh|tflite)\z/
INACTIVE_STATUS = %w[⚪ ⚫ 🌿 🔗].freeze

# Діалект-нормалізація: канон пише kebab/space — код snake_case; CamelCase
# окремою case-sensitive гілкою (substring-склейка delete("_") давала
# префікс-колізії: hardwarekeys ⊂ hardwarekeyservice).
def stem_variants(stem)
  lc = stem.downcase
  [ lc, lc.tr("_", "-"), lc.tr("_", " ") ].uniq
end

def camel(stem)
  stem.split(/[_.]/).map(&:capitalize).join
end

def found_in?(text_lc, text_raw, stem)
  stem_variants(stem).any? { |v| text_lc.include?(v) } || text_raw.include?(camel(stem))
end

def repo_file_exists?(basename)
  @repo_files ||= {}
  @repo_files.fetch(basename) do
    hits = Dir.glob(File.join(REPO_ROOT, "**", basename)) +
           Dir.glob(File.join(REPO_ROOT, "{.github,.claude}", "**", basename))
    @repo_files[basename] = hits.reject { |p| p.include?("node_modules") }.any?
  end
end

puts "── Вісь 1 · canon-claim: код-символ зі Стану відсутній у заявлених домах ──"
claim_hits = 0
muted = []
items.each do |id, it|
  next unless it[:stan] && it[:docs].any?

  tokens = it[:stan].scan(/`([^`\s]+)`/).flatten.select do |t|
    t.match?(/\A[\w:#.!?()\[\]]+\z/) && (t.include?("_") || t.include?("#") || t.end_with?("()"))
  end
  homes = it[:docs] | [ "00_06" ]
  tokens.uniq.each do |tok|
    next if tok.start_with?("_") # суфікс-скорочення / toolchain-символ
    next if tok.match?(FILE_EXT) && repo_file_exists?(File.basename(tok)) # сирий tok: 05_parity_dump.py

    stem = tok.sub(/\A[A-Z]\w*(?:::\w+)*#/, "").sub(/\A[^A-Za-z]+/, "")[/\A[\w:.]+/].to_s
    next if stem.length < 4
    next if stem.match?(/\A[A-Z][A-Z0-9_.]*\z/) # ALL_CAPS: ENV/регістр/константа = spec-at-source
    next if stem.match?(FILE_EXT) && repo_file_exists?(File.basename(stem))

    segs = stem.split(".")
    is_chain = stem.include?(".") && !stem.match?(FILE_EXT) && stem[0].match?(/[a-z]/)
    next if is_chain && (segs.length > 2 || tok.include?("(")) # вираз-цитата (a.b.c / виклик)

    # 2-сегментний table.column-клейм: повний стем АБО правий сегмент у домі
    probes = is_chain ? [ stem, segs.last ] : [ stem ]
    next if probes.any? { |p| homes.any? { |d| doc_texts_lc[d] && found_in?(doc_texts_lc[d], doc_texts[d], p) } }

    # Class#method: клас канонізований у домі (case-sensitive слово) → метод = деталь
    cls = tok[/\A[A-Z]\w*(?:::\w+)*(?=#)/]
    next if cls && homes.any? { |d| doc_texts[d]&.match?(/\b#{Regexp.escape(cls)}\b/) }

    # negation / memory-дім у ±90 символах довкола токена → не клейм, skip
    ctx = it[:stan][/.{0,90}#{Regexp.escape(tok)}.{0,90}/m].to_s
    next if ctx.match?(NEGATION) || ctx.match?(MEMORY_CTX)

    # 00_07 не рахується «знайдено» — Стан-рядок сам там живе
    elsewhere = doc_texts_lc.select { |d, txt| d != "00_07" && found_in?(txt, doc_texts[d], stem) }.keys
    hint = elsewhere.any? ? "∈ #{elsewhere.join(', ')} — wrong-дім?" : "канон НІДЕ не називає (діра або код-only згадка)"
    line = "  #{id}: `#{tok}` ∉ {#{it[:docs].join(', ')}} · #{hint}"

    # ⚪/⚫/🌿/🔗: дім = призначення роботи, не клейм на наявний зміст → не в основний
    # рахунок. Але й НЕ глушити мовчки: vilize-Стани несуть факти-про-код («X
    # захардкоджено», «Y у коді не існує»), а для них вісь «канон НІДЕ не називає» =
    # перевірка ІСНУВАННЯ, від lifecycle незалежна. Тому — повні хіти окремою секцією.
    if INACTIVE_STATUS.include?(it[:status])
      muted << line
      next
    end

    claim_hits += 1
    puts line
  end
end
puts "  (чисто ✓)" if claim_hits.zero?
if muted.any?
  puts ""
  puts "  ── статус-muted (⚪/⚫/🌿/🔗) — поза основним рахунком, розібрати очима на vilize ──"
  puts "  (дім у меті = призначення роботи, тож «wrong-дім?» тут очікуваний FP; але"
  puts "   «канон НІДЕ не називає» = перевірка існування — читай саме її)"
  muted.each { |line| puts line }
end

# --- вісь 2: volatile-numbers ---
COUNT_WORDS = /(?:host-)?тест\p{L}*|spec\p{L}*(?:-кейс\p{L}*)?|спек\p{L}*|examples?|KAT\b|golden\p{L}*|кейс\p{L}*|файл\p{L}*|сервіс\p{L}*|воркер\p{L}*|guard\p{L}*|гейт\p{L}*|модел\p{L}*/u
puts "\n── Вісь 2 · volatile-numbers: число+лічильне слово (розібрати клас A/B/C/D очима) ──"
num_hits = 0
items.each do |id, it|
  next unless it[:stan]

  it[:stan].scan(%r{(.{0,28})(?<![A-Za-z.§v])\b(\d+(?:/\d+)?)\s*(#{COUNT_WORDS})(.{0,22})}u) do |pre, num, word, post|
    next if pre.match?(/(?:PATH|Phase|Фаза|Gen)\s*\z/i) # [A] ID-число перед лічильним словом

    num_hits += 1
    puts "  #{id}: …#{pre}[#{num} #{word}]#{post}…"
  end
end
puts "  (чисто ✓)" if num_hits.zero?

puts "\nadvisory: хіти розібрати очима — [C]-клас лікується прибиранням числа + рефом джерела."
