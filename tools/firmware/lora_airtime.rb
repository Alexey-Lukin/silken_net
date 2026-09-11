# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.61] LoRa time-on-air — модель, а не переписані числа.
#
# Канон 03_05 §2.1 ПОСИЛАЄТЬСЯ сюди; wire-budget ledger там само читає
# символьні блоки з цієї ж таблиці, а не тримає власні межі.
#
# Pure Ruby (no Rails). Виклик:
#   ruby tools/firmware/lora_airtime.rb               # звіт (профіль + блоки + ключові кадри)
#   ruby tools/firmware/lora_airtime.rb --assert      # фізика + парність моделі з 02_03 §9.6
#   ruby tools/firmware/lora_airtime.rb --check-canon # таблиця 03_05 §2.1 проти моделі
#   ruby tools/firmware/lora_airtime.rb pl=17         # ToA довільного payload'у
#
# ЧОМУ ця модель існує (вимір 2026-09-11, FW.61). Канон тримав ДВА різні
# тракти під однаково авторитетними підписами: блок «Параметри LoRa (Silken
# Net default)» у 03_05 §2.1 казав 868.1 МГц / SF10, тоді як ратифікований
# енергосценарій 02_03 §9.8 (Сценарій C — єдиний energy-positive) і код
# (`Radio.SetChannel(868000000)`, `LORA_PANIC_SF`, `CAD_T_SYM_SF9_BW125_US`)
# кажуть 868.0 / SF9. Гірше: тамтешня формула вшивала LDRO=1 знаменником
# `4·(SF−2)`. Наслідок був не косметичний — із тих меж виводились «бюджетні
# факти» ledger'а, і він обіцяв «+1 байт безкоштовно» на 31 Б, якого при
# відвантаженій модуляції немає. Тобто таблиця, з якої ОБИРАЮТЬ байти,
# видавала хибний хід (00_05 §4). Лік — не підправити числа, а завести
# МОДЕЛЬ, яка їх перераховує (ssot-maintenance §Guard-craft #95).
#
# ⛔ Профіль тут НЕ дублюється: він читається з `firmware/common/lora_phy.h`
# — того самого набору, який компілюють обидві прошивки. Третього дому в
# цих номіналів бути не повинно.
#
# СТЕЛЯ, оголошена вголос: модель рахує LoRa-кадр за формулою Semtech і
# нічого не знає про реальний ефір — RF-тракт, антену, e.i.r.p. і чинні
# умови НКЕК (00_07 ARCH.24) вона не судить. `--check-canon` бачить лише
# рядки таблиці, які вміє розпізнати її ж парсер, тому розмір множини
# перевіряється окремо: скорочена/порожня таблиця інакше пройшла б зеленою.

HEADER = File.expand_path("../../firmware/common/lora_phy.h", __dir__)
CANON_DOC = File.expand_path("../../docs/03_05_Hardware_Symmetric_Crypto_and_Security.md", __dir__)
ENERGY_DOC = File.expand_path("../../docs/02_03_BQ25570_MPPT_Nano_Power.md", __dir__)

# Якорі airtime із ЧУЖОГО дому (02_03 §9.6). Значення транскрибовані СВІДОМО:
# розпізнавати їх регексом по прозі означало б ключуватись на формі речення
# (`guard-craft` #94), а речення там троє й усі різні. Натомість гейт окремо
# доводить, що транскрипція ще ЖИВА — кожне число мусить дослівно стояти в
# тому домі. Так ловиться і дрейф моделі, і дрейф сусіда, без парсера прози.
# ⛔ Не міняти тут число, не змінивши його в 02_03 — гейт саме це й спіймає.
ENERGY_ANCHORS = { 16 => 164.9, 17 => 164.9, 30 => 226.3 }.freeze
# Як ті самі числа НАПИСАНІ в 02_03 §9.6 (там і точна, і округлена форми).
ENERGY_ANCHOR_LITERALS = [ "164.9", "226" ].freeze

CANON_ROWS_EXPECTED = 7

# ── Профіль із прошивки ────────────────────────────────────────────────
def read_profile(text)
  nums = text.scan(/^#define\s+(LORA_PHY_\w+)\s+(-?\d+)u?\b/).to_h { |k, v| [ k, Integer(v) ] }
  # Булеві ловимо ОКРЕМО: доти регекс брав лише цифри, тож `crcOn`/`fixLen`/`iqInverted`
  # у PROFILE не потрапляли взагалі — і `--check-canon` міг лише перевірити, що РЯДОК
  # існує, а не що значення збігається. Перевернувши `crcOn = false` у каноні, ти
  # проходив гейт зеленим (знайдено адверсарним ревʼю 2026-09-11).
  bools = text.scan(/^#define\s+(LORA_PHY_\w+)\s+(true|false)\b/).to_h { |k, v| [ k, v == "true" ] }
  defines = nums.merge(bools)
  missing = %w[LORA_PHY_FREQ_HZ LORA_PHY_SF LORA_PHY_BW_HZ LORA_PHY_CR
               LORA_PHY_PREAMBLE_SYMBOLS LORA_PHY_TX_POWER_DBM] - defines.keys
  abort("lora_phy.h: не знайдено #{missing.join(', ')} — парсер або заголовок змінились") unless missing.empty?
  defines
end

PROFILE = read_profile(File.read(HEADER))
SF = PROFILE.fetch("LORA_PHY_SF")
BW_HZ = PROFILE.fetch("LORA_PHY_BW_HZ")
CR = PROFILE.fetch("LORA_PHY_CR")
PREAMBLE = PROFILE.fetch("LORA_PHY_PREAMBLE_SYMBOLS")
FREQ_HZ = PROFILE.fetch("LORA_PHY_FREQ_HZ")
TX_DBM = PROFILE.fetch("LORA_PHY_TX_POWER_DBM")

# LowDatarateOptimize — НЕ наш вибір і не константа: драйвер виводить його
# сам (`radio.c` RadioSetRx/TxConfig): 1 лише при (BW125 ∧ SF∈{11,12}) або
# (BW250 ∧ SF12). Дзеркалимо ту саму умову, щоб модель не розійшлась із
# кремнієм на іншій робочій точці.
def ldro?(spreading_factor, bandwidth_hz)
  (bandwidth_hz == 125_000 && [ 11, 12 ].include?(spreading_factor)) ||
    (bandwidth_hz == 250_000 && spreading_factor == 12)
end

def t_sym_us(spreading_factor = SF, bandwidth_hz = BW_HZ)
  (2**spreading_factor) * 1_000_000 / bandwidth_hz
end

# Semtech SX126x: n_payload = 8 + max(ceil((8·PL − 4·SF + 28 + 16·CRC − 20·IH)
#                                     / (4·(SF − 2·DE))) · (CR + 4), 0)
def payload_symbols(payload_bytes, spreading_factor: SF, bandwidth_hz: BW_HZ, coderate: CR,
                    crc_on: true, implicit_header: false)
  de = ldro?(spreading_factor, bandwidth_hz) ? 1 : 0
  num = 8 * payload_bytes - 4 * spreading_factor + 28 + (crc_on ? 16 : 0) - (implicit_header ? 20 : 0)
  den = 4 * (spreading_factor - 2 * de)
  8 + [ (num.to_f / den).ceil * (coderate + 4), 0 ].max
end

def toa_us(payload_bytes, **opts)
  sym = t_sym_us(opts.fetch(:spreading_factor, SF), opts.fetch(:bandwidth_hz, BW_HZ))
  preamble_us = (PREAMBLE + 4.25) * sym
  preamble_us + payload_symbols(payload_bytes, **opts) * sym
end

def toa_ms(payload_bytes, **opts) = toa_us(payload_bytes, **opts) / 1000.0

# Межі символьного блоку, у якому лежить payload_bytes: сусідні довжини, що
# коштують РІВНО стільки ж. Саме це питання ставить wire-budget ledger.
def symbol_block(payload_bytes)
  n = payload_symbols(payload_bytes)
  lo = payload_bytes
  lo -= 1 while lo > 1 && payload_symbols(lo - 1) == n
  hi = payload_bytes
  hi += 1 while hi < 255 && payload_symbols(hi + 1) == n
  (lo..hi)
end

# Ключові кадри тракту — імена беруться з канону, не вигадуються тут.
KEY_FRAMES = {
  16 => "ECB air-кадр (transitional, живий сьогодні)",
  17 => "найменший не-control кадр (SILENCE-1 pulse-гіпотеза)",
  21 => "Rails-розпаковка (`N n c C n C C a4`)",
  24 => "CCM air rev1 (історичний)",
  28 => "CCM air rev2 (історичний)",
  30 => "CCM air rev2.1 (заморожений формат)",
  31 => "rev2.1 + 1 байт headroom"
}.freeze

def report
  puts "LoRa PHY-профіль (firmware/common/lora_phy.h — дім номіналів 03_05 §2.1):"
  puts format("  %.1f МГц · SF%d · BW %d кГц · CR 4/%d · преамбула %d симв · +%d дБм",
              FREQ_HZ / 1e6, SF, BW_HZ / 1000, CR + 4, PREAMBLE, TX_DBM)
  puts format("  T_sym = 2^%d / %d Гц = %d мкс · LDRO = %s (драйвер виводить сам)",
              SF, BW_HZ, t_sym_us, ldro?(SF, BW_HZ) ? "1" : "0")
  puts
  puts format("  %-4s %-9s %-11s %-13s %s", "PL", "символів", "T_air, мс", "блок, Б", "що це")
  KEY_FRAMES.each do |pl, what|
    blk = symbol_block(pl)
    puts format("  %-4d %-9d %-11.1f %-13s %s", pl, payload_symbols(pl), toa_ms(pl),
                "#{blk.first}..#{blk.last}", what)
  end
  puts
  nxt = symbol_block(30).last + 1
  puts "Ціна наступного байта після rev2.1 (30 Б): " \
       "#{format('%+.1f', toa_ms(nxt) - toa_ms(30))} мс — 30 Б є ОСТАННІМ у своєму блоці."
  duty = toa_ms(30) / 1000.0 / 0.01
  puts format("Duty-cycle 1%% (EU868 g1) на кадрі 30 Б → мінімальний період %.1f с.", duty)
end

def assert_mode
  errors = []

  # 1. Якір у ЧУЖОМУ домі — дві половини, і обидві потрібні: модель мусить
  #    відтворювати транскрибовані числа, А транскрипція мусить ще стояти в
  #    02_03. Без другої половини це самоперевірка під виглядом зовнішньої
  #    (адверсарне ревʼю 2026-09-11).
  energy = File.read(ENERGY_DOC)
  ENERGY_ANCHOR_LITERALS.each do |lit|
    errors << "02_03 §9.6 більше не містить «#{lit}» — якір протух, звір дім перед правкою" \
      unless energy.include?(lit)
  end
  ENERGY_ANCHORS.each do |pl, stated|
    got = toa_ms(pl)
    errors << format("PL=%d: модель %.1f мс ≠ якір 02_03 §9.6 %.1f мс", pl, got, stated) if (got - stated).abs > 0.2
  end

  # 2. LDRO-правило мусить збігатися з умовою драйвера (radio.c), інакше
  #    модель описує не наш кремній.
  errors << "LDRO при SF#{SF}/BW#{BW_HZ} має бути 0 — перевір дзеркало умови radio.c" if ldro?(SF, BW_HZ)
  errors << "LDRO при SF12/BW125 має бути 1 — дзеркало умови radio.c зламане" unless ldro?(12, 125_000)

  # 3. Профіль сам собі несуперечливий: T_sym, виведений тут, дорівнює тому,
  #    що заголовок віддає препроцесором (і що пінить cad_sniff.h).
  errors << "T_sym=#{t_sym_us} мкс ≠ 4096 — SF/BW у lora_phy.h зсунулись без свіпу CAD-математики" \
    unless t_sym_us == 4096

  # 4. Монотонність: довший кадр не може коштувати менше airtime.
  prev = 0.0
  (1..64).each do |pl|
    cur = toa_ms(pl)
    errors << "ToA не монотонна на PL=#{pl} (#{prev.round(1)} → #{cur.round(1)})" if cur < prev - 1e-9
    prev = cur
  end

  if errors.empty?
    puts "✅ lora_airtime: SF#{SF}/BW#{BW_HZ / 1000}к/CR4:#{CR + 4}, T_sym=#{t_sym_us}мкс, LDRO=0 · " \
         "16Б=#{toa_ms(16).round(1)}мс · 30Б=#{toa_ms(30).round(1)}мс (парність із 02_03 §9.6)"
    exit 0
  end
  warn "❌ lora_airtime FAIL:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
end

# Рядок таблиці 03_05 §2.1: `| 16 | 28 | 164.9 | … |`
CANON_ROW = /^\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*([\d.]+)\s*\|/

# Профіль у каноні тримає ТРЕТЯ колонка — аргумент драйвера дослівно
# (`datarate = 9`, `Radio.SetChannel(868000000)`). Саме її, а не прозу
# другої, звіряємо з `lora_phy.h`: гейт по формі аргументу не плутається
# в одиницях («125 кГц» ⊥ `bandwidth = 0`).
CANON_PROFILE_KEYS = {
  "datarate" => "LORA_PHY_SF",
  "bandwidth" => "LORA_PHY_BW",
  "coderate" => "LORA_PHY_CR",
  "preambleLen" => "LORA_PHY_PREAMBLE_SYMBOLS",
  "power" => "LORA_PHY_TX_POWER_DBM"
}.freeze
CANON_PROFILE_EXPECTED = CANON_PROFILE_KEYS.size + 1 # + SetChannel

def parse_canon_profile(section)
  found = {}
  section.each_line do |line|
    next unless line.start_with?("|")

    found["LORA_PHY_FREQ_HZ"] = Integer(Regexp.last_match(1)) if line =~ /SetChannel\((\d+)\)/
    CANON_PROFILE_KEYS.each do |arg, define|
      found[define] = Integer(Regexp.last_match(1)) if line =~ /\b#{arg}\s*=\s*(-?\d+)/
    end
  end
  found
end

# Секція обмежується ВЛАСНИМ ПРЕДМЕТОМ, а не заголовком. Доти вона
# чіплялась за текст `#### …`, і перше ж перейменування заголовка зробило
# обидві множини порожніми — гейт почервонів правильно, але назвав не ту
# причину (`ssot-maintenance` §Guard-craft #50: гейт тримає док за
# ІДЕНТИФІКАТОР і не бачить, що субʼєкт лишився на місці). Лід профілю —
# те, що не може змінитись без зміни самого предмета.
SECTION_START = "**Базлайн raw-LoRa P2P"
def canon_section(text)
  i = text.index(SECTION_START)
  return "" if i.nil?

  tail = text[i..]
  stop = tail.index(/\n#{'#' * 3}+ /)
  stop.nil? ? tail : tail[0...stop]
end

def parse_canon_table(text)
  section = canon_section(text)
  return [] if section.empty?

  section.each_line.filter_map do |line|
    m = CANON_ROW.match(line)
    next if m.nil?

    { pl: Integer(m[1]), symbols: Integer(m[2]), toa_ms: Float(m[3]) }
  end
end

def check_canon_mode
  doc = File.read(CANON_DOC)
  section = canon_section(doc)
  rows = parse_canon_table(doc)
  problems = []

  # One-Home: профіль у каноні мусить дослівно дорівнювати тому, що компілює
  # прошивка. Це єдина вісь, де гейт судить ДВА наші доми один проти одного,
  # тож розмір множини пінимо окремо — інакше зникла колонка читається як згода.
  canon_profile = parse_canon_profile(section)
  if canon_profile.size != CANON_PROFILE_EXPECTED
    problems << "профіль: розпізнано #{canon_profile.size} з #{CANON_PROFILE_EXPECTED} аргументів " \
                "— колонка «Аргумент драйвера» змінила форму; неповна множина мовчки згодна"
  end
  canon_profile.each do |define, canon_value|
    firmware_value = PROFILE[define]
    if firmware_value.nil?
      problems << "профіль: канон називає #{define}, а lora_phy.h його не має"
    elsif firmware_value != canon_value
      problems << "профіль #{define}: канон #{canon_value}, lora_phy.h #{firmware_value}"
    end
  end
  { "crcOn" => "LORA_PHY_CRC_ON", "fixLen" => "LORA_PHY_FIX_LEN" }.each do |flag, define|
    m = section.match(/\b#{flag}\s*=\s*(true|false)\b/)
    if m.nil?
      problems << "профіль: у таблиці немає рядка `#{flag} = …` — пакетні прапорці не гейтовані"
      next
    end
    canon_bool = m[1] == "true"
    problems << "профіль #{define}: канон #{canon_bool}, lora_phy.h #{PROFILE[define]}" if PROFILE[define] != canon_bool
  end

  if rows.size != CANON_ROWS_EXPECTED
    problems << "розмір множини: розпізнано #{rows.size} рядків, очікувано #{CANON_ROWS_EXPECTED} " \
                "— парсер або таблиця змінились; скорочена множина проходить зеленою мовчки"
  end
  rows.each do |row|
    sym = payload_symbols(row[:pl])
    got = toa_ms(row[:pl])
    if row[:symbols] != sym
      problems << format("PL=%d: таблиця каже %d символів, модель дає %d", row[:pl], row[:symbols], sym)
    end
    if (row[:toa_ms] - got).abs > 0.2
      problems << format("PL=%d: таблиця каже %.1f мс, модель дає %.1f мс", row[:pl], row[:toa_ms], got)
    end
  end
  problems.each { |p| warn "FAIL  #{CANON_DOC.sub("#{Dir.pwd}/", '')} — #{p}" }
  puts problems.empty? ? "OK  §2.1 airtime-таблиця (#{rows.size} рядків) збігається з моделлю" : "RED"
  exit(problems.empty? ? 0 : 1)
end

case ARGV.first
when "--assert" then assert_mode
when "--check-canon" then check_canon_mode
when nil then report
when /\Apl=\d+\z/
  pl = Integer(ARGV.first.split("=", 2).last)
  blk = symbol_block(pl)
  puts format("PL=%d → %d символів, T_air = %.1f мс (блок %d..%d Б коштує стільки ж)",
              pl, payload_symbols(pl), toa_ms(pl), blk.first, blk.last)
else
  warn "невідомий режим #{ARGV.first.inspect}; доступні: (порожньо) · --assert · --check-canon · pl=<байт>"
  exit 2
end
