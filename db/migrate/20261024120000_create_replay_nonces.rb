# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [SEC.39, ратифіковано founder 2026-10-24] Атомарний анти-повтор у Postgres — форма SEC.40
# (`CcmReplayWindow`): unique-ключ (scope, digest) і один оператор `INSERT … ON CONFLICT`. Доти чотири
# сайти тримали nonce у Solid Cache, чий `write(unless_exist: true)` не є SET NX: два конкурентні перші
# записи обидва вигравали (виміряно 199/200), а транзієнтний збій бази кешу читався як ПОВТОР.
# Таблиця нова й порожня, тож індекс у тій самій міграції безпечний.
class CreateReplayNonces < ActiveRecord::Migration[8.1]
  def change
    create_table :replay_nonces do |t|
      t.string :scope, null: false
      t.string :digest, null: false
      # Двофазним сайтам — owner-токен спроби, потім термінальний маркер; одноразовим — NULL.
      t.string :owner
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :replay_nonces, %i[scope digest], unique: true
    # Прибиральник видаляє за `expires_at`; фолбеки QATT/M2M під аварією Redis пишуть рядок на батч і вхід.
    add_index :replay_nonces, :expires_at
  end
end
