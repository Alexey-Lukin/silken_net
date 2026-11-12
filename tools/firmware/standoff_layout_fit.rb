#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# Чи вміщається на низу RF Deck (і верху Power Deck під ним) розкладка, за якої стійки поз. 25 без гвинтів тримають проміжок біля пари B2B
# (`00_07` HW.29, 🤖-нога «умови й здійсненність», перевірки (1)–(2); розбір — `02_01 §3.1`, врізка поз. 25 ⊕ 2026-11-12).
#
#   ruby tools/firmware/standoff_layout_fit.rb             # дефолт під купол + цілі пакета кореня, обидва прочитання сегмента
#   ruby tools/firmware/standoff_layout_fit.rb 21.92 22.80 # власні контури
#   ruby tools/firmware/standoff_layout_fit.rb --assert    # контролі шукача + дзеркала
#
# Тіла низу RF Deck — ті самі, що в сумі калькулятора (`board_area_budget.rb`): диск EDLC KR із двома виводами, сокет CLP,
# торці двох стійок; на верху Power Deck — вилка FW під сокетом (та сама вісь) і пади стійок; THT-пади EDLC (наскрізні) —
# поза сегментом верху RF Deck за обох прочитань. Умова (1): центроїд валика прокладки кишені лежить у «стадіоні» торців (смуга діаметра торця вздовж
# відрізка між центрами). Умова (2): рівнодійна двох pogo-пінів — теж у стадіоні, за обох крайніх розподілів сили між пінами;
# зовнішній пін — на кільцевій площадці (`02_02 §6`), азимут і радіус вільні; отвори хвостовиків крізь Power Deck не налазять
# на пади pogo. BME280 (верх RF Deck) — поза сегментом бустера за обох прочитань; «наскрізний» додає сегмент як keep-out низу.
#
# Шукач — максимізація найменшого запасу (рестарти + локальне сходження, фіксований сід). Додатний запас — КОНСТРУКТИВНИЙ
# доказ (розкладка існує); відʼємний — «не знайдено», не доказ неможливості. `--assert`: Ø30 мусить поставити центроїд рівно
# на лінію стійок (запас = радіус торця), Ø14 — дати відʼємний запас; дзеркала значень звірено з калькулятором і кешами.
# ⛔ Стелі — усі тягнуть запас ВНИЗ: (а) з верху Power Deck — лише вилка й пади стійок: власні деталі сторони (і ті, що
# рівномірні цілі пакета переносять між сторонами) не розкладено, висоти під диском EDLC не судяться; (б) keep-out THT-падів EDLC під пайку розміру не має (лист VD MAIS, `00_07` HW.37); (в) розводка
# й переходи не моделюються — лише кортьярди; (г) кутова привʼязка плати до радома (кишеня над BME280) — поза цією моделлю.
# ⚠️ Умови (1)–(2) — НЕОБХІДНІ, не достатні: контакт між деками один, тож у рівновазі рівнодійні валика й pogo мусять ще й
# збігтися в плані, інакше стек хилиться як ціле — хвіст (4) тієї ж ноги, і цей інструмент його не судить.
require "json"
require_relative "board_area_budget"

GRAV = 9.80665
EDGE = USABLE_EDGE_MM
_, COIN_R, COIN_REACH = EDLC_SHAPE.fetch("kr")
TAB = [ COIN_REACH - COIN_R, 1.30 ].freeze                  # вивід за ободом: радіально × уздовж (рядок EDLC "kr")
SOCK_W = 2 * SOCKET_EXTENT[1]                               # кортьярд CLP уздовж
SOCK_H = SOCKET_EXTENT[0]                                   # кортьярд CLP поперек
SO_COURT_D = Math.sqrt(STANDOFFS.fetch("m2x8_stop")[1].fetch("RF Deck, низ") / 2 / (Math::PI / 4))
SO_COURT_R = SO_COURT_D / 2
SO_FACE_R = (SO_COURT_D - 0.5) / 2                          # торець корпусу = кортьярд − 2 × 0.25 (рядок STANDOFFS)
HOLE_R = 3.0 / 2        # хвостовик Ø2.8 крізь Power Deck ≈ внутрішній Ø3.0 кільцевого паду (`deck_standoff_shortlist` §3)
POGO_PAD_R = 2.5 / 2    # пад pogo на низу Power Deck Ø2.5 (`02_02 §6`)
R_O = [ 3.0, 7.0 ].freeze # зовнішній пін: ≥ 2.0 (PEEK-кільце Ø4.0) + наконечник + захоплення (`02_02 §6`) · нижче канавки O-кільця
BME_HALF = 1.5          # BME280 2.5 × 2.5 + кортьярд: півгабарит у бік сегмента
HDR_W, HDR_H = 6.85, 7.36 # кортьярд вилки FW (B2B[:header]): уздовж ряду × поперек — вісь та сама, що в сокета
PAD_R = 5.80 / 2        # кортьярд кільцевого паду стійки на верху Power Deck (рядок STANDOFFS)
THT_PITCH, THT_R = 10.0, 2.30 / 2 # отвори виводів EDLC на кроці 10.0, кільце Ø2.30 (EDLC "kr", верх RF Deck)

RADOME = JSON.parse(File.read(File.expand_path("../cad/cem/radome.json", __dir__)))
def cem(h, key)
  h.each do |k, v|
    return v if k == key
    found = v.is_a?(Hash) ? cem(v, key) : nil
    return found unless found.nil?
  end
  nil
end
# Центроїд валика: рамка (отвір + 2 стінки) на одному азимуті, зовнішній край — на pocket_outer_radius.
G_R = cem(RADOME, "pocket_outer_radius_mm") - ((cem(RADOME, "pocket_opening_depth_mm") + (2 * cem(RADOME, "pocket_wall_mm"))) / 2)
G = [ G_R, 0.0 ].freeze

# Пін 60 ± 20 г на середині ходу (`02_02 §2.2`); нижня межа звірена з кешем `87`. Крайній розподіл — один пін на мінімумі, другий на максимумі.
PIN_G = [ 40.0, 80.0 ].freeze
POGO = JSON.parse(File.read(File.expand_path("../in_silico/cache/mechanical/pogo_sway_transfer.json", __dir__)))
F_SPLIT = [ PIN_G[0] / PIN_G.sum, PIN_G[1] / PIN_G.sum ].freeze

def mirrors!
  raise "EDLC kr: дзеркало виводу розійшлося з калькулятором" unless (disc(2 * COIN_R) + (2 * rect(*TAB)) - EDLC.fetch("kr")[1]).abs < 1e-9
  raise "сокет CLP: дзеркало розійшлося з B2B[:socket]" unless (rect(SOCK_W, SOCK_H) - B2B.fetch(:socket)).abs < 1e-9
  raise "торець стійки ≠ Ø4.35 (`deck_standoff_shortlist` §3)" unless ((2 * SO_FACE_R) - 4.35).abs < 1e-9
  raise "вилка FW: дзеркало розійшлося з B2B[:header]" unless (rect(HDR_W, HDR_H) - B2B.fetch(:header)).abs < 1e-9
  raise "пад стійки: дзеркало розійшлося з STANDOFFS" unless ((2 * disc(2 * PAD_R)) - STANDOFFS.fetch("m2x8_stop")[1].fetch("Power Deck, верх")).abs < 1e-9
  raise "THT-пади EDLC: дзеркало розійшлося з калькулятором" unless ((2 * disc(2 * THT_R)) - EDLC.fetch("kr")[2]).abs < 1e-9
  raise "сила піна: дзеркало розійшлося з кешем 87" unless ((PIN_G[0] * 1e-3 * GRAV) - POGO.fetch("inputs").fetch("pin_force_min_N")).abs < 1e-5
  raise format("центроїд валика %.3f ≠ 6.66 — перечитай radome.json і врізку поз. 25", G_R) unless (G_R - 6.66).abs < 1e-9
end

def dot(a, b) = (a[0] * b[0]) + (a[1] * b[1])
def vsub(a, b) = [ a[0] - b[0], a[1] - b[1] ]
def vnorm(a) = Math.hypot(a[0], a[1])
def seg_dist(p, a, b)
  ab = vsub(b, a)
  t = (dot(vsub(p, a), ab) / [ dot(ab, ab), 1e-12 ].max).clamp(0.0, 1.0)
  vnorm(vsub(p, [ a[0] + (t * ab[0]), a[1] + (t * ab[1]) ]))
end
def line_dist(p, a, b)
  ab = vsub(b, a)
  l = vnorm(ab)
  l < 1e-9 ? vnorm(vsub(p, a)) : ((ab[0] * (p[1] - a[1])) - (ab[1] * (p[0] - a[0]))).abs / l
end
def corners(c, w, h, ang)
  ux = [ Math.cos(ang), Math.sin(ang) ]
  uy = [ -ux[1], ux[0] ]
  [ [ 1, 1 ], [ 1, -1 ], [ -1, -1 ], [ -1, 1 ] ].map do |sx, sy|
    [ c[0] + (sx * w / 2 * ux[0]) + (sy * h / 2 * uy[0]), c[1] + (sx * w / 2 * ux[1]) + (sy * h / 2 * uy[1]) ]
  end
end
def disc_rect_gap(p, r, c, w, h, ang)
  d = vsub(p, c)
  ux = [ Math.cos(ang), Math.sin(ang) ]
  uy = [ -ux[1], ux[0] ]
  lx = dot(d, ux).abs - (w / 2)
  ly = dot(d, uy).abs - (h / 2)
  Math.hypot([ lx, 0 ].max, [ ly, 0 ].max) + [ [ lx, ly ].max, 0 ].min - r
end
def sat_gap(pa, pb)
  [ pa, pb ].flat_map do |poly|
    poly.each_index.map do |i|
      e = vsub(poly[(i + 1) % 4], poly[i])
      l = vnorm(e)
      n = [ -e[1] / l, e[0] / l ]
      a = pa.map { |v| dot(v, n) }
      b = pb.map { |v| dot(v, n) }
      [ b.min - a.max, a.min - b.max ].max
    end
  end.max
end

# x = [ax ay bx by cx cy α sx sy β ψ r_o φ]: стійки A, B · центр і вісь EDLC · центр і кут сокета · азимут і радіус
# зовнішнього pogo-піна · азимут зовнішньої нормалі сегмента.
def margins(x, d, through)
  ru = (d / 2) - EDGE
  dc = -booster_chord(d) # відстань хорди від центру (калькулятор дає координату, відʼємну)
  a, b, c, sc = x[0, 2], x[2, 2], x[4, 2], x[7, 2]
  al, be = x[6], x[9]
  ro = x[11].clamp(*R_O)
  pd = [ Math.cos(x[10]), Math.sin(x[10]) ]
  u = [ Math.cos(x[12]), Math.sin(x[12]) ]
  ax = [ Math.cos(al), Math.sin(al) ]
  tab_c = [ 1, -1 ].map { |s| [ c[0] + (s * (COIN_R + (TAB[0] / 2)) * ax[0]), c[1] + (s * (COIN_R + (TAB[0] / 2)) * ax[1]) ] }
  tabs = tab_c.map { |tc| corners(tc, TAB[0], TAB[1], al) }
  sock = corners(sc, SOCK_W, SOCK_H, be)
  po = [ ro * pd[0], ro * pd[1] ]
  fit = [ ru - (vnorm(c) + COIN_R), sock.map { |v| ru - vnorm(v) }.min, disc_rect_gap(c, COIN_R, sc, SOCK_W, SOCK_H, be),
          vnorm(vsub(a, b)) - SO_COURT_D ]
  tabs.each { |t| fit << t.map { |v| ru - vnorm(v) }.min << sat_gap(t, sock) }
  [ a, b ].each do |s|
    fit << (ru - (vnorm(s) + SO_COURT_R)) << (vnorm(vsub(s, c)) - (SO_COURT_R + COIN_R)) << disc_rect_gap(s, SO_COURT_R, sc, SOCK_W, SOCK_H, be)
    tab_c.each { |tc| fit << disc_rect_gap(s, SO_COURT_R, tc, TAB[0], TAB[1], al) }
  end
  hdr = corners(sc, HDR_W, HDR_H, be)
  top = [ hdr.map { |v| ru - vnorm(v) }.min, vnorm(vsub(a, b)) - (2 * PAD_R) ]
  [ a, b ].each { |s| top << (ru - (vnorm(s) + PAD_R)) << disc_rect_gap(s, PAD_R, sc, HDR_W, HDR_H, be) }
  tht = [ 1, -1 ].map { |k| [ c[0] + (k * THT_PITCH / 2 * ax[0]), c[1] + (k * THT_PITCH / 2 * ax[1]) ] }
  m = { bodies: fit.min, power_top: top.min, bme: dc - (dot(G, u) + BME_HALF), tht: tht.map { |t| dc - (dot(t, u) + THT_R) }.min,
        G: SO_FACE_R - seg_dist(G, a, b),
        P: SO_FACE_R - F_SPLIT.map { |f| seg_dist([ f * po[0], f * po[1] ], a, b) }.max,
        holes: [ a, b ].flat_map { |s| [ vnorm(s), vnorm(vsub(s, po)) ] }.min - (HOLE_R + POGO_PAD_R) }
  if through
    reach = [ dot(c, u) + COIN_R, sock.map { |v| dot(v, u) }.max ] + tabs.map { |t| t.map { |v| dot(v, u) }.max } +
            [ a, b ].map { |s| dot(s, u) + SO_COURT_R }
    m[:segment] = dc - reach.max
  end
  [ m, line_dist(sc, a, b) ]
end

MODES = { bodies: %i[bodies power_top bme tht segment], conditions: %i[bodies power_top bme tht segment G P holes] }.freeze
def score(x, d, through, mode, pair_line)
  m, off = margins(x, d, through)
  s = m.slice(*MODES.fetch(mode)).values.min
  s = [ s, pair_line - off ].min if pair_line
  [ s, m, off ]
end

def search(d, through, mode, pair_line: nil, restarts: 150, steps: 1500, rng: Random.new(20_261_112))
  ru = (d / 2) - EDGE
  pt = lambda do
    r = ru * Math.sqrt(rng.rand)
    t = 2 * Math::PI * rng.rand
    [ r * Math.cos(t), r * Math.sin(t) ]
  end
  best = nil
  restarts.times do
    x = [ *pt.call, *pt.call, *pt.call, Math::PI * rng.rand, *pt.call, Math::PI * rng.rand, 2 * Math::PI * rng.rand,
          R_O[0] + ((R_O[1] - R_O[0]) * rng.rand), 2 * Math::PI * rng.rand ]
    cur = score(x, d, through, mode, pair_line)
    steps.times do |i|
      step = (2.0 * (1 - (i.to_f / steps))) + 0.02
      y = x.each_with_index.map { |v, k| v + ((rng.rand - 0.5) * step * ([ 6, 9, 10, 12 ].include?(k) ? 0.6 : 1.0)) }
      nxt = score(y, d, through, mode, pair_line)
      x, cur = y, nxt if nxt[0] > cur[0]
    end
    best = [ *cur, x ] if best.nil? || cur[0] > best[0]
  end
  best
end

mirrors!
if ARGV == [ "--assert" ]
  hi = search(30.0, false, :conditions) # робочий бюджет шукача: контроль судить той самий шукач, що таблиця
  lo = search(14.0, false, :conditions)
  unless (hi[1][:G] - SO_FACE_R).abs < 0.05 && hi[0] > 1.5
    raise format("позитивний контроль: Ø30 дав %+.2f (G %.3f), очікувано центроїд на лінії (%.3f)", hi[0], hi[1][:G], SO_FACE_R)
  end
  raise format("негативний контроль: Ø14 дав %+.2f, очікувано відʼємне", lo[0]) unless lo[0].negative?
  puts format("standoff_layout_fit: дзеркала й контролі тримають (Ø30 G %.3f · Ø14 %+.2f)", hi[1][:G], lo[0])
  exit
end

rows = if ARGV.empty?
         [ [ CEILING_MM, false ], [ CEILING_MM, true ],
           [ package_target(rigid_flex: false, through: false).first, false ], [ package_target(rigid_flex: false, through: true).first, true ] ]
else
         ARGV.map(&:to_f).flat_map { |d| [ [ d, false ], [ d, true ] ] }
end
puts "Здійсненність умов (1)–(2) розбору стійок поз. 25 — низ RF Deck і верх Power Deck (HW.29) — найменший запас, мм; + = розкладку знайдено"
puts format("  центроїд валика r %.2f · торець Ø%.2f · кортьярд Ø%.2f · EDLC Ø%.1f · сокет %.2f × %.2f · розподіл pogo %.2f / %.2f",
            G_R, 2 * SO_FACE_R, SO_COURT_D, 2 * COIN_R, SOCK_W, SOCK_H, *F_SPLIT)
rows.each do |d, through|
  b = search(d, through, :bodies)
  c = search(d, through, :conditions)
  p = search(d, through, :conditions, pair_line: 1.0)
  puts format("  Ø%.2f %-24s лише тіла %+.2f · з умовами %+.2f (G %+.2f · P %+.2f · верх Power Deck %+.2f) · + пара ≤ 1.0 мм від лінії стійок %+.2f",
              d, through ? "наскрізний сегмент" : "сегмент лише на верху", b[0], c[0], c[1][:G], c[1][:P], c[1][:power_top], p[0])
end
