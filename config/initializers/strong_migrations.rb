# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Strong Migrations — захист від небезпечних міграцій у продакшні.
# При масштабуванні до мільярдів записів (телеметрія, транзакції, дерева)
# навіть "проста" ALTER TABLE може заблокувати таблицю на десятки хвилин.
#
# `start_after` = найсвіжіший squash-anchor: усе до нього вже влито в
# `db/structure.sql`, тож перевіряти там нема чого.
#
# 🔴 ВИВОДИТЬСЯ З ІМЕНІ ФАЙЛУ, а не хардкодиться — і це не стиль, а зняття
# найтихішого кроку re-squash-процедури [OPS.24]. Доти крок 5 («bump
# `StrongMigrations.start_after`») вимагав, щоб людина перенесла timestamp
# руками, а помилка там МОВЧАЗНА: значення НИЖЧЕ за живий анкер знімає
# перевірки з уже застосованих міграцій, і ніщо не червоніє. Ціна була не
# гіпотетичною — `06_01` двічі ніс попередній анкер саме в тому кроці, а
# коментар ЦЬОГО файлу — теж (два рядки над правильним числом). Виведене
# значення не має де розійтись: джерело те саме, що й для `db:migrate`.
#
# ⚠️ Порожній глоб = зламаний checkout (міграції їдуть в образ через `COPY . .`),
# тож падаємо ГУЧНО замість тихого дефолту — мовчазний нуль тут читався б як
# «перевірки вимкнено», а це протилежне тому, чого хоче цей файл.
squash_anchor = Dir[Rails.root.join("db/migrate/*_init_consolidated.rb")].max
raise "StrongMigrations: squash-анкер `db/migrate/*_init_consolidated.rb` не знайдено — " \
      "checkout неповний, а мовчазний fallback приховав би це" if squash_anchor.nil?

StrongMigrations.start_after = File.basename(squash_anchor)[/\A\d+/].to_i

# Час очікування lock-у на таблицю перед відміною міграції.
# 10 секунд — безпечний ліміт для IoT uplink pipeline (телеметрія не чекатиме довше).
StrongMigrations.lock_timeout = 10.seconds

# Час виконання одного SQL statement.
# 1 година — для масивних backfill на мільярдах рядків (blockchain_transactions, telemetry_logs).
StrongMigrations.statement_timeout = 1.hour

# Мажор, проти якого StrongMigrations судить безпечність операції.
# 🔴 Мусить дорівнювати ПРОДОВОМУ (`terraform/database.tf` = POSTGRES_17), інакше
# гейт судить код на іншому движку, ніж той, що виконає його в проді — рівно той
# клас, який [OPS.27] закрив для CI-контейнерів, і той самий, що доти був тут:
# стояло 16 при 17 у dev, у CI та в terraform. Помилка м'яка в один бік
# (заниження = зайва обережність) і НЕ м'яка в інший, тож паритет тримаємо явно.
StrongMigrations.target_version = 17
