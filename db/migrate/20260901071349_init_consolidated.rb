# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = =====================================================================
# 🌱 INIT CONSOLIDATED — single squashed migration
# = =====================================================================
# This is the SQUASH ANCHOR. Everything that existed before it lives in
# `db/structure.sql`, since the project has no production database to preserve
# (pre-launch). ⚠️ This header once claimed to be the only migration here, and
# that sentence stood while four incrementals sat on top of it — a self-location
# claim is falsified by an edit in ANOTHER file, so it reads fresher the longer
# it stands. Hence no claim about the population is made here at all: count with
# `ls db/migrate/`, and read the live anchor timestamp off the filename.
#
# Workflow for new clones:
#   bin/rails db:create db:schema:load db:seed
#
# Workflow for *adding* new migrations later:
#   bin/rails g migration AddXxx ...
#   bin/rails db:migrate
#   bin/rails db:schema:dump   # refreshes db/structure.sql
#
# Workflow for *another squash* later (post-launch — only if no prod):
#   1. `bin/rails db:schema:dump` to make sure structure.sql is current.
#   2. Delete every migration file *except this one*.
#   3. Rename this file's timestamp to a fresh one (e.g. now()).
#   4. 🔴 Скинути `schema_migrations` У БАЗІ (dev І test), не у файлі:
#        DELETE FROM schema_migrations;
#        INSERT INTO schema_migrations (version) VALUES ('<новий timestamp>');
#      і аж тоді повторити `db:schema:dump`.
#      ⚠️ Формулювання «replace the INSERT block in structure.sql» стояло тут із
#      народження й було МАРНИМ ЗА ПОБУДОВОЮ: `db:schema:dump` генерує цей блок
#      із БАЗИ, тож будь-яка правка файлу відкочується наступним же дампом.
#      Ціна не гіпотетична — сквош 2026-08-15 виконали за старим приписом, і до
#      2026-08-24 блок ніс **22 версії при 10 файлах**, включно з ПОПЕРЕДНІМ
#      анкером. Шкоди не сталось (на `schema:load` Rails просто вважає ті
#      міграції виконаними, а файлів для них немає), але сам факт був невидимий:
#      єдиний, хто на нього дивиться, — цей крок, і він вказував не туди.
#   ⊕ Кроку 5 БІЛЬШЕ НЕМАЄ [OPS.24]. Він звучав «bump StrongMigrations.start_after»
#     і був єдиним МОВЧАЗНИМ кроком процедури: значення нижче за живий анкер знімає
#     перевірки з уже застосованих міграцій, і ніщо не червоніє. Тепер
#     `config/initializers/strong_migrations.rb` виводить його з імені ЦЬОГО файлу,
#     тож переносити нема чого — і перенести неправильно неможливо.
#     ⚠️ Дзеркальний наслідок: кроки 3 і 4 стали ще несучішими — перейменування
#     файлу тепер рухає і `start_after`, тож воно мусить іти в ОДНОМУ коміті з
#     переписаним блоком `schema_migrations`.
#
# Нагадування, що борг накопичився, друкує сам `db:migrate`
# (`lib/tasks/migration_hygiene.rake`, поріг — присуд founder-а).
#
# Data seeding (system_parameters, organizations, oracle_executioner, ...)
# lives in db/seeds.rb and is invoked by `bin/rails db:seed`. Do NOT add
# data INSERTs to migrations — they belong in seeds or rake tasks
# (see lib/tasks/) so a fresh structure.sql never carries data.
class InitConsolidated < ActiveRecord::Migration[8.1]
  def up
    # Schema loaded from db/structure.sql via `bin/rails db:schema:load`.
    # `db:setup` runs schema:load then seed automatically; nothing to do
    # in code-form — this migration exists only as the schema_migrations
    # version anchor.
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
