# frozen_string_literal: true

# Strong Migrations — захист від небезпечних міграцій у продакшні.
# При масштабуванні до мільярдів записів (телеметрія, транзакції, дерева)
# навіть "проста" ALTER TABLE може заблокувати таблицю на десятки хвилин.
#
# `start_after` вказує на найсвіжіший squash-anchor (init_consolidated).
# Всі майбутні міграції з timestamp > 20260709140000 проходять
# Strong Migrations перевірки. Bump цього значення під час кожного
# наступного squash (див. db/migrate/<ts>_init_consolidated.rb).
StrongMigrations.start_after = 20260711160000

# Час очікування lock-у на таблицю перед відміною міграції.
# 10 секунд — безпечний ліміт для IoT uplink pipeline (телеметрія не чекатиме довше).
StrongMigrations.lock_timeout = 10.seconds

# Час виконання одного SQL statement.
# 1 година — для масивних backfill на мільярдах рядків (blockchain_transactions, telemetry_logs).
StrongMigrations.statement_timeout = 1.hour

# Target PostgreSQL version for safety checks
StrongMigrations.target_version = 16
