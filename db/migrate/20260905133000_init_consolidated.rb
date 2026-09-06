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
# 🔴 СКВОШ 2026-09-05 склав У СЕБЕ одну річ, якої немає в жодній міграції, і це
# записано ТУТ, бо `structure.sql` не пояснює власних мінус-рядків: у складеній
# схемі БІЛЬШЕ НЕМАЄ `clusters.entropy_score`. Колонку знято разом із трактом
# `entropy_anomaly` (E.64, `05_05 §8.1`): детектор тлумачив розкид Z по кластеру як
# «гомогенізація = лісовий стрес», а розкид породжений per-device `K_seed`, які ми
# ПРИЗНАЧИЛИ, — виміряно N=200/R=500, H = 0.9077 на лісі БЕЗ біологічної різниці.
# ⚠️ Знято не міграцією, а ALTER-ом у dev перед дампом — і сам гейт дампу правий,
# що це виглядає як дрейф: двокроковий `ignored_columns`-танець мав СЕНС лише проти
# rolling-деплою з даними, а сквош базу зносить і сіє наново, тож підстава відпала.
# ⛔ Наступний, хто побачить у git-історії зникнення колонки без міграції, читає ЦЕЙ
# абзац: провенанс тут, не в `git log -S`.
#
# ⊕ ДРУГИЙ такий мінус-рядок, тією ж формою і з тієї ж підстави: у схемі більше
# немає `users.telegram_chat_id`. Канал Telegram зрізано ⚖️ founder 2026-09-06
# [ARCH.60] — не через дефект, а через ціну: колонка персональних даних, супровід
# у трьох юр-документах (`b2c_tos_privacy` · `dpia_art35` · `ropa_art30`), вендор
# без processor-DPA і відкрите питання «процесор чи контролер». Живий вимір на
# canopy того дня: бот працював (`configured?` = true, канал доступний) при нулі
# непорожніх `chat_id`. Тобто труба стояла відкритою і не мала до кого говорити
# — а чи пройшло нею щось раніше, приладу вже немає (юр-формулювання й назва
# відсутнього свідка — `b2c_tos_privacy §D.3`). Прецедент форми — зняття SMS разом із
# `users.phone_number` [ARCH.78, 2026-08-20]; головний урок того зрізу — сліди
# лишаються в доках, тож цього разу код, локалі, специ й юр-корпус ішли ОДНИМ
# проходом. ⚠️ Знято так само ALTER-ом у dev перед дампом, з тієї ж причини.
#
# Workflow for new clones (dev/test):
#   bin/rails db:create db:schema:load
#   bin/rails runner 'PartitionMaintenanceWorker.new.perform'   # ← МІЖ, не після
#   bin/rails db:seed
# 🔴 Порядок несучий, і `db:setup`/`db:prepare` його порушують ЗА ПОБУДОВОЮ: вони
# склеюють schema:load із seed, не лишаючи місця прогнати воркер між ними. `db/seeds.rb`
# датує «мовчунку» 73.hours.ago, тож 1-3 числа рядок цілить у ПОПЕРЕДНІЙ місяць — а
# `db/structure.sql` несе лише той календар, що існував на момент дампу. Якщо місяця в
# ньому немає, рядок тихо осідає в `_default` і НАЗАВЖДИ блокує партицію того місяця
# (`PG::CheckViolation`; рунбук `06_06 §5.5`). На `production` сід узагалі не їде —
# `db/seeds.rb` fail-closed за слотом (`00_07` OPS.38 веде склад bootstrap).
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
    # ⚠️ `db:setup` НЕ використовувати — воно склеює schema:load із seed (див. шапку).
    # Ця міграція існує лише як version-анкер schema_migrations; коду тут немає.
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
