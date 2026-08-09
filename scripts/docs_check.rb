#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/docs_check.rb — швидкий, Rails-free запуск SSOT-гейтів.
#
# Ганяє ДВА кроки джоби `docs_check` (`docs:check_refs` + `tracker:check`) тими
# самими rake-тілами, що й CI, але БЕЗ
# завантаження Rails: завантажує файли rake-тасок напряму й викликає їх. Engine-и
# (`lib/docs_*.rb`, `lib/tracker/dashboard.rb`) — чистий Ruby (лише `require "set"`,
# stdlib), тож скрипт не потребує ні `bundle`, ні БД, ні гемів окрім `rake` (default
# gem Ruby). ~0.3 с проти ~1.2 с у `bin/rails docs:check_refs`; придатний для
# pre-commit-хука або контриб'ютора, який править прозу без Rails-середовища.
#
# Нуль дублювання оркестрації — reuse-ить ТІ САМІ тіла rake-тасок (джерело істини
# CI), тож не може розійтися з `bin/rails docs:check_refs`.
#
# Usage:
#   ruby scripts/docs_check.rb            # обидва гейти (check_refs + tracker:check)
#   ruby scripts/docs_check.rb refs       # лише docs:check_refs
#   ruby scripts/docs_check.rb tracker    # лише tracker:check
#
# Exit ≠ 0, якщо будь-який гейт упав (кожна rake-таска `abort`-ить при порушенні).
# ПРИМІТКА: це READ-ONLY перевірка. Регенерація ToC — окремо `bin/rails docs:toc`.
#

require "rake"
extend Rake::DSL

root = File.expand_path("..", __dir__)
load File.join(root, "lib", "tasks", "docs.rake")
load File.join(root, "lib", "tasks", "tracker.rake")

tasks =
  case ARGV[0]
  when "refs"     then %w[docs:check_refs]
  when "tracker"  then %w[tracker:check]
  when nil, "all" then %w[docs:check_refs tracker:check]
  else abort "usage: ruby scripts/docs_check.rb [refs|tracker|all]"
  end

# Кожна таска `abort`-ить (SystemExit) при порушенні; ловимо, щоб ОБИДВА гейти
# відзвітували, і повертаємо ненульовий код, якщо хоч один упав.
overall = 0
tasks.each do |t|
  Rake::Task[t].invoke
rescue SystemExit => e
  overall = 1 unless e.success?
end

# OPS.25 — гейт називає ВЛАСНИЙ клас, а не мовчить про нього. Цей скрипт ганяє
# ДВА кроки джоби `docs_check`; читати його зелене як вердикт про смугу `CI · Docs`
# — це та підміна виміру, що клала `main` тричі. Свідомо БЕЗ числа: лічильник
# кроків росте (`00_06 §1` no-volatile-counts), а джерело істини — сам workflow,
# який читає `docs_band.rb`.
warn "\n(це 2 кроки джоби `docs_check` — не вся смуга `CI · Docs`; повна: ruby scripts/docs_band.rb)"

exit overall
