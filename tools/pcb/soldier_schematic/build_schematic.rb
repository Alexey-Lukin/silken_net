#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [HW.56] Схема силового деку Солдата — генератор. Пише `soldier_power.kicad_sch` (+ власну бібліотеку
# символів, проєктну таблицю бібліотек і мінімальний `.kicad_pro`): людина відкриває схему в KiCad 10,
# агент перевіряє без вікна. Рішення, форма й межа — `docs/02_01 §7`; робота — `docs/00_07` HW.56.
# ⛔ Схему руками не правити: правка — тут, файл перегенеровується, а `--check` червоніє, якщо закомічене
# відстало від генератора.
#
#   ruby tools/pcb/soldier_schematic/build_schematic.rb          # згенерувати + перевірки, вихід у out/
#   ruby tools/pcb/soldier_schematic/build_schematic.rb --check  # те саме, і червоніє на застарілих файлах
#
# Перевірки (кожна валить прогін): ERC усіх рівнів · експорт PDF і SPICE-нетліста · фаради з голим `F` у
# нетлісті · ЗВІРКА З’ЄДНАНЬ — генератор окремо тримає ЗАДУМАНЕ (пін → мережа) і окремо МАЛЮНОК (дроти,
# мітки, символи землі), експортує нетліст самого KiCad і вимагає, щоб кожен пін лежав у задуманій мережі.
# Дріт, що зачепив чужий пін, чи мітка, перейменована на наявну мережу, ERC-у не видні (жодна мітка не
# висить), а звірці видні.
#
# Звідки кожне число (одна річ — один дім):
#   • плечі дільників BQ25570 — таблиця `02_03 §5`, прочитана тим самим `parse_canon_table`, яким
#     `tools/firmware/bq25570_dividers.rb --check-canon` судить канон: схема з каноном розійтися не може,
#     доки ганяють `--check` (у CI — ще відкрита нога HW.56);
#   • символи — стандартні бібліотеки KiCad 10, вбудовані в схему копією;
#   • P/N у схему НЕ копіюються: поле «BOM» кожної деталі — вказівник на `02_01 §3.1` поз. N.
#
# Розпіновку BQ25570 звірено з таблицею пінів SLUSBH2G (березень 2019). Дві правки символу — за паспортом,
# не за бібліотекою, тож виправлений символ живе у власній бібліотеці `SilkenNet`:
#   • `VBAT` (18): бібліотека — `power_in`, паспорт — I/O (чип веде його зсередини від VSTOR);
#   • `VOUT` (14): бібліотека — `input`, паспорт — O (вихід buck).
# Піни 9 і 17 у паспорті — NC «на землю через PowerPAD»; бібліотека зве їх VSS і складає з 1, 15 і 21
# в одну точку — схема тягне цю точку на GND, як велить паспорт.
# Символів кламп- і ключ-деталей KiCad не має — вони будуються тут із таблиць пінів (`OWN_SYMBOLS`):
#   • TLV840N…PL — SNVSBC3C Figure 6-3; NC 4 і 5 на GND — «Recommended connection to GND» паспорта;
#   • TPS22860 — SLVSD04 §6; NC 3 вільний (паспорт землі не просить);
#   • DMN2990UFA — графіка стокового Q_NMOS, номери — землі `tools/pcb/hw12_dmn2990ufa_breakout` (1 G · 2 S · 3 D):
#     паспорт DS35765 падів не нумерує, а його мітка Pin#1 стоїть на СТОКУ — тож «pin 1» виробника ≠ наш пад 1.
#
# Вузли трирезисторного стеку VBAT_OK — з рівнянь паспорта: Eq. 4 (поріг на зростанні) = VBIAS·(1 +
# (ROK2 + ROK3)/ROK1) — вузол над ROK1 при повному стеку; Eq. 3 (на спаданні) = VBIAS·(1 + ROK2/ROK1) —
# той самий вузол при закороченому ROK3. Тож `OK_PROG` — між ROK1 і ROK2, `OK_HYST` — між ROK2 і ROK3,
# ROK3 — до VRDIV. Верхнє плече MPPT (ROC2) — на VIN_DC, не на VRDIV: присуд `02_03 §4.А`.
#
# ⛔ ОГОЛОШЕНІ СТЕЛІ — читай як перелік того, чого цей файл НЕ доводить:
#   • Аркуш ЛОГІЧНИЙ — силовий тракт, а не дека: поз. 23 стоїть тут, бо живиться з VSTOR, а на якій деці вона
#     сяде, вирішує розводка HW.9 (природне місце — верх RF Deck, `02_01 §7.1`).
#   • v2 — BQ25570 з обвʼязкою, кламп поз. 14 і ключ Vcap-sense поз. 23; MCU на аркуші немає, тож ON і ADC ключа
#     виходять з аркуша глобальними мітками (`OFF_SHEET`), а пін MCU обирає `.ioc` (`docs/00_07` FW.46).
#   • P/N клампа — кандидати HW.12 (значення несе «(кандидат)»), номінали R_dump і pull-down затвора — рекомендація
#     шортлиста; номінали дільника Vcap не обрано («не обрано», поза симуляцією).
#   • Номінали L і C живуть тут і в BOM `02_01 §3.1` — звіряються очима, гейта між ними немає.
#   • ⛔ Фаради пиши через масштаб (`470mF`), ніколи голим `F`: у SPICE `F` у будь-якому регістрі — ФЕМТО, і
#     KiCad при експорті його не перекладає (`M` → `Meg` перекладає), тож `0.47F` іоністора ngspice прочитав
#     би як 0.47 фФ.
#   • Відкрите в каноні лишається відкритим і тут: `VBAT` — 100 мкФ АБО перемичка на VSTOR (`00_07` HW.9),
#     тож обидві деталі стоять DNP, жодну не обрано.
#   • U1 · U2 · U3 · Q1 виключено із симуляції (`02_01 §7`): моделей BQ25570, TPS22860 і варіанта NAPL50 немає, а модель
#     DMN2990UFA підпорогового струму не має, тож `IDSS` клампа не передбачила б; SPICE-нетліст пасивних
#     симуляцією тракту НЕ є, і його ніхто не проганяє: «SPICE exit 0» доводить лише ЕКСПОРТ.
#   • Багатоодиничні символи (кілька unit чи body style) генератор не підтримує й відмовляє вголос.
#   • Форма — гібрид (⚖️ делеговано 2026-11-08, `02_01 §7`): земля — символом, дільники — сходинками з
#     дротами, паралельні конденсатори — на шині, піни мікросхеми — заглушка з міткою. Звірка стереже
#     ЗʼЄДНАННЯ, а не читабельність: «читається» судить людина.

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../../firmware/bq25570_dividers"

HERE = __dir__
NAME = "soldier_power"
KICAD_APP = File.expand_path("~/Applications/KiCad/KiCad.app")
SYMBOL_DIR = [ ENV["KICAD_SYMBOL_DIR"], ENV["KICAD10_SYMBOL_DIR"], "#{KICAD_APP}/Contents/SharedSupport/symbols",
               "/usr/share/kicad/symbols" ].compact.find { |d| File.directory?(d) } ||
             abort("FAIL: бібліотек символів KiCad 10 не знайдено — задай KICAD_SYMBOL_DIR")
KICAD_CLI = [ ENV["KICAD_CLI"], "#{KICAD_APP}/Contents/MacOS/kicad-cli" ].compact.find { |p| File.executable?(p) } ||
            "kicad-cli"
GRID = 1.27
STUB = 2.54
RUNG = 7.62 # крок плечей у сходинці дільника
RAIL = 10.16 # крок деталей на шині — ширший, щоб номінали не злипались
OWN_LIB = "SilkenNet"
GROUND = "GND"
# Мережі, що йдуть з аркуша до MCU (його на цьому аркуші немає), — глобальна мітка з напрямком, як його бачить
# силовий дек. Пін MCU тут не обрано: пін-мапу тримає `.ioc` (`docs/00_07` FW.46), не схема.
OFF_SHEET = { "VCAP_SENSE_EN" => :input, "VCAP_ADC" => :output }.freeze

# ── S-вирази KiCad: розбір і запис ────────────────────────────────────────────────────────────────
module Sexp
  Atom = Struct.new(:v)

  module_function

  def parse(src)
    stack = [ [] ]
    src.scan(/\(|\)|"(?:\\.|[^"\\])*"|[^\s()"]+/) do |t|
      case t
      when "(" then stack.push([])
      when ")" then (done = stack.pop) && stack.last << done
      when /\A"/ then stack.last << t[1..-2].gsub(/\\(.)/) { Regexp.last_match(1) == "n" ? "\n" : Regexp.last_match(1) }
      else stack.last << Atom.new(t)
      end
    end
    stack.first
  end

  def head(node) = node.first.is_a?(Atom) ? node.first.v : node.first.to_s
  def child(node, name) = node.find { |e| e.is_a?(Array) && head(e) == name }
  def children(node, name) = node.select { |e| e.is_a?(Array) && head(e) == name }

  # Глибока копія дерева: масиви копіюються, атоми й рядки ніхто не мутує на місці (правка піна заміняє
  # елемент масиву). Не `Marshal` — той Brakeman слушно позначає як шлях до виконання коду.
  def copy(node) = node.is_a?(Array) ? node.map { |e| copy(e) } : node

  def num(x)
    s = format("%.4f", x.to_f).sub(/0+\z/, "").sub(/\.\z/, "")
    s == "-0" ? "0" : s
  end

  def atom(x)
    case x
    when Atom then x.v
    when Symbol then x.to_s
    when String then "\"#{x.gsub(/[\\"]/) { |c| "\\#{c}" }.gsub("\n", '\\n')}\""
    when Integer then x.to_s
    when Numeric then num(x)
    else raise "незнайомий атом #{x.inspect}"
    end
  end

  def dump(node, depth = 0)
    return atom(node) unless node.is_a?(Array)
    return "(#{node.map { |e| atom(e) }.join(' ')})" if node.none?(Array)

    lead = node.take_while { |e| !e.is_a?(Array) }
    pad = "\t" * (depth + 1)
    body = node.drop(lead.size).map { |e| pad + dump(e, depth + 1) }
    "(#{lead.map { |e| atom(e) }.join(' ')}\n#{body.join("\n")}\n#{"\t" * depth})"
  end
end

# ── Стандартні символи KiCad ──────────────────────────────────────────────────────────────────────
module Lib
  module_function

  def tree(lib) = (@trees ||= {})[lib] ||= Sexp.parse(File.read(File.join(SYMBOL_DIR, "#{lib}.kicad_sym"))).first

  def symbol(lib, name)
    sym = tree(lib).find { |e| e.is_a?(Array) && Sexp.head(e) == "symbol" && e[1] == name } ||
          raise("#{lib}:#{name} у бібліотеках KiCad не знайдено")
    raise "#{lib}:#{name} — похідний символ (extends); вбудовування таких не підтримано" if Sexp.child(sym, "extends")

    Sexp.copy(sym)
  end

  def pins(sym)
    units = sym.select { |e| e.is_a?(Array) && Sexp.head(e) == "symbol" }.map { |e| e[1].to_s[/_(\d+)_(\d+)\z/, 0] }
    raise "#{sym[1]}: багатоодиничний символ — не підтримано" if units.compact.any? { |u| u.split("_").drop(1).any? { |d| d.to_i > 1 } }

    found = []
    walk = lambda do |n|
      next unless n.is_a?(Array)
      next n.each { |e| walk.call(e) } unless Sexp.head(n) == "pin"

      at = Sexp.child(n, "at")
      found << { node: n, number: Sexp.child(n, "number")[1], name: Sexp.child(n, "name")[1],
                 x: at[1].v.to_f, y: at[2].v.to_f, angle: at[3].v.to_i }
    end
    walk.call(sym)
    found
  end
end

# ── Власні символи: розпіновка з таблиці пінів паспорта ───────────────────────────────────────────────
# У KiCad 10 цих деталей немає (звірено з позитивним контролем: BQ25570 і сусіди родин — TPS22810 · TPS22917 ·
# TLV810E — у бібліотеках знаходяться). Номер і імʼя кожного піна — з паспорта, тип — наше прочитання його I/O; бік і
# зсув — наш вибір малюнка. Тип піна судить ERC, тож NC, який паспорт радить тягнути на землю, — `passive`: пін типу
# `no_connect` ERC підʼєднувати забороняє. Дерево проганяється через dump → parse, щоб мати ту саму форму
# (атоми, а не числа), що й стокові символи, — далі генератор їх не розрізняє.
module Own
  module_function

  FONT = [ :effects, [ :font, [ :size, 1.27, 1.27 ] ] ].freeze
  SIDE = { left: ->(w, _h, o) { [ -w - STUB, o, 0 ] }, right: ->(w, _h, o) { [ w + STUB, o, 180 ] },
           top: ->(_w, h, o) { [ o, h + STUB, 270 ] }, bottom: ->(_w, h, o) { [ o, -h - STUB, 90 ] } }.freeze

  def prop(key, value, x, y, hide: true)
    [ :property, key, value, [ :at, x, y, 0 ], [ :show_name, :no ], [ :do_not_autoplace, :no ],
      *([ [ :hide, :yes ] ] if hide), FONT ]
  end

  # pins — [номер, імʼя, тип, бік, зсув уздовж боку від центру]
  def ic(name, half_w:, half_h:, pins:, footprint:, datasheet:, description:)
    pin = lambda do |number, pin_name, type, side, offset|
      [ :pin, type, :line, [ :at, *SIDE.fetch(side).call(half_w, half_h, offset) ], [ :length, STUB ],
        [ :name, pin_name, FONT ], [ :number, number, FONT ] ]
    end
    tree = [ :symbol, name, [ :exclude_from_sim, :no ], [ :in_bom, :yes ], [ :on_board, :yes ], [ :in_pos_files, :yes ],
             [ :duplicate_pin_numbers_are_jumpers, :no ],
             prop("Reference", "U", -half_w, half_h + 1.27, hide: false), prop("Value", name, 0, -half_h - 1.27, hide: false),
             prop("Footprint", footprint, 0, 0), prop("Datasheet", datasheet, 0, 0), prop("Description", description, 0, 0),
             [ :symbol, "#{name}_0_1", [ :rectangle, [ :start, -half_w, half_h ], [ :end, half_w, -half_h ],
                                         [ :stroke, [ :width, 0.254 ], [ :type, :default ] ], [ :fill, [ :type, :background ] ] ] ],
             [ :symbol, "#{name}_1_1", *pins.map { |p| pin.call(*p) } ], [ :embedded_fonts, :no ] ]
    Sexp.parse(Sexp.dump(tree)).first
  end

  # Графіка стокового `Device:Q_NMOS` (у KiCad 10 його піни звуться літерами D · G · S), перенумерована на
  # пади землі, з якою ключ ставитимуть.
  def nmos(name, numbers:, datasheet:, description:)
    sym = Lib.symbol("Device", "Q_NMOS")
    old = sym[1]
    sym[1] = name
    Sexp.children(sym, "symbol").each { |u| u[1] = u[1].sub(/\A#{Regexp.escape(old)}_/, "#{name}_") }
    Lib.pins(sym).each { |p| Sexp.child(p[:node], "number")[1] = numbers.fetch(p[:number]) }
    { "Value" => name, "Datasheet" => datasheet, "Description" => description }.each do |key, value|
      Sexp.children(sym, "property").find { |p| p[1] == key }[2] = value
    end
    sym
  end
end

OWN_SYMBOLS = {
  # SNVSBC3C (09/2020): Figure 6-3 «TLV840N, DBV» і Pin Functions; номенклатура (табл. 12-1): N — без CT і MR,
  # PL — push-pull, active-low. NC 4 і 5 — «Recommended connection to GND».
  "TLV840N_PL" => lambda {
    Own.ic("TLV840N_PL", half_w: 7.62, half_h: 5.08, footprint: "Package_TO_SOT_SMD:SOT-23-5",
                         datasheet: "https://www.ti.com/lit/ds/symlink/tlv840.pdf",
                         description: "Supervisor TLV840N..PL (push-pull, active-low), SOT-23-5 DBV; pins per SNVSBC3C Fig. 6-3",
                         pins: [ [ "1", "~{RESET}", :output, :right, 0 ], [ "2", "VDD", :power_in, :left, 0 ],
                                 [ "3", "GND", :power_in, :bottom, -5.08 ], [ "4", "NC", :passive, :bottom, 0 ],
                                 [ "5", "NC", :passive, :bottom, 5.08 ] ])
  },
  # SLVSD04 (04/2015) «Pin Configuration and Functions»; orderable лише DBV (addendum того ж PDF).
  "TPS22860" => lambda {
    Own.ic("TPS22860", half_w: 7.62, half_h: 5.08, footprint: "Package_TO_SOT_SMD:SOT-23-6",
                       datasheet: "https://www.ti.com/lit/ds/symlink/tps22860.pdf",
                       description: "Ultra-low-leakage load switch, SOT-23-6 DBV; pins per SLVSD04 section 6",
                       pins: [ [ "1", "VOUT", :power_out, :right, 2.54 ], [ "2", "GND", :power_in, :bottom, 0 ],
                               [ "3", "NC", :no_connect, :right, -2.54 ], [ "4", "VIN", :power_in, :left, 2.54 ],
                               [ "5", "VBIAS", :power_in, :left, 0 ], [ "6", "ON", :input, :left, -2.54 ] ])
  },
  # DS35765 Rev. 3-2 падів не нумерує: креслення корпусу (стор. 5) несе лише мітку Pin#1 — і вона на ВЕЛИКОМУ
  # паді, тобто на стоку. Номери тут — конвенція землі `tools/pcb/hw12_dmn2990ufa_breakout` (1 = G, 2 = S, 3 = D):
  # символ мусить говорити мовою того футпринта, з яким ключ ставитимуть.
  "DMN2990UFA" => lambda {
    Own.nmos("DMN2990UFA", numbers: { "G" => "1", "S" => "2", "D" => "3" },
                           datasheet: "https://www.diodes.com/assets/Datasheets/DMN2990UFA.pdf",
                           description: "N-MOSFET 20 V, X2-DFN0806-3; pad numbers = land pattern of tools/pcb/hw12_dmn2990ufa_breakout")
  }
}.freeze

# ── Аркуш: ЗАДУМАНЕ (пін → мережа) окремо від МАЛЮНКА ──────────────────────────────────────────────
class Sheet
  ROOT = "0a1b2c3d-4e5f-5a6b-8c7d-9e0f1a2b3c4d"
  # Пін дивиться ВІД точки зʼєднання ДО тіла символу; заглушка йде у протилежний бік.
  OUTWARD = { 0 => [ -1, 0 ], 180 => [ 1, 0 ], 90 => [ 0, 1 ], 270 => [ 0, -1 ] }.freeze
  LABEL = { [ -1, 0 ] => [ 180, %i[right bottom] ], [ 1, 0 ] => [ 0, %i[left bottom] ],
            [ 0, 1 ] => [ 270, %i[right bottom] ], [ 0, -1 ] => [ 90, %i[left bottom] ] }.freeze

  attr_reader :own, :stock, :intended

  def initialize
    @lib = {}
    @own = {}
    @stock = []
    @items = []
    @points = {}
    @intended = {}
    @power = 0
  end

  def self.uid(key)
    h = Digest::SHA1.hexdigest("silkennet/HW.56/#{NAME}/#{key}")
    "#{h[0, 8]}-#{h[8, 4]}-5#{h[13, 3]}-#{((h[16, 2].to_i(16) & 0x3f) | 0x80).to_s(16)}#{h[18, 2]}-#{h[20, 12]}"
  end

  # Кожен пін символу мусить отримати мережу ЯВНО (`:nc` — теж явно): пропущений пін — помилка генератора,
  # а не тихий обрив. `draw: false` — зʼєднання малює викличник (сходинка, шина); задумане пишеться завжди.
  # Повертає { номер піна → [x, y] } — кінці пінів на аркуші.
  def place(lib_id, ref, value, at:, nets:, draw: true, bom: nil, note: nil, dnp: false, sim: true, in_bom: true, patch: {},
            tag_at: [ 2.54, -1.27 ])
    lib_id, sym = embed(lib_id, patch)
    x, y = at
    on_grid!(ref, x, y)
    pins = Lib.pins(sym)
    numbers = pins.map { |p| p[:number] }.uniq
    extra = nets.keys - numbers
    missing = numbers - nets.keys
    raise "#{ref}: невідомі піни #{extra}" unless extra.empty?
    raise "#{ref}: піни без мережі #{missing}" unless missing.empty?

    node = [ :symbol, [ :lib_id, lib_id ], [ :at, x, y, 0 ], [ :unit, 1 ], [ :exclude_from_sim, sim ? :no : :yes ],
             [ :in_bom, in_bom ? :yes : :no ], [ :on_board, :yes ], [ :dnp, dnp ? :yes : :no ],
             [ :uuid, Sheet.uid("sym/#{ref}") ],
             prop("Reference", ref, x + tag_at[0], y + tag_at[1], shown: !ref.start_with?("#")),
             prop("Value", value, x + tag_at[0], y + tag_at[1] + 2.54, shown: true),
             prop("Footprint", "", x, y), prop("Datasheet", "", x, y), prop("Description", "", x, y) ]
    node << prop("BOM", bom, x, y) if bom
    node << prop("Примітка", note, x, y) if note
    numbers.each { |n| node << [ :pin, n, [ :uuid, Sheet.uid("pin/#{ref}/#{n}") ] ] }
    node << [ :instances, [ :project, NAME, [ :path, "/#{ROOT}", [ :reference, ref ], [ :unit, 1 ] ] ] ]
    @items << node
    pins.each { |p| @intended[[ ref, p[:number] ]] = nets.fetch(p[:number]) } unless ref.start_with?("#")
    pins.each { |p| connect(ref, p, x, y, nets.fetch(p[:number])) } if draw
    pins.each_with_object({}) { |p, ends| ends[p[:number]] ||= [ x + p[:x], y - p[:y] ] }
  end

  # Дільник — вертикальна сходинка: верх — заглушка з міткою `nets.first`, вузли між плечима — гілка
  # вправо з міткою, низ — символ землі. `nets` — від верху до низу, на одну більше, ніж плечей.
  def divider(arms, nets, x:, y:, **opts)
    raise "сходинка #{arms.map(&:first)}: низ мусить бути #{GROUND}" unless nets.last == GROUND

    ends = arms.each_with_index.map do |(ref, value), i|
      place("Device:R_Small", ref, value, at: [ x, y + (i * RUNG) ], nets: { "1" => nets[i], "2" => nets[i + 1] },
                                          draw: false, **opts)
    end
    tag = arms.first.first
    lead_up(ends.first["1"], nets.first, tag)
    ends.each_cons(2).with_index do |(upper, lower), i|
      node = upper["2"]
      branch = [ node[0] + (4 * STUB), node[1] ] # довша гілка: мітка не налазить на номінал плеча
      wire(node, lower["1"], "#{tag}/rung#{i}")
      wire(node, branch, "#{tag}/branch#{i}")
      junction(node, "#{tag}/node#{i}")
      label(branch, nets[i + 1], [ 1, 0 ], "#{tag}/node#{i}")
    end
    ground(ends.last["2"], "#{tag}/bottom")
  end

  # Шина: паралельні двополюсники однієї мережі — верхи з’єднані дротом, кожен низ — на землю.
  def rail(parts, net, x:, y:)
    ends = parts.each_with_index.map do |(ref, lib, value, opts), i|
      place("Device:#{lib}", ref, value, at: [ x + (i * RAIL), y ], nets: { "1" => net, "2" => GROUND }, draw: false, **opts)
    end
    tag = "rail/#{net}"
    lead_up(ends.first["1"], net, tag)
    ends.each_cons(2).with_index { |(a, b), i| wire(a["1"], b["1"], "#{tag}/#{i}") }
    ends[0...-1].each_with_index { |e, i| junction(e["1"], "#{tag}/#{i}") }
    ends.each_with_index { |e, i| ground(e["2"], "#{tag}/gnd#{i}") }
  end

  # Шунт: плече від мережі `top` до стоку ключа, витік — на землю, затвор — заглушка з міткою `gate`. Плече й
  # ключ стоять в одну вертикаль і з’єднані дротом, вузол `mid` — гілкою вбік: фізику клампа читають згори
  # вниз. Крок — із геометрії стокових `R_Small` (піни ±2.54) і `Q_NMOS` (стік +2.54/+5.08), тож дріт стоку
  # вертикальний. Дріт тягнеться між ФАКТИЧНИМИ кінцями пінів: зсунеться геометрія — він піде навскіс, і це судить
  # око, не звірка (мутацію зсуву звірка не бачить — перевірено); дріт не на той пін звірка червонить.
  def shunt(arm, fet, top:, mid:, gate:, x:, y:)
    ref, value, opts = arm
    r = place("Device:R_Small", ref, value, at: [ x, y ], nets: { "1" => top, "2" => mid }, draw: false, **opts)
    lead_up(r["1"], top, ref)
    lib_id, fref, fvalue, fopts = fet
    q = place(lib_id, fref, fvalue, at: [ x - 2.54, y + (2 * STUB) + 5.08 ], draw: false, **fopts,
                                    nets: { "1" => gate, "2" => GROUND, "3" => mid })
    node = r["2"]
    branch = [ node[0] + (4 * STUB), node[1] ]
    wire(node, q["3"], "#{fref}/drain")
    wire(node, branch, "#{fref}/branch")
    junction(node, "#{fref}/node")
    label(branch, mid, [ 1, 0 ], "#{fref}/node")
    stub = [ q["1"][0] - STUB, q["1"][1] ]
    wire(q["1"], stub, "#{fref}/gate")
    label(stub, gate, [ -1, 0 ], "#{fref}/gate")
    ground(q["2"], "#{fref}/source")
  end

  def text(str, x, y)
    @items << [ :text, str, [ :exclude_from_sim, :yes ], [ :at, x, y, 0 ],
                [ :effects, [ :font, [ :size, 1.27, 1.27 ] ], [ :justify, :left, :bottom ] ], [ :uuid, Sheet.uid("text/#{x}/#{y}") ] ]
  end

  def document
    [ :kicad_sch, [ :version, 20260306 ], [ :generator, "silkennet_hw56" ], [ :generator_version, "10.0" ],
      [ :uuid, ROOT ], [ :paper, "A3" ],
      [ :title_block, [ :title, "SilkenNet — Солдат, силовий тракт (v2)" ], [ :company, "SilkenNet" ],
        [ :comment, 1, "Згенеровано tools/pcb/soldier_schematic/build_schematic.rb — руками не правити" ],
        [ :comment, 2, "Плечі дільників — docs/02_03 §5 через bq25570_dividers.rb · P/N — docs/02_01 §3.1" ] ],
      [ :lib_symbols, *@lib.values ], *@items, [ :sheet_instances, [ :path, "/", [ :page, "1" ] ] ] ]
  end

  private

  # Символ, виправлений за паспортом, перестає бути символом KiCad: він їде у власну бібліотеку
  # `SilkenNet` (файл `silkennet.kicad_sym` поруч), і схема посилається вже на неї — тоді вбудована
  # копія збігається зі своєю бібліотекою, а ERC не скаржиться на розбіжність, якої ми припустились свідомо.
  # Символ, якого KiCad не має зовсім, генератор будує сам (`OWN_SYMBOLS`) — і він живе там само.
  def embed(lib_id, patch)
    lib, name = lib_id.split(":", 2)
    own = lib == OWN_LIB || !patch.empty?
    target = own ? "#{OWN_LIB}:#{name}" : lib_id
    sym = @lib[target] ||= begin
      s = lib == OWN_LIB ? OWN_SYMBOLS.fetch(name).call : Lib.symbol(lib, name)
      patch.each do |number, type|
        pin = Lib.pins(s).find { |p| p[:number] == number } || raise("#{lib_id}: піна #{number} немає")
        pin[:node][1] = Sexp::Atom.new(type.to_s)
      end
      @own[name] = Sexp.copy(s) if own
      @stock << lib unless own
      s[1] = target
      s
    end
    [ target, sym ]
  end

  def prop(key, value, x, y, shown: false)
    effects = [ :effects, [ :font, [ :size, 1.27, 1.27 ] ] ]
    effects << (shown ? [ :justify, :left ] : [ :hide, :yes ])
    [ :property, key, value, [ :at, x, y, 0 ], effects ]
  end

  def on_grid!(ref, *coords)
    coords.each { |c| raise "#{ref}: #{c} поза сіткою #{GRID} мм" unless ((c / GRID) - (c / GRID).round).abs < 1e-6 }
  end

  # Заглушка від піна назовні; на кінці — мітка мережі або, для землі, символ землі.
  def connect(ref, pin, sx, sy, net)
    px = sx + pin[:x]
    py = sy - pin[:y]
    key = [ px.round(3), py.round(3) ]
    if (seen = @points[key])
      raise "#{ref}.#{pin[:number]}: точка вже несе мережу #{seen}, пін просить #{net}" unless seen == net
      return
    end
    @points[key] = net
    tag = "#{ref}/#{pin[:number]}"
    return @items << [ :no_connect, [ :at, px, py ], [ :uuid, Sheet.uid("nc/#{tag}") ] ] if net == :nc

    dx, dy = OUTWARD.fetch(pin[:angle])
    stub_end = [ px + (dx * STUB), py + (dy * STUB) ]
    wire([ px, py ], stub_end, tag)
    net == GROUND ? ground(stub_end, tag, [ dx, dy ]) : label(stub_end, net, [ dx, dy ], tag)
  end

  def lead_up(point, net, tag)
    top = [ point[0], point[1] - STUB ]
    wire(point, top, "#{tag}/lead")
    label(top, net, [ 0, -1 ], "#{tag}/lead")
  end

  def wire(a, b, tag)
    @items << [ :wire, [ :pts, [ :xy, *a ], [ :xy, *b ] ], [ :stroke, [ :width, 0 ], [ :type, :default ] ],
                [ :uuid, Sheet.uid("wire/#{tag}") ] ]
  end

  def junction(point, tag)
    @items << [ :junction, [ :at, *point ], [ :diameter, 0 ], [ :color, 0, 0, 0, 0 ], [ :uuid, Sheet.uid("junction/#{tag}") ] ]
  end

  def label(point, net, dir, tag)
    angle, justify = LABEL.fetch(dir)
    if (shape = OFF_SHEET[net])
      return @items << [ :global_label, net, [ :shape, shape ], [ :at, *point, angle ], [ :fields_autoplaced, :yes ],
                         [ :effects, [ :font, [ :size, 1.27, 1.27 ] ], [ :justify, justify.first ] ], [ :uuid, Sheet.uid("glabel/#{tag}") ] ]
    end

    @items << [ :label, net, [ :at, *point, angle ], [ :effects, [ :font, [ :size, 1.27, 1.27 ] ], [ :justify, *justify ] ],
                [ :uuid, Sheet.uid("label/#{tag}") ] ]
  end

  # Символ землі дивиться НАЗОВНІ від піна: на бічному піні вниз він налазив би на сусідній пін.
  GROUND_ANGLE = { [ 0, 1 ] => 0, [ -1, 0 ] => 270, [ 1, 0 ] => 90, [ 0, -1 ] => 180 }.freeze

  def ground(point, tag, dir = [ 0, 1 ])
    @power += 1
    ref = format("#PWR%02d", @power)
    lib_id, = embed("power:GND", {})
    x, y = point
    @items << [ :symbol, [ :lib_id, lib_id ], [ :at, x, y, GROUND_ANGLE.fetch(dir) ], [ :unit, 1 ], [ :exclude_from_sim, :no ], [ :in_bom, :no ],
                [ :on_board, :yes ], [ :dnp, :no ], [ :uuid, Sheet.uid("gnd/#{tag}") ],
                prop("Reference", ref, x, y + 5.08), prop("Value", GROUND, x, y + 3.81, shown: dir == [ 0, 1 ]),
                prop("Footprint", "", x, y), prop("Datasheet", "", x, y), prop("Description", "", x, y),
                [ :pin, "1", [ :uuid, Sheet.uid("gndpin/#{tag}") ] ],
                [ :instances, [ :project, NAME, [ :path, "/#{ROOT}", [ :reference, ref ], [ :unit, 1 ] ] ] ] ]
  end
end

# ── Плечі дільників — з канону ────────────────────────────────────────────────────────────────────
def dividers
  rows = parse_canon_table(File.read(CANON_DOC))
  abort "FAIL: §5 дав #{rows.size} рядків, очікувано #{CANON_ROWS_EXPECTED}" unless rows.size == CANON_ROWS_EXPECTED
  pick = ->(re) { rows.find { |r| r[:label] =~ re } || abort("FAIL: у §5 немає рядка #{re.source}") }
  mppt = pick.call(/MPPT/)
  ov = pick.call(/Overvoltage/)
  off = pick.call(/OK OFF/)
  on = pick.call(/OK ON/)
  out = pick.call(/Buck/)
  arms = { "ROC1" => mppt[:r1], "ROC2" => mppt[:r2], "ROV1" => ov[:r1], "ROV2" => ov[:r2], "ROK1" => off[:r1],
           "ROK2" => off[:r2], "ROK3" => on[:r3], "ROUT1" => out[:r1], "ROUT2" => out[:r2] }
  arms.each { |k, v| abort "FAIL: плече #{k} не витяглось із §5" unless v }
  arms
end

def ohms(megohm) = megohm >= 1 ? "#{Sexp.num(megohm)}M" : "#{Sexp.num(megohm * 1000)}k"

# ── Сам силовий дек ───────────────────────────────────────────────────────────────────────────────
def build
  s = Sheet.new
  bom = ->(pos) { "docs/02_01 §3.1 поз. #{pos}" }
  open_vbat = "⚖️ відкрито: 100 мкФ АБО перемичка на VSTOR — docs/00_07 HW.9"
  pos10 = bom.call(10)

  # Позначення великого корпусу — над ним, праворуч від верхніх пінів, а не поверх назв пінів.
  s.place("Battery_Management:BQ25570", "U1", "BQ25570", at: [ 190.5, 114.3 ], bom: bom.call(2), sim: false, tag_at: [ 7.62, -21.59 ],
          note: "SPICE-моделі немає — docs/02_01 §7", patch: { "18" => :bidirectional, "14" => :power_out },
          nets: { "1" => GROUND, "2" => "VIN_DC", "3" => "VOC_SAMP", "4" => "VREF_SAMP", "5" => GROUND,
                  "6" => "VBAT_OK", "7" => "VBAT_OV", "8" => "VRDIV", "9" => GROUND, "10" => "OK_HYST",
                  "11" => "OK_PROG", "12" => "VOUT_SET", "13" => "VBAT_OK", "14" => "VOUT", "15" => GROUND,
                  "16" => "LBUCK", "17" => GROUND, "18" => "VBAT", "19" => "VSTOR", "20" => "LBOOST", "21" => GROUND })

  # Джерело й прапорці живлення: EBFC зовнішній, тож VIN_DC і GND мусять мати оголошеного «водія».
  s.place("Connector_Generic:Conn_01x02", "J1", "EBFC (pogo)", at: [ 76.2, 50.8 ], bom: bom.call(7), sim: false,
          nets: { "1" => "VIN_DC", "2" => GROUND })
  s.place("power:PWR_FLAG", "#FLG01", "PWR_FLAG", at: [ 76.2, 76.2 ], in_bom: false, sim: false, nets: { "1" => GROUND })
  s.place("power:PWR_FLAG", "#FLG02", "PWR_FLAG", at: [ 88.9, 76.2 ], in_bom: false, sim: false, nets: { "1" => "VIN_DC" })

  # Ряд живлення: вхід · boost · опорний вузол MPPT · шина VSTOR · VBAT (відкрито) · buck.
  two = ->(ref, lib, value, x, a, b, **kw) { s.place("Device:#{lib}", ref, value, at: [ x, 50.8 ], nets: { "1" => a, "2" => b }, **kw) }
  two.call("C1", "C_Small", "4.7u", 101.6, "VIN_DC", GROUND, bom: pos10, note: "C_IN ≥ 4.7 мкФ (SLUSBH2G); P/N не обрано")
  two.call("L1", "L_Small", "22u", 114.3, "VIN_DC", "LBOOST", bom: bom.call(15))
  two.call("C2", "C_Small", "10n", 127.0, "VREF_SAMP", GROUND, bom: pos10, note: "CREF 9–11 нФ, малий витік (SLUSBH2G)")
  s.rail([ [ "C3", "C_Small", "4.7u", { bom: pos10, note: "C_STOR ≥ 4.7 мкФ (SLUSBH2G)" } ],
           [ "C4", "C_Small", "100n", { bom: pos10, note: "C_STOR 0.1 мкФ паралельно (SLUSBH2G)" } ],
           [ "C5", "C_Polarized_Small", "470mF", { bom: bom.call(3), note: "EDLC на VSTOR — docs/02_03 §2" } ] ],
         "VSTOR", x: 139.7, y: 50.8)
  s.place("Jumper:SolderJumper_2_Open", "JP1", "VBAT—VSTOR", at: [ 190.5, 50.8 ], dnp: true, sim: false, note: open_vbat,
          nets: { "1" => "VBAT", "2" => "VSTOR" })
  two.call("C6", "C_Small", "100u", 215.9, "VBAT", GROUND, dnp: true, sim: false, note: open_vbat)
  two.call("L2", "L_Small", "10u", 228.6, "LBUCK", "VOUT", bom: bom.call(15))
  two.call("C7", "C_Small", "47u", 241.3, "VOUT", GROUND, bom: bom.call(9))

  # Дільники — сходинками; номінали з канону, верх — VRDIV (MPPT — VIN_DC, §4.А).
  arms = dividers
  arm = ->(*refs) { refs.map { |r| [ r, ohms(arms.fetch(r)) ] } }
  r_opts = { bom: pos10, note: "1 % E96 · номінал із docs/02_03 §5" }
  s.divider(arm.call("ROV2", "ROV1"), [ "VRDIV", "VBAT_OV", GROUND ], x: 101.6, y: 165.1, **r_opts)
  s.divider(arm.call("ROK3", "ROK2", "ROK1"), [ "VRDIV", "OK_HYST", "OK_PROG", GROUND ], x: 127.0, y: 165.1, **r_opts)
  s.divider(arm.call("ROUT2", "ROUT1"), [ "VRDIV", "VOUT_SET", GROUND ], x: 152.4, y: 165.1, **r_opts)
  s.divider(arm.call("ROC2", "ROC1"), [ "VIN_DC", "VOC_SAMP", GROUND ], x: 177.8, y: 165.1, **r_opts)

  # Кламп VSTOR поз. 14 — топологія Ш-N (docs/02_03 §4.Б): supervisor стежить за власним VDD = VSTOR і над
  # порогом відкриває NMOS-шунт через R_dump. P/N і номінали — рекомендація шортлиста, не присуд (HW.12).
  pos14 = bom.call(14)
  candidate = "кандидат — P/N рекомендація, не присуд; деталь судить стенд docs/00_07 HW.12"
  s.place("#{OWN_LIB}:TLV840N_PL", "U2", "TLV840NAPL50 (кандидат)", at: [ 279.4, 101.6 ], bom: pos14, sim: false,
          note: candidate, tag_at: [ -7.62, -8.89 ],
          nets: { "1" => "CLAMP_GATE", "2" => "VSTOR", "3" => GROUND, "4" => GROUND, "5" => GROUND })
  s.divider([ [ "RGPD1", "10M" ] ], [ "CLAMP_GATE", GROUND ], x: 317.5, y: 116.84, bom: pos14,
            note: "pull-down затвора: нижче VPOR 0.7 В вихід TLV840 не визначено, а VGS(th) min ключа 0.4 В")
  s.shunt([ "RDUMP1", "22k", { bom: pos14, note: "R_dump — рекомендація шортлиста ovp_clamp_shortlist §5, не присуд" } ],
          [ "#{OWN_LIB}:DMN2990UFA", "Q1", "DMN2990UFA (кандидат)",
            { bom: pos14, sim: false, note: "#{candidate} · номери пінів — землі tools/pcb/hw12_dmn2990ufa_breakout", tag_at: [ 6.35, -1.27 ] } ],
          top: "VSTOR", mid: "CLAMP_DRAIN", gate: "CLAMP_GATE", x: 355.6, y: 93.98)

  # Ключ Vcap-sense поз. 23 (docs/02_01 §3.1): VIN і VBIAS — від VSTOR, ON — GPIO, дільник — на окремий ADC-пін.
  # ON тримає pull-down (⚖️ founder 2026-11-08, врізка docs/02_01 §3.1): GPIO MCU буває tri-state — після reset (крім
  # JTAG-пінів, тож ON не на них) і без живлення в brownout, — а ключ на VSTOR живий; чи ON справді спливає, не зміряно
  # (найслабша ланка там же); 1 МΩ — з витоку ION і GPIO (≤ 0.2 В під VIL), не за аналогією.
  s.place("#{OWN_LIB}:TPS22860", "U3", "TPS22860", at: [ 279.4, 165.1 ], bom: bom.call(23), sim: false,
          note: "ON тримає RPD1 — docs/02_01 §3.1 (⚖️ founder 2026-11-08)", tag_at: [ -7.62, -8.89 ],
          nets: { "1" => "VCAP_SW", "2" => GROUND, "3" => :nc, "4" => "VSTOR", "5" => "VSTOR", "6" => "VCAP_SENSE_EN" })
  s.divider([ [ "RPD1", "1M" ] ], [ "VCAP_SENSE_EN", GROUND ], x: 241.3, y: 182.88, bom: pos10,
            note: "pull-down ON: ION ≤ 100 нА × 1 МΩ ≤ 0.1 В під VIL (SLVSD04) — docs/02_01 §3.1")
  s.divider([ [ "RSNS1", "не обрано" ], [ "RSNS2", "не обрано" ] ], [ "VCAP_SW", "VCAP_ADC", GROUND ], x: 317.5, y: 167.64,
            bom: pos10, sim: false, note: "тевенін ≤ 50 кОм; номінали — розводка разом із docs/00_07 FW.50", tag_at: [ -12.7, -1.27 ])

  s.text("v2 — BQ25570 і обвʼязка · кламп поз. 14 (P/N — кандидати HW.12) · ключ Vcap-sense поз. 23.", 25.4, 228.6)
  s.text("Номінали дільників BQ25570 читаються з docs/02_03 §5; зʼєднання звіряються з нетлістом KiCad.", 25.4, 233.68)
  s.text("VBAT: 100 мкФ АБО перемичка на VSTOR — відкрито (HW.9), обидві деталі DNP.", 25.4, 238.76)
  s.text("VCAP_SENSE_EN і VCAP_ADC — до MCU, пін-мапа — .ioc (FW.46); ON ключа тримає pull-down RPD1 (⚖️ 2026-11-08).", 25.4, 243.84)
  s
end

# Таблиця бібліотек — ПРОЄКТНА, через змінні, які KiCad визначає сам (на Mac і в Docker однаково):
# глобальна таблиця користувача тут не суддя — вона буває зламаною (запис зі шляхом translocation-у).
def lib_table(sheet)
  rows = sheet.stock.uniq.sort.map { |l| [ :lib, [ :name, l ], [ :type, "KiCad" ], [ :uri, "${KICAD10_SYMBOL_DIR}/#{l}.kicad_sym" ], [ :options, "" ], [ :descr, "" ] ] }
  rows << [ :lib, [ :name, OWN_LIB ], [ :type, "KiCad" ], [ :uri, "${KIPRJMOD}/silkennet.kicad_sym" ], [ :options, "" ],
            [ :descr, "HW.56 — символи, звірені з паспортами" ] ]
  [ :sym_lib_table, [ :version, 7 ], *rows ]
end

def own_library(sheet)
  version = Lib.tree("Battery_Management").find { |e| e.is_a?(Array) && Sexp.head(e) == "version" }
  [ :kicad_symbol_lib, version, [ :generator, "silkennet_hw56" ], [ :generator_version, "10.0" ],
    *sheet.own.map { |name, sym| sym.dup.tap { |s| s[1] = name } } ]
end

def write_project(dir)
  FileUtils.mkdir_p(dir)
  sheet = build
  File.write(File.join(dir, "#{NAME}.kicad_sch"), "#{Sexp.dump(sheet.document)}\n")
  File.write(File.join(dir, "silkennet.kicad_sym"), "#{Sexp.dump(own_library(sheet))}\n")
  File.write(File.join(dir, "sym-lib-table"), "#{Sexp.dump(lib_table(sheet))}\n")
  # `.kicad_pro` генерується ЗАВЖДИ й судиться `--check`: у ньому живуть рівні строгості ERC, тож одне
  # збереження з GUI, що поставить правило в ignore, інакше заглушило б ERC непомітно.
  File.write(File.join(dir, "#{NAME}.kicad_pro"), "#{JSON.pretty_generate(meta: { filename: "#{NAME}.kicad_pro", version: 1 })}\n")
end

def cli(*args)
  out, status = Open3.capture2e(KICAD_CLI, *args)
  [ out, status.exitstatus ]
end

# Звірка з’єднань: кожен пін деталі мусить лежати в ЗАДУМАНІЙ мережі нетліста, який експортує сам KiCad.
def netlist_problems(net_file, intended)
  actual = {}
  Sexp.child(Sexp.parse(File.read(net_file)).first, "nets").then { |nets| Sexp.children(nets, "net") }.each do |net|
    name = Sexp.child(net, "name")[1].sub(%r{\A/}, "")
    Sexp.children(net, "node").each { |n| actual[[ Sexp.child(n, "ref")[1], Sexp.child(n, "pin")[1] ]] = name }
  end
  actual.reject! { |(ref, _), _| ref.start_with?("#") }
  ok = ->(pin, want) { want == :nc ? actual[pin].nil? || actual[pin].start_with?("unconnected-") : actual[pin] == want }
  wrong = intended.filter_map { |pin, want| "#{pin.join('.')}: задумано #{want}, у KiCad #{actual[pin].inspect}" unless ok.call(pin, want) }
  extra = (actual.keys - intended.keys).map { |pin| "#{pin.join('.')}: у KiCad є (#{actual[pin]}), у задуманому немає" }
  wrong + extra
end

def verify(dir)
  sch = File.join(dir, "#{NAME}.kicad_sch")
  out_dir = File.join(HERE, "out")
  FileUtils.mkdir_p(out_dir)
  erc = File.join(out_dir, "erc.json")
  log, code = cli("sch", "erc", "--format", "json", "--severity-all", "--exit-code-violations", "-o", erc, sch)
  violations = File.exist?(erc) ? JSON.parse(File.read(erc)).fetch("sheets", []).flat_map { |sh| sh.fetch("violations", []) } : []
  violations.each { |v| warn "ERC  #{v['severity']}  #{v['type']}: #{v['description']}" }
  warn log unless code.zero? || !violations.empty?
  _, pdf = cli("sch", "export", "pdf", "-o", File.join(out_dir, "#{NAME}.pdf"), sch)
  _, spice = cli("sch", "export", "netlist", "--format", "spice", "-o", File.join(out_dir, "#{NAME}.cir"), sch)
  net_file = File.join(out_dir, "#{NAME}.net")
  _, nl = cli("sch", "export", "netlist", "--format", "kicadsexpr", "-o", net_file, sch)
  wiring = nl.zero? ? netlist_problems(net_file, build.intended) : [ "нетліст KiCad не експортувався" ]
  wiring.each { |w| warn "FAIL  зʼєднання — #{w}" }
  cir = File.join(out_dir, "#{NAME}.cir")
  # Будь-який токен-значення з голим F (у SPICE — фемто): `0.47F` · `4.7e-1F` · `0.47Farad`, не лише останній.
  femto_value = /\A[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?f(arad)?\z/i
  femto = File.exist?(cir) ? File.read(cir).lines.select { |l| l.split.drop(3).any? { |t| t.match?(femto_value) } } : [ "нетліст не записано" ]
  femto.each { |l| warn "FAIL  SPICE читає голе F як фемто: #{l.strip}" }
  puts "ERC: #{violations.size} порушень (exit #{code}) · звірка зʼєднань: #{wiring.size} розбіжностей · " \
       "PDF exit #{pdf} · SPICE exit #{spice} → #{out_dir.sub("#{Dir.pwd}/", '')}"
  code.zero? && pdf.zero? && spice.zero? && wiring.empty? && femto.empty?
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.first == "--check"
    Dir.mktmpdir do |tmp|
      write_project(tmp)
      stale = [ "#{NAME}.kicad_sch", "#{NAME}.kicad_pro", "silkennet.kicad_sym", "sym-lib-table" ].reject do |f|
        File.exist?(File.join(HERE, f)) && File.read(File.join(HERE, f)) == File.read(File.join(tmp, f))
      end
      stale.each { |f| warn "FAIL  #{f} відстає від генератора — перегенеруй без --check" }
      exit((verify(HERE) && stale.empty?) ? 0 : 1)
    end
  else
    write_project(HERE)
    exit(verify(HERE) ? 0 : 1)
  end
end
