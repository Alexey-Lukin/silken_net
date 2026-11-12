#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [HW.37 · HW.9] Попередній ескіз для складальника (селективна пайка / робот-паяльник):
# де стоять два THT-виводи іоністора на RF Deck і що їх оточує — НЕ розводка.
# Розводки ще немає (вона рухається одним пакетом кореня після осі 3 RF-макета, `00_07` HW.9),
# і саме відповідь складальника про вільне місце навколо виводів — її вхід (`02_01 §3.1` поз. 3).
# Тож ескіз малює лише те, що канон уже фіксує, а зону без SMD позначає «?».
#
#   ruby tools/pcb/edlc_tht_sketch/edlc_tht_sketch.rb OUT.svg
#   rsvg-convert -f pdf -o OUT.pdf OUT.svg   # і/або -f png -d 200 -p 200
#
# Числа й доми (дзеркала — правити в домі):
#   крок виводів 10.0 · отвір Ø1.10 · монета Ø11.5 · H 5.2      — `02_01 §3.1` поз. 3 (Eaton KR, «Effective June 2026»)
#   пад Ø2.30                                                   — `tools/firmware/board_area_budget.rb`, EDLC["kr"] (верх RF Deck)
#   зсув монети від центру плати ≈ 2.99 мм                      — та сама геометрія, що `geometric_floor` калькулятора
#                                                                 (монета й сокет B2B на низу RF Deck); відтворено формулою
#                                                                 нижче, позитивний контроль — підлога Ø18.6, як друкує калькулятор
#   плата Ø≈22 (21.87 — пакет кореня, сегмент лише на верху RF) — `02_01 §3.5` ⊕ «Пакет кореня» 2026-10-13
#   FR4 1.6                                                     — `02_01 §3.1` поз. 8
#   сусіди на боці пайки ≤ 1.1 мм; антена 2.4 мм                — `02_01 §3.1` поз. 19 (≤ 1.10) · поз. 17–18 · бустер NN02-224
# ⛔ Числа настанови SEHO (2 / 5 мм) свідомо НЕ малюються: лист їх не називає, щоб складальник дав своє
# (`docs/protocols/procurement/node_tht_soldering_rfq.md` §1, рядок «Процес Б»).

BOARD_D   = 21.87
PITCH     = 10.0
HOLE_D    = 1.10
PAD_D     = 2.30
COIN_D    = 11.5
COIN_H    = 5.2
FR4       = 1.6
SMD_H     = 1.1
ANT_H     = 2.4
EDGE_CU   = 0.3   # відступ міді від краю — `02_01 §3.5`, USABLE_EDGE_MM калькулятора
EDLC_HALF, EDLC_REACH = 6.0, 6.45        # EDLC_SHAPE["kr"] калькулятора
SOCKET_EXTENT = [ 5.20, 3.64 ].freeze    # SOCKET_EXTENT калькулятора (CLP з кортьярдом)

def coin_offset
  (0..6000).map do |i|
    s = i / 1000.0
    pts = [ [ -s - EDLC_HALF, 0.0 ], [ -s, EDLC_REACH ], [ -s + EDLC_HALF + SOCKET_EXTENT[0], SOCKET_EXTENT[1] ] ]
    [ pts.map { |x, y| Math.hypot(x, y) }.max, s ]
  end.min
end

floor_r, S = coin_offset
floor_d = (2 * floor_r) + (2 * EDGE_CU)
abort format("geometric floor Ø%.2f ≠ calculator Ø18.6 — formula drifted from board_area_budget.rb", floor_d) unless (floor_d - 18.6).abs < 0.06
EDGE_GAP = (BOARD_D / 2) - Math.hypot(S, PITCH / 2)

K = 18.0 # px per mm
def x(mm) = format("%.1f", mm * K)
def esc(s) = s.gsub("&", "&amp;").gsub("<", "&lt;")

out = ARGV.fetch(0) { abort "Usage: #{$PROGRAM_NAME} OUT.svg" }
cx, cy = 16.0, 17.0              # top view centre, mm
holes = [ [ cx - S, cy - (PITCH / 2) ], [ cx - S, cy + (PITCH / 2) ] ]
q_r = 3.6                         # radius of the «?» ring — arbitrary on purpose, see label

top = []
top << %(<circle cx="#{x(cx)}" cy="#{x(cy)}" r="#{x(BOARD_D / 2)}" fill="#eef3ea" stroke="#333" stroke-width="2"/>)
top << %(<circle cx="#{x(cx - S)}" cy="#{x(cy)}" r="#{x(COIN_D / 2)}" fill="none" stroke="#777" stroke-width="1.5" stroke-dasharray="6 4"/>)
holes.each do |hx, hy|
  top << %(<circle cx="#{x(hx)}" cy="#{x(hy)}" r="#{x(q_r)}" fill="#fff" stroke="#c0392b" stroke-width="1.5" stroke-dasharray="4 3"/>)
  top << %(<circle cx="#{x(hx)}" cy="#{x(hy)}" r="#{x(PAD_D / 2)}" fill="#d4a017" stroke="#8a6d00"/>)
  top << %(<circle cx="#{x(hx)}" cy="#{x(hy)}" r="#{x(HOLE_D / 2)}" fill="#fff" stroke="#555"/>)
  top << %(<text x="#{x(hx + q_r + 0.3)}" y="#{x(hy + 0.4)}" font-size="15" fill="#c0392b">R = ?</text>)
end
dim_x = cx - S - 4.2
top << %(<line x1="#{x(dim_x)}" y1="#{x(holes[0][1])}" x2="#{x(dim_x)}" y2="#{x(holes[1][1])}" stroke="#333" marker-start="url(#a)" marker-end="url(#a)"/>)
top << %(<text x="#{x(dim_x - 2.6)}" y="#{x(cy + 0.4)}" font-size="14">10,0 ± 0,3</text>)
top << %(<text x="#{x(cx + 1.0)}" y="#{x(cy - 2.5)}" font-size="13" fill="#2d5a27">SMD-компоненти,</text>)
top << %(<text x="#{x(cx + 1.0)}" y="#{x(cy - 1.5)}" font-size="13" fill="#2d5a27">висота ≤ 1,1 мм</text>)
top << %(<text x="#{x(cx + 1.0)}" y="#{x(cy - 0.5)}" font-size="13" fill="#2d5a27">(розміщення ще не визначено)</text>)

legend = [
  "ВИД ЗВЕРХУ — бік пайки виводів (верхній бік плати; SMD уже запаяні reflow)",
  format("Плата кругла, Ø ≈ 22 мм (розмір уточнюється); від центру отвору до краю ≈ %.1f мм", EDGE_GAP).sub(/(\d)\.(\d) мм/, '\1,\2 мм'),
  "Отвори Ø1,10 мм, пади Ø2,3 мм; два виводи на кроці 10,0 ± 0,3 мм",
  "Пунктир сірий — корпус іоністора Ø11,5 мм на ПРОТИЛЕЖНОМУ боці (H до 5,2 мм)",
  "Пунктир червоний — зона без SMD навколо виводу: R = ваше значення (на ескізі довільне)",
  "Антена (висота 2,4 мм) — не поруч із виводами; точне місце ще не визначено",
  "Попередній ескіз, не розводка: розміщення сусідів задасть саме ваша відповідь"
]

sx, sy = 40.0, 14.0               # section origin (board top-left), mm
sec = []
sec << %(<rect x="#{x(sx)}" y="#{x(sy)}" width="#{x(22.0)}" height="#{x(FR4)}" fill="#cfe0c3" stroke="#333"/>)
sec << %(<text x="#{x(sx + 22.4)}" y="#{x(sy + 1.2)}" font-size="13">FR4 1,6</text>)
coin_x = sx + 5.0
sec << %(<rect x="#{x(coin_x)}" y="#{x(sy + FR4 + 0.2)}" width="#{x(COIN_D)}" height="#{x(COIN_H - 0.2)}" rx="6" fill="#ddd" stroke="#555"/>)
sec << %(<text x="#{x(coin_x + 1.2)}" y="#{x(sy + FR4 + 3.2)}" font-size="13">іоністор, H ≤ 5,2</text>)
[ coin_x + 0.75, coin_x + COIN_D - 0.75 ].each do |lx|
  sec << %(<line x1="#{x(lx)}" y1="#{x(sy - 0.6)}" x2="#{x(lx)}" y2="#{x(sy + FR4 + 1.2)}" stroke="#8a6d00" stroke-width="3"/>)
  sec << %(<path d="M #{x(lx - 1.0)} #{x(sy)} Q #{x(lx)} #{x(sy - 1.2)} #{x(lx + 1.0)} #{x(sy)} Z" fill="#b0b0b0" stroke="#666"/>)
end
[ [ coin_x + 0.75 - 4.4, 1.6 ], [ coin_x + COIN_D - 0.75 + 2.8, 1.6 ] ].each do |bx, w|
  sec << %(<rect x="#{x(bx)}" y="#{x(sy - SMD_H)}" width="#{x(w)}" height="#{x(SMD_H)}" fill="#7fb069" stroke="#2d5a27"/>)
end
sec << %(<text x="#{x(coin_x + COIN_D - 0.75 + 4.6)}" y="#{x(sy - 0.3)}" font-size="12" fill="#2d5a27">SMD ≤ 1,1</text>)
gap_l, gap_r = coin_x + COIN_D - 0.75 + 1.0, coin_x + COIN_D - 0.75 + 2.8
sec << %(<line x1="#{x(gap_l)}" y1="#{x(sy - 1.5)}" x2="#{x(gap_r)}" y2="#{x(sy - 1.5)}" stroke="#c0392b" marker-start="url(#a)" marker-end="url(#a)"/>)
sec << %(<text x="#{x(gap_l + 0.2)}" y="#{x(sy - 1.9)}" font-size="13" fill="#c0392b">? мм</text>)
sec << %(<text x="#{x(sx)}" y="#{x(sy - 3.4)}" font-size="13">РОЗРІЗ (схематично): виводи паяються згори,</text>)
sec << %(<text x="#{x(sx)}" y="#{x(sy - 2.6)}" font-size="13">корпус — знизу; плата паяється окремо, до складання стеку</text>)

svg = <<~SVG
  <?xml version="1.0" encoding="UTF-8"?>
  <svg xmlns="http://www.w3.org/2000/svg" width="#{x(66)}" height="#{x(47)}" viewBox="0 0 #{x(66)} #{x(47)}" font-family="DejaVu Sans, Arial, sans-serif">
  <defs><marker id="a" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#333"/></marker></defs>
  <rect width="100%" height="100%" fill="#fff"/>
  <text x="#{x(1.5)}" y="#{x(2.6)}" font-size="20" font-weight="bold">Іоністор Eaton KR-5R5H474-R — розміщення двох виводів (попередній ескіз)</text>
  #{top.join("\n")}
  #{sec.join("\n")}
  #{legend.each_with_index.map { |t, i| %(<text x="#{x(1.5)}" y="#{x(36.5 + (i * 1.35))}" font-size="14">#{esc(t)}</text>) }.join("\n")}
  </svg>
SVG
File.write(out, svg)
puts format("wrote %s · coin offset %.3f mm · floor Ø%.2f (= calculator) · hole→edge %.2f mm on Ø%.2f", out, S, floor_d, EDGE_GAP, BOARD_D)
