#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =============================================================================
# 🏛️ ONCHAIN ROLE REGISTRY SYNC  [ARCH.112]
# =============================================================================
# Речення, яке цей гейт застосовує:
#
#   КОЖНА роль, що існує в нашій on-chain системі, мусить мати рядок у реєстрі
#   стоячих повноважень `05_03 §Стоячі повноваження після деплою` — і той рядок
#   мусить називати, чи вона СКЛАДАЄТЬСЯ на якійсь події.
#
# ЧОМУ (клас, а не випадок). Ролі роздають окремими комітами, а перелік того, що
# складається, пишуть ОДИН раз — тож він старіє тільки в бік НЕПОВНОТИ, і нічим
# не червоніє. Виміряно на собі 2026-08-27: `EXECUTOR_ROLE` не існував у каноні
# ЗОВСІМ (відкритий екзекутор, тобто повноваження, яке має весь світ), а
# `CANCELLER_ROLE` був у контрактах і випав із renounce-переліку `SEC.1` —
# постійне вето над рішеннями DAO, лишене не присудом, а пропуском.
#
# ⛔ ЧОМУ НЕ `grantRole`. Очевидна форма — «шукати виклики `grantRole`» — сліпа
# рівно на тій ролі, що купила цей гейт: `EXECUTOR_ROLE` не грантиться викликом
# узагалі, він приходить масивом `executors` у конструкторі `TimelockController`.
# Тому вісь тут — САМІ КОНСТАНТИ РОЛЕЙ, які існують незалежно від способу видачі.
#
# 🔎 ДИСКРИМІНАТОР (структурний, без carve-out-реєстру). Токен `X_ROLE` є роллю
# СИСТЕМИ, якщо вона його ОГОЛОШУЄ (`keccak256("X_ROLE")`) або ВІДДАЄ гетером
# (`.X_ROLE()`). Локальний хендл у гарнесі (`bytes32 internal immutable
# ADMIN_ROLE = scc.DEFAULT_ADMIN_ROLE()`) не має жодної з двох форм і відпадає
# сам. Периметр виміряно вичерпно перед написанням: 10 кандидатів → 9 ролей + 1
# псевдонім, тобто нуль хибних позитивів після дискримінатора.
#
# 📏 ОГОЛОШЕНА СТЕЛЯ — читай як перелік того, чого цей гейт НЕ бачить:
#   · він судить НАЯВНІСТЬ рядка й НЕПОРОЖНІСТЬ вироку, ніколи ПРАВИЛЬНІСТЬ
#     вироку — «складається на події X» із хибним X проходить зеленим;
#   · він не знає, чи роль справді ВИДАЄТЬСЯ на деплої (роль, оголошена в
#     контракті й нікому не надана, теж вимагає рядка — і це свідомо: право,
#     яке існує й нікому не належить, однаково є частиною постави);
#   · ролі, успадковані від залежності й ніде в нашому дереві не згадані,
#     невидимі за побудовою — вони не мають у нас жодної форми, за яку взятись.
#
# Прогін:  ruby scripts/onchain_role_registry_sync.rb
# Exit:    0 — реєстр повний · 1 — роль без рядка або рядок без вироку
# =============================================================================

ROOT = File.expand_path("..", __dir__)
CANON = File.join(ROOT, "docs", "05_03_Tokenomics_SCC_and_SFC.md")
SECTION_ANCHOR = "Стоячі повноваження станом на деплой-день"

SOLIDITY_GLOBS = [
  File.join(ROOT, "contracts", "*.sol"),
  File.join(ROOT, "contracts", "script", "*.sol"),
  File.join(ROOT, "contracts", "test", "**", "*.sol")
].freeze

# Роль, яку система ОГОЛОШУЄ, або яку вона ВІДДАЄ гетером.
DECLARED  = /keccak256\(\s*"([A-Z][A-Z0-9_]*_ROLE)"\s*\)/
GETTER    = /\.\s*([A-Z][A-Z0-9_]*_ROLE)\s*\(\s*\)/

def system_roles
  roles = Hash.new { |h, k| h[k] = [] }
  SOLIDITY_GLOBS.flat_map { |g| Dir.glob(g) }.sort.each do |path|
    text = File.read(path)
    rel = path.sub("#{ROOT}/", "")
    [ DECLARED, GETTER ].each do |re|
      text.scan(re) { |(name)| roles[name] << rel }
    end
  end
  roles.transform_values(&:uniq)
end

# Рядки таблиці реєстру: від заголовка секції до наступного `## `/`### `.
def registry_rows
  unless File.exist?(CANON)
    warn "onchain_role_registry_sync ✗ — канон-файл не знайдено: #{CANON}"
    exit 1
  end
  lines = File.readlines(CANON)
  start = lines.index { |l| l.start_with?("#") && l.include?(SECTION_ANCHOR) }
  if start.nil?
    warn "onchain_role_registry_sync ✗ — секцію «#{SECTION_ANCHOR}» не знайдено в 05_03"
    warn "  (переїхала або перейменована — це і є те, що гейт мусить помітити)"
    exit 1
  end

  rows = []
  lines[(start + 1)..].each do |line|
    break if line.start_with?("## ") || line.start_with?("### ")
    next unless line.lstrip.start_with?("|")

    cells = line.strip.sub(/\A\|/, "").sub(/\|\z/, "").split("|").map(&:strip)
    next if cells.size < 4                      # не 4-колонковий рядок
    next if cells.all? { |c| c.match?(/\A:?-+:?\z/) } # роздільник
    next if cells.first.include?("Повноваження")      # шапка
    rows << cells
  end
  rows
end

roles = system_roles
rows = registry_rows

if rows.empty?
  warn "onchain_role_registry_sync ✗ — таблиця реєстру порожня (перевір розмітку секції)"
  exit 1
end

missing = []
verdictless = []

roles.each_key do |role|
  row = rows.find { |cells| cells[0].include?(role) }
  if row.nil?
    missing << role
    next
  end
  fate = row[3].to_s.gsub(/[[:space:]]/, "")
  verdictless << role if fate.empty? || fate == "—" || fate == "-"
end

if missing.empty? && verdictless.empty?
  puts "onchain_role_registry_sync ✓ — #{roles.size} on-chain ролей, у кожної рядок із вироком " \
       "про складання (05_03 §#{SECTION_ANCHOR})"
  exit 0
end

warn "onchain_role_registry_sync ✗ — реєстр стоячих повноважень неповний [ARCH.112]"
missing.each do |role|
  warn "  ✗ #{role}: немає рядка в реєстрі — оголошено/вживано в #{roles[role].join(', ')}"
end
verdictless.each do |role|
  warn "  ✗ #{role}: рядок є, але колонка «складається на події?» порожня — " \
       "право без названого терміну повернення є майном, не довіреним"
end
warn ""
warn "  Дім реєстру: docs/05_03_Tokenomics_SCC_and_SFC.md §#{SECTION_ANCHOR}"
warn "  Присуд про термін guardian-вето й підстава — там же; трекер — 00_07 ARCH.112."
exit 1
