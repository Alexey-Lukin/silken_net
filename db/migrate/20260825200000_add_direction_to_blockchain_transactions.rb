# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.95] Напрямок грошового рядка стає ЯВНИМ, а не деривованим.
#
# ⚖️ Присуд 2026-08-25 (машина за делегуванням founder). Доти напрямок деривувався
# з `sourceable_type = "NaasContract"`, і ARCH.101 ратифікував саме цю деривацію —
# але на ПЕРЕДУМОВІ, записаній дослівно в моделі: «єдиний slash-шлях». ESG-погашення
# цю передумову знімає, бо є другим родом вилучення з обігу й НЕ має природного
# `sourceable`-об'єкта. Тобто ратифіковано було «деривація, доки burn має одну
# причину», а не «деривація назавжди».
#
# Чому колонка, а не другий член дискримінатора:
#   1. `NOT IN (...)` з NULL віддає NULL, тож кожен новий читач мусив би відтворювати
#      `IS DISTINCT FROM`/`IS NULL`-пастку руками — а два сайти вже роблять це поза
#      моделлю, попри її власне «Дім свідомо ОДИН».
#   2. Погашенню довелось би вигадати штучний `sourceable`.
#   3. `NOT NULL` + default знімає NULL-вісь назавжди.
#
# `BURN_SOURCEABLE_TYPE` НЕ зникає: він і далі відповідає на інше питання — «який
# саме burn є slash'ем» (база `05_05 §3`). Розводяться РІД операції й ЇЇ ПРИЧИНА.
class AddDirectionToBlockchainTransactions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # PG11+ : default на існуючій таблиці — метадані, не rewrite (партиції теж).
    add_column :blockchain_transactions, :direction, :string,
               default: "mint", null: false

    # Backfill існуючих slash-інтентів — НЕСУЧИЙ, не косметика: без нього
    # `net_minted_supply` порахував би кожен історичний burn ЕМІСІЄЮ, а той
    # агрегат годує L1-якір і базу слешингу. Форма — batched `update_all` поза
    # DDL-транзакцією (`in_batches`), тобто та сама safe-форма, що її пропонує
    # сам `strong_migrations`; `execute` тут відкинуто свідомо — він вимагав би
    # `safety_assured`, а це твердження про майбутнє («таблиця буде мала»), і
    # прецеденту такого в `db/migrate/` немає.
    backfill_scope.in_batches(of: 5_000) { |batch| batch.update_all(direction: "burn") }

    # ⛔ Індексу на `direction` свідомо НЕМА. Колонку читають лише разом із
    # `token_type`+`status` (обидва вже у WHERE кожного споживача), а на
    # партиційній таблиці `CREATE INDEX CONCURRENTLY` неможливий — тобто ціною
    # був би або лок, або `safety_assured`. Виміру, що індекс потрібен, немає:
    # mainnet не задеплоєно. Заводити його — коли з'явиться навантаження.
  end

  def down
    remove_column :blockchain_transactions, :direction
  end

  private

  # Локальний AR-клас, а не `BlockchainTransaction`: модель несе AASM, валідації
  # й колбеки, яких міграція не має права виконувати, і чия форма зміниться
  # раніше за цей файл.
  def backfill_scope
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "blockchain_transactions"
      self.primary_key = "id"
    end
    klass.where(sourceable_type: "NaasContract")
  end
end
