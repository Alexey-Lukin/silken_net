# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.119] Партіальний індекс під дренаж `PeaqBackfillWorker`.
#
# 🔴 Підстава ВИМІРЯНА, не припущена. Наявний `index_trees_on_peaq_did` — UNIQUE btree на
# самій колонці, і планувальник для `peaq_did IS NULL ORDER BY id LIMIT n` його НЕ бере:
# з `enable_seqscan=off` він обирає `Index Scan using trees_pkey … Filter: (peaq_did IS NULL)`,
# тобто йде по всьому PK і фільтрує. На 120 рядках це миттєво й зелене в кожному тесті;
# на флоті — O(дерев) щоночі, тобто рівно та «тихо квадратична на 10¹²» форма, яку
# [`00_01 §1.1`] називає дефектом ТУТ, а не пізніше.
#
# Форма — дзеркало `index_audit_logs_pending_archive` (той самий предикат «чекає на роботу»),
# і предикат індексу мусить збігатися зі скоупом воркера дослівно, інакше він не вживеться.
class AddPendingPeaqDidIndexToTrees < ActiveRecord::Migration[8.1]
  # strong_migrations: `add_index` без `algorithm: :concurrently` блокує записи в `trees`.
  disable_ddl_transaction!

  def change
    add_index :trees, :id,
              where: "peaq_did IS NULL",
              name: "index_trees_pending_peaq_did",
              algorithm: :concurrently
  end
end
