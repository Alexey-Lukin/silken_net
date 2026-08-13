# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.84] «Не виміряно» — це СТАН, а не нуль: знімаємо DEFAULT/NOT NULL із
# денормалізованого стресу дерева.
#
# `latest_stress_index numeric(4,3) DEFAULT 0.0 NOT NULL` означало, що дерево,
# якого нічний прохід не аналізував ЖОДНОГО разу, несе «нуль стресу» — найкращий
# можливий показник. І це не крайовий збіг: `calculate_stress_index_heuristic`
# віддає рівно `0.0` для здорового дерева (обидва доданки — sap і акустика —
# інертні до ENV-калібрування), тобто дефолт збігається з МОДАЛЬНИМ виміром.
# «Бездоганне» і «не міряли» були одним числом, і жоден споживач їх не розрізняв.
#
# Форма ліку не нова — вона ратифікована на сусідній колонці тим самим пунктом:
# `clusters.health_index` nullable із ARCH.84 сайт 1 (`04_01 §3`), ридер читає
# колонку як є, писач без інсайту кладе явний `nil`.
#
# ⛔ Бекфілу НЕМАЄ, і не лише через pre-launch. Єдиний доступний дискримінатор
# («дерево має AiInsight ⇒ колонку писали») спростовується самими сідами: вони
# створюють `daily_health_summary` для КОЖНОГО дерева й не пишуть цю колонку
# жодного разу — тож backfill назвав би «виміряними нулем» усі рядки, включно з
# аномальними, чий інсайт каже 0.95. Це не полагодило б дефект, а завізувало б
# його записом в історії схеми. До того ж на свіжому клоні шлях —
# `db:schema:load` + `db:seed` (шапка анкера), тобто міграція не бігає взагалі.
#
# `safety_assured`: pre-launch (нуль вузлів у полі); колонка поза індексами,
# CHECK'ами й FK — перевірено `db/structure.sql`.
class MakeTreeStressIndexNullable < ActiveRecord::Migration[8.1]
  def up
    change_column_null :trees, :latest_stress_index, true
    change_column_default :trees, :latest_stress_index, from: 0.0, to: nil
  end

  def down
    # Зворотний хід мусить забити NULL-и, інакше NOT NULL не стане.
    safety_assured do
      change_column_default :trees, :latest_stress_index, from: nil, to: 0.0
      change_column_null :trees, :latest_stress_index, false, 0.0
    end
  end
end
