# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.84] Знімає `trees.health_streak` разом із усією anti-flapping-петлею.
#
# Колонку денормалізували 2026-03-05 під `TelemetryLog#recovery_confirmed?`, який
# мав закривати біо-тривоги за «3 поспіль здоровими пакетами» — і цей споживач не
# був задротований жодного дня. Присуд founder 2026-08-16: не дротувати, зняти.
#
# 🔴 Підстава — НЕ «нуль читачів» (продакшну не було, тож це вимір недобудованості,
# а не смерті), а те, що КОНСТРУКЦІЯ хибна: сигнал закриття не спростовує сигнал
# відкриття. `healthy?` не кличе `Attractor.homeostatic?`, тобто сліпий до половини
# власного тригера посухи; для `entropy_anomaly` це взагалі інший рівень агрегації
# (Shannon по кластеру за добу ⊥ 3 пакети одного дерева). Повний розбір — `00_07`
# ARCH.84 та `04_01` §TelemetryLog.
#
# Незворотна навмисно: `down` відновив би колонку, але не значення — лічильник
# накопичувальний, а історії його інкрементів ніде немає.
class DropTreesHealthStreak < ActiveRecord::Migration[8.1]
  def up
    safety_assured { remove_column :trees, :health_streak }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
