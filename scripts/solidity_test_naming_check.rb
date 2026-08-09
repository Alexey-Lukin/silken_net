#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# TEST.14 · Foundry naming-вісь: revert-тест мусить називатись `testRevert_*`.
#
# РЕЧЕННЯ, ЯКЕ ГЕЙТ ЕНФОРСИТЬ (одне, без «and» — §Guard-craft #46):
#   функція у contracts/test/**.t.sol, чиє ТІЛО містить expectRevert/expectPartialRevert
#   і яка названа `test_*`, мусить називатись `testRevert_*`.
#
# ЧОМУ ЦЕ НЕ КОСМЕТИКА: ім'я тесту — єдине, що читає людина в CI-звіті. `test_foo`, який
# насправді стереже реверт, читається як happy-path, тож його зникнення з переліку падінь
# нічого нікому не каже. Дзеркально: `testRevert_` дає `--match-test "testRevert_"` як
# робочий зріз усієї revert-поверхні.
#
# СТЕЛІ (називаємо явно — гейт без оголошеної стелі перетворює зелене на «не перевірено»):
#   1. Парсер — брейс-лічильник, не Solidity-AST. Він бачить функції верхнього рівня в
#      контракті; вкладені визначення (яких у Solidity немає) поза моделлю за побудовою.
#   2. Коментарі вирізаються ДО перевірки тіла (`//` та `/* */`), інакше проза про
#      expectRevert червонить сумлінний happy-path-тест. Рядкові літерали НЕ вирізаються:
#      `expectRevert` усередині рядка в цьому дереві не трапляється, а вирізання додало б
#      парсеру стану без жодного улову.
#   3. Гейт мовчить про НЕ-`test_` номенклатури (`testFuzz_`, `check_`, `property_`,
#      `invariant_`, хелпери). Це свідомо: fuzz/symbolic/property-функція має власну
#      конвенцію CLAUDE.md §8, і revert усередині неї легітимний. Сьогодні таких із
#      expectRevert нуль — тобто виняток порожній, але він структурний, не історичний.
#   4. Улов на момент відвантаження — НУЛЬ (усі 22 порушники вирівняні тим самим пакетом).
#      Це батарея, не worklist: вона пінить інваріант, який дерево вже тримає.

require "pathname"

ROOT = Pathname.new(__dir__).parent
TEST_GLOB = ROOT.join("contracts", "test", "**", "*.t.sol")
REVERT_CALLS = /\b(?:expectRevert|expectPartialRevert)\b/
# Номенклатури, що мають ВЛАСНУ конвенцію — гейт до них не адресується (стеля 3).
FOREIGN_PREFIXES = %w[testFuzz_ testRevert_ check_ property_ invariant_].freeze

# Вирізає коментарі, зберігаючи кількість рядків (щоб номер рядка лишався правдивим).
def strip_comments(src)
  out = src.gsub(%r{/\*.*?\*/}m) { |block| "\n" * block.count("\n") }
  out.gsub(%r{//[^\n]*}, "")
end

# Функції верхнього рівня: [ім'я, рядок оголошення, тіло без коментарів].
def each_function(src)
  lines = strip_comments(src).lines
  name = nil
  start = nil
  depth = 0
  body = []

  lines.each_with_index do |line, idx|
    if name.nil?
      next unless (m = line.match(/^\s*function\s+([A-Za-z0-9_$]+)\s*\(/))

      name = m[1]
      start = idx + 1
      body = [ line ]
      depth = line.count("{") - line.count("}")
      # Оголошення без відкритої дужки (interface/abstract) — не тіло.
      name = nil if line.include?("{") && depth <= 0
    else
      body << line
      depth += line.count("{") - line.count("}")
      next unless depth <= 0

      yield(name, start, body.join)
      name = nil
      body = []
    end
  end
end

files = Dir.glob(TEST_GLOB.to_s).sort
violations = []
scanned_revert_fns = 0

files.each do |path|
  src = File.read(path, encoding: "utf-8")
  rel = Pathname.new(path).relative_path_from(ROOT)

  each_function(src) do |name, line, body|
    next unless body.match?(REVERT_CALLS)

    scanned_revert_fns += 1
    next if FOREIGN_PREFIXES.any? { |p| name.start_with?(p) }
    next unless name.start_with?("test_")

    violations << "#{rel}:#{line} — #{name} стереже реверт, але названий як happy-path"
  end
end

# ─── Ліхтарі на ВЛАСНИЙ вимір ────────────────────────────────────────────────
# Порожня множина зелена назавжди — тож обидва інваріанти перевіряємо явно.
# Це НЕ лічильники, що ростуть: обидва питають «чи периметр узагалі живий».
if files.empty?
  warn "::error::solidity_test_naming: глоб #{TEST_GLOB} не знайшов жодного .t.sol — периметр сліпий"
  exit 1
end

if scanned_revert_fns.zero?
  warn "::error::solidity_test_naming: у #{files.size} файлах НУЛЬ функцій з expectRevert — " \
       "парсер зламався (revert-тести в цьому дереві існують завжди)"
  exit 1
end

unless violations.empty?
  warn "::error::solidity_test_naming: revert-тест із happy-path-іменем:"
  violations.each { |v| warn "  #{v}" }
  warn "Перейменуй на testRevert_* (CLAUDE.md §8). ⚠️ Ім'я ключує contracts/.gas-snapshot, " \
       "тож перейменування вимагає forge snapshot --no-match-test \"invariant_|testFuzz_\" тим самим комітом."
  exit 1
end

puts "OK — #{scanned_revert_fns} revert-функцій у #{files.size} файлах, усі названі за конвенцією"
