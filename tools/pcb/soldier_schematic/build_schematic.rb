#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [HW.56] Схема силового деку Солдата — генератор. Пише `soldier_power.kicad_sch` (+ мінімальний
# `.kicad_pro`): людина відкриває його в KiCad 10 (редактор схем — з вікна KiCad), агент перевіряє
# без вікна — ERC за кодом виходу, рендер PDF, SPICE-нетліст із тієї самої схеми. Рішення й межа —
# `docs/02_01 §7`; робота — `docs/00_07` HW.56. ⛔ Схему руками не правити: правка — тут, файл
# перегенеровується, а `--check` червоніє, якщо закомічена схема відстала від генератора.
#
#   ruby tools/pcb/soldier_schematic/build_schematic.rb          # згенерувати + ERC + PDF + SPICE у out/
#   ruby tools/pcb/soldier_schematic/build_schematic.rb --check  # те саме, і червоніє на застарілій схемі
#
# Звідки кожне число (одна річ — один дім):
#   • плечі дільників BQ25570 — таблиця `02_03 §5`, прочитана тим самим `parse_canon_table`, яким
#     `tools/firmware/bq25570_dividers.rb --check-canon` судить канон: схема з каноном розійтися не може;
#   • символи — стандартні бібліотеки KiCad 10, вбудовані в схему копією;
#   • P/N у схему НЕ копіюються: поле «BOM» кожної деталі — вказівник на `02_01 §3.1` поз. N.
#
# Розпіновку BQ25570 звірено з таблицею пінів SLUSBH2G (березень 2019). Дві правки вбудованої копії
# символу — за паспортом, не за бібліотекою, бо інакше ERC червонів би на правильній схемі:
#   • `VBAT` (18): бібліотека — `power_in`, паспорт — I/O (чип веде його зсередини від VSTOR);
#   • `VOUT` (14): бібліотека — `input`, паспорт — O (вихід buck).
# Піни 9 і 17 у паспорті — NC «на землю через PowerPAD»; бібліотека зве їх VSS і складає з 1, 15 і 21
# в одну точку — схема тягне цю точку на GND, як велить паспорт.
#
# Вузли трирезисторного стеку VBAT_OK — з рівнянь паспорта: Eq. 4 (поріг на зростанні) = VBIAS·(1 +
# (ROK2 + ROK3)/ROK1) — вузол над ROK1 при повному стеку; Eq. 3 (на спаданні) = VBIAS·(1 + ROK2/ROK1) —
# той самий вузол при закороченому ROK3. Тож `OK_PROG` — між ROK1 і ROK2, `OK_HYST` — між ROK2 і ROK3,
# ROK3 — до VRDIV. Верхнє плече MPPT (ROC2) — на VIN_DC, не на VRDIV: присуд `02_03 §4.А`.
#
# ⛔ ОГОЛОШЕНІ СТЕЛІ — читай як перелік того, чого цей файл НЕ доводить:
#   • v0 — лише BQ25570 і його обвʼязка; кламп поз. 14 і ключ поз. 23 — наступні кроки HW.56.
#   • Номінали L і C живуть тут і в BOM `02_01 §3.1` — звіряються очима, гейта між ними немає.
#   • ⛔ Фаради пиши через масштаб (`470mF`), ніколи голим `F`: у SPICE `F` у будь-якому регістрі — ФЕМТО, і
#     KiCad при експорті його не перекладає (`M` → `Meg` перекладає), тож `0.47F` іоністора ngspice прочитав
#     би як 0.47 фФ. `verify` валить прогін на такому значенні в нетлісті.
#   • Відкрите в каноні лишається відкритим і тут: `VBAT` — 100 мкФ АБО перемичка на VSTOR (`00_07` HW.9),
#     тож обидві деталі стоять DNP, жодну не обрано.
#   • U1 виключено із симуляції — вендорської моделі BQ25570 немає (`02_01 §7`); SPICE-нетліст пасивних
#     симуляцією тракту НЕ є.
#   • Розміщення — сітка, а зʼєднання — мітками на кінцях пінів: це читається як нетліст, не як
#     намальована схема; ERC судить зʼєднання, а не читабельність.

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
OWN_LIB = "SilkenNet"

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

    Marshal.load(Marshal.dump(sym))
  end

  def pins(sym)
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

# ── Аркуш ─────────────────────────────────────────────────────────────────────────────────────────
class Sheet
  ROOT = "0a1b2c3d-4e5f-5a6b-8c7d-9e0f1a2b3c4d"
  # Пін дивиться ВІД точки зʼєднання ДО тіла символу; заглушка йде у протилежний бік.
  OUTWARD = { 0 => [ -1, 0 ], 180 => [ 1, 0 ], 90 => [ 0, 1 ], 270 => [ 0, -1 ] }.freeze
  LABEL = { [ -1, 0 ] => [ 180, %i[right bottom] ], [ 1, 0 ] => [ 0, %i[left bottom] ],
            [ 0, 1 ] => [ 270, %i[right bottom] ], [ 0, -1 ] => [ 90, %i[left bottom] ] }.freeze

  attr_reader :own, :stock

  def initialize
    @lib = {}
    @own = {}
    @stock = []
    @items = []
    @points = {}
  end

  def self.uid(key)
    h = Digest::SHA1.hexdigest("silkennet/HW.56/#{NAME}/#{key}")
    "#{h[0, 8]}-#{h[8, 4]}-5#{h[13, 3]}-#{((h[16, 2].to_i(16) & 0x3f) | 0x80).to_s(16)}#{h[18, 2]}-#{h[20, 12]}"
  end

  # Кожен пін символу мусить отримати мережу ЯВНО (`:nc` — теж явно): пропущений пін — помилка
  # генератора, а не тихий обрив, який ERC міг би й не назвати.
  def place(lib_id, ref, value, at:, nets:, bom: nil, note: nil, dnp: false, sim: true, in_bom: true, patch: {})
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
             prop("Reference", ref, x + 2.54, y - 1.27, shown: !ref.start_with?("#")),
             prop("Value", value, x + 2.54, y + 1.27, shown: true),
             prop("Footprint", "", x, y), prop("Datasheet", "", x, y), prop("Description", "", x, y) ]
    node << prop("BOM", bom, x, y) if bom
    node << prop("Примітка", note, x, y) if note
    numbers.each { |n| node << [ :pin, n, [ :uuid, Sheet.uid("pin/#{ref}/#{n}") ] ] }
    node << [ :instances, [ :project, NAME, [ :path, "/#{ROOT}", [ :reference, ref ], [ :unit, 1 ] ] ] ]
    @items << node
    pins.each { |p| connect(ref, p, x, y, nets.fetch(p[:number])) }
  end

  def text(str, x, y)
    @items << [ :text, str, [ :exclude_from_sim, :yes ], [ :at, x, y, 0 ],
                [ :effects, [ :font, [ :size, 1.27, 1.27 ] ], [ :justify, :left, :bottom ] ], [ :uuid, Sheet.uid("text/#{x}/#{y}") ] ]
  end

  def document
    [ :kicad_sch, [ :version, 20260306 ], [ :generator, "silkennet_hw56" ], [ :generator_version, "10.0" ],
      [ :uuid, ROOT ], [ :paper, "A3" ],
      [ :title_block, [ :title, "SilkenNet — Солдат, силовий дек (v0)" ], [ :company, "SilkenNet" ],
        [ :comment, 1, "Згенеровано tools/pcb/soldier_schematic/build_schematic.rb — руками не правити" ],
        [ :comment, 2, "Плечі дільників — docs/02_03 §5 через bq25570_dividers.rb · P/N — docs/02_01 §3.1" ] ],
      [ :lib_symbols, *@lib.values ], *@items, [ :sheet_instances, [ :path, "/", [ :page, "1" ] ] ] ]
  end

  private

  # Символ, виправлений за паспортом, перестає бути символом KiCad: він їде у власну бібліотеку
  # `SilkenNet` (файл `silkennet.kicad_sym` поруч), і схема посилається вже на неї — тоді вбудована
  # копія збігається зі своєю бібліотекою, а ERC не скаржиться на розбіжність, якої ми припустились свідомо.
  def embed(lib_id, patch)
    lib, name = lib_id.split(":", 2)
    target = patch.empty? ? lib_id : "#{OWN_LIB}:#{name}"
    sym = @lib[target] ||= begin
      s = Lib.symbol(lib, name)
      patch.each do |number, type|
        pin = Lib.pins(s).find { |p| p[:number] == number } || raise("#{lib_id}: піна #{number} немає")
        pin[:node][1] = Sexp::Atom.new(type.to_s)
      end
      @own[name] = Marshal.load(Marshal.dump(s)) unless patch.empty?
      @stock << lib if patch.empty?
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
    ex = px + (dx * STUB)
    ey = py + (dy * STUB)
    angle, justify = LABEL.fetch([ dx, dy ])
    @items << [ :wire, [ :pts, [ :xy, px, py ], [ :xy, ex, ey ] ], [ :stroke, [ :width, 0 ], [ :type, :default ] ],
                [ :uuid, Sheet.uid("wire/#{tag}") ] ]
    @items << [ :label, net, [ :at, ex, ey, angle ], [ :effects, [ :font, [ :size, 1.27, 1.27 ] ], [ :justify, *justify ] ],
                [ :uuid, Sheet.uid("label/#{tag}") ] ]
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

  s.place("Battery_Management:BQ25570", "U1", "BQ25570", at: [ 190.5, 114.3 ], bom: bom.call(2), sim: false,
          note: "SPICE-моделі немає — docs/02_01 §7", patch: { "18" => :bidirectional, "14" => :power_out },
          nets: { "1" => "GND", "2" => "VIN_DC", "3" => "VOC_SAMP", "4" => "VREF_SAMP", "5" => "GND",
                  "6" => "VBAT_OK", "7" => "VBAT_OV", "8" => "VRDIV", "9" => "GND", "10" => "OK_HYST",
                  "11" => "OK_PROG", "12" => "VOUT_SET", "13" => "VBAT_OK", "14" => "VOUT", "15" => "GND",
                  "16" => "LBUCK", "17" => "GND", "18" => "VBAT", "19" => "VSTOR", "20" => "LBOOST", "21" => "GND" })

  # Джерело й прапорці живлення: EBFC зовнішній, тож VIN_DC і GND мусять мати оголошеного «водія».
  s.place("Connector_Generic:Conn_01x02", "J1", "EBFC (pogo)", at: [ 76.2, 50.8 ], bom: bom.call(7), sim: false,
          nets: { "1" => "VIN_DC", "2" => "GND" })
  s.place("power:PWR_FLAG", "#FLG01", "PWR_FLAG", at: [ 76.2, 76.2 ], in_bom: false, sim: false, nets: { "1" => "GND" })
  s.place("power:PWR_FLAG", "#FLG02", "PWR_FLAG", at: [ 88.9, 76.2 ], in_bom: false, sim: false, nets: { "1" => "VIN_DC" })

  # Ряд живлення: вхід · boost · опорний вузол MPPT · накопичувач · buck.
  two = ->(ref, lib, value, x, a, b, **kw) { s.place("Device:#{lib}", ref, value, at: [ x, 50.8 ], nets: { "1" => a, "2" => b }, **kw) }
  two.call("C1", "C_Small", "4.7u", 101.6, "VIN_DC", "GND", bom: bom.call(10), note: "C_IN ≥ 4.7 мкФ (SLUSBH2G); P/N не обрано")
  two.call("L1", "L_Small", "22u", 114.3, "VIN_DC", "LBOOST", bom: bom.call(15))
  two.call("C2", "C_Small", "10n", 127.0, "VREF_SAMP", "GND", bom: bom.call(10), note: "CREF 9–11 нФ, малий витік (SLUSBH2G)")
  two.call("C3", "C_Small", "4.7u", 139.7, "VSTOR", "GND", bom: bom.call(10), note: "C_STOR ≥ 4.7 мкФ (SLUSBH2G)")
  two.call("C4", "C_Small", "100n", 152.4, "VSTOR", "GND", bom: bom.call(10), note: "C_STOR 0.1 мкФ паралельно (SLUSBH2G)")
  two.call("C5", "C_Polarized_Small", "470mF", 165.1, "VSTOR", "GND", bom: bom.call(3), note: "EDLC на VSTOR — docs/02_03 §2")
  s.place("Jumper:SolderJumper_2_Open", "JP1", "VBAT—VSTOR", at: [ 203.2, 50.8 ], dnp: true, sim: false, note: open_vbat,
          nets: { "1" => "VBAT", "2" => "VSTOR" })
  two.call("C6", "C_Small", "100u", 228.6, "VBAT", "GND", dnp: true, note: open_vbat)
  two.call("L2", "L_Small", "10u", 241.3, "LBUCK", "VOUT", bom: bom.call(15))
  two.call("C7", "C_Small", "47u", 254.0, "VOUT", "GND", bom: bom.call(9))

  # Ряд дільників: номінали — з канону, верх кожного — до VRDIV (ROC2 — до VIN_DC, §4.А).
  arms = dividers
  [ [ "ROV2", "VRDIV", "VBAT_OV" ], [ "ROV1", "VBAT_OV", "GND" ],
    [ "ROK3", "VRDIV", "OK_HYST" ], [ "ROK2", "OK_HYST", "OK_PROG" ], [ "ROK1", "OK_PROG", "GND" ],
    [ "ROUT2", "VRDIV", "VOUT_SET" ], [ "ROUT1", "VOUT_SET", "GND" ],
    [ "ROC2", "VIN_DC", "VOC_SAMP" ], [ "ROC1", "VOC_SAMP", "GND" ] ].each_with_index do |(ref, top, bottom), i|
    s.place("Device:R_Small", ref, ohms(arms.fetch(ref)), at: [ 101.6 + (12.7 * i), 177.8 ], bom: bom.call(10),
            note: "1 % E96 · номінал із docs/02_03 §5", nets: { "1" => top, "2" => bottom })
  end

  s.text("v0 — BQ25570 і обвʼязка. Кламп поз. 14 і ключ поз. 23 — наступні кроки docs/00_07 HW.56.", 25.4, 228.6)
  s.text("Зʼєднання — мітками на кінцях пінів; номінали дільників читаються з docs/02_03 §5.", 25.4, 233.68)
  s.text("VBAT: 100 мкФ АБО перемичка на VSTOR — відкрито (HW.9), обидві деталі DNP.", 25.4, 238.76)
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
  pro = File.join(dir, "#{NAME}.kicad_pro")
  File.write(pro, "#{JSON.pretty_generate(meta: { filename: "#{NAME}.kicad_pro", version: 1 })}\n") unless File.exist?(pro)
end

def cli(*args)
  out, status = Open3.capture2e(KICAD_CLI, *args)
  [ out, status.exitstatus ]
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
  femto = File.read(File.join(out_dir, "#{NAME}.cir")).lines.grep(/\s[\d.]+F\s*\z/i)
  femto.each { |l| warn "FAIL  SPICE читає голе F як фемто: #{l.strip}" }
  puts "ERC: #{violations.size} порушень (exit #{code}) · PDF exit #{pdf} · SPICE-нетліст exit #{spice} → #{out_dir.sub("#{Dir.pwd}/", '')}"
  code.zero? && pdf.zero? && spice.zero? && femto.empty?
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.first == "--check"
    Dir.mktmpdir do |tmp|
      write_project(tmp)
      stale = [ "#{NAME}.kicad_sch", "silkennet.kicad_sym", "sym-lib-table" ].reject do |f|
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
