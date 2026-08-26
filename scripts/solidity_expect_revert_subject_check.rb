#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# DOC-T.89 · Foundry expectRevert-вісь: реверт-очікування мусить називати ПРЕДМЕТ.
#
# РЕЧЕННЯ, ЯКЕ ГЕЙТ ЕНФОРСИТЬ (одне, без «and» — §Guard-craft #46):
#   виклик `expectRevert()` з ПОРОЖНІМ списком аргументів у contracts/test/**.t.sol
#   заборонений; предмет називають рядком, селектором або `expectPartialRevert`.
#
# ЧОМУ ЦЕ НЕ КОСМЕТИКА — і чому саме тут. Голий `expectRevert()` проходить при реверті
# з БУДЬ-ЯКОЇ причини, а наші revert-тести майже всі стережуть `AccessControl`/`Pausable`.
# Отже регресія, що зламає `onlyRole(MINTER_ROLE)` так, що реверт лишиться (наприклад
# арифметика падає раніше по шляху), пройде ЗЕЛЕНОЮ на тесті, названому саме за цю
# властивість. Money-path тут не абстракція: `mint()`/`slash()` гейтовані рівно ролями.
#
# ЧОМУ ГЕЙТ, А НЕ РЕВʼЮ. `CLAUDE.md §8` доти казав «гейта на цю вісь нема — її тримає
# ревʼю, бо голий виклик неможливо відрізнити від легітимного "будь-який реверт"
# статично». Перша половина твердження була про НАМІР і правдива; друга — про ФОРМУ, і
# вона хибна: порожній список аргументів статично видно точно. Ратчет не судить наміру,
# він вимагає, щоб намір «будь-який реверт» був ОГОЛОШЕНИЙ (`expectPartialRevert`
# із селектором — саме та форма, яку канон уже приписує для непередбачуваного аргументу).
#
# СТЕЛІ (називаємо явно — гейт без оголошеної стелі перетворює зелене на «не перевірено»):
#   1. Гейт судить НАЯВНІСТЬ предмета, ніколи його ПРАВИЛЬНІСТЬ. `expectRevert("не той
#      рядок")` він пропустить — цю вісь тримає ревʼю, і вона справді не має форми.
#   2. Парсер — регекс над джерелом із вирізаними коментарями, не Solidity-AST. Рядкові
#      літерали НЕ вирізаються: `expectRevert()` усередині рядка в цьому дереві не
#      трапляється, а вирізання додало б стану без жодного улову (та сама межа, що в
#      сусіда `solidity_test_naming_check.rb`).
#   3. Багаторядкова форма покрита: `\s` матчить переводи рядка, тож `expectRevert(\n)`
#      ловиться, а `expectRevert(\n  abi.encodeWithSelector(...)\n)` — ні, і це правильно.
#   4. Улов на момент відвантаження — НУЛЬ (25 ретрофітнуто 2026-08-09, TEST.14). Це
#      РАТЧЕТ, а не worklist: живість доведено мутацією, не популяцією (§Guard-craft #61).

require "pathname"

ROOT      = Pathname.new(__dir__).parent
TEST_GLOB = ROOT.join("contracts", "test", "**", "*.t.sol")

# Голий виклик: між дужками нічого, крім пробілів/переводів рядка.
BARE_CALL = /\bexpectRevert\s*\(\s*\)/
# Будь-яке реверт-очікування — для ліхтаря «парсер живий».
ANY_CALL  = /\b(?:expectRevert|expectPartialRevert)\s*\(/

# Вирізає коментарі, зберігаючи кількість рядків (щоб номер рядка лишався правдивим).
def strip_comments(src)
  out = src.gsub(%r{/\*.*?\*/}m) { |block| "\n" * block.count("\n") }
  out.gsub(%r{//[^\n]*}, "")
end

files      = Dir.glob(TEST_GLOB.to_s).sort
violations = []
scanned    = 0

files.each do |path|
  stripped = strip_comments(File.read(path, encoding: "utf-8"))
  rel      = Pathname.new(path).relative_path_from(ROOT)

  scanned += stripped.scan(ANY_CALL).size

  stripped.to_enum(:scan, BARE_CALL).each do
    line_no = stripped[0...Regexp.last_match.begin(0)].count("\n") + 1
    violations << "#{rel}:#{line_no} — голий expectRevert() не називає предмета"
  end
end

# ─── Ліхтарі на ВЛАСНИЙ вимір ────────────────────────────────────────────────
# Порожня множина зелена назавжди — тож обидва інваріанти перевіряємо явно.
if files.empty?
  warn "::error::solidity_expect_revert_subject: глоб #{TEST_GLOB} не знайшов жодного .t.sol — периметр сліпий"
  exit 1
end

if scanned.zero?
  warn "::error::solidity_expect_revert_subject: у #{files.size} файлах НУЛЬ реверт-очікувань — " \
       "парсер зламався (revert-тести в цьому дереві існують завжди)"
  exit 1
end

unless violations.empty?
  warn "::error::solidity_expect_revert_subject: реверт-очікування без предмета:"
  violations.each { |v| warn "  #{v}" }
  warn "Назви предмет (CLAUDE.md §8). Ідіом залежить від ДЖЕРЕЛА реверту: наш " \
       "`require(cond, \"рядок\")` → vm.expectRevert(\"exact error string\"); OZ 5.7 кидає " \
       "custom errors → vm.expectRevert(abi.encodeWithSelector(IAccessControl.\
AccessControlUnauthorizedAccount.selector, actor, role)); непередбачуваний аргумент → " \
       "vm.expectPartialRevert(selector)."
  exit 1
end

puts "OK — #{scanned} реверт-очікувань у #{files.size} файлах, усі називають предмет"
