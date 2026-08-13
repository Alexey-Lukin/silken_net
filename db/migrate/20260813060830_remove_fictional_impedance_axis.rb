# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.86] Імпедансна вісь не мала вимірювального тракту — знімаємо її схему.
#
# Пристрій імпеданс не міряє і ніколи не слав: поля немає в жодній ері
# wire-формату, ADC Солдата має рівно два канали (внутрішня температура +
# Vcap), а в BOM немає жодного bioimpedance-компонента. Сідові значення
# (1000/1200/1500/1800/2200) — точний ряд номіналів резисторів E12, тобто
# вигадані як оми, а не виміряні.
#
# `baseline_impedance` при цьому був ОБОВ'ЯЗКОВИМ (`presence: true`), тож
# кожна порода мусила нести вигадане число; він же ділив безрозмірну
# координату Лоренца в публічному `stress_index`, даючи показник, стиснутий
# у ~2 % шкали. `impedance_offset_ohms` — офсет калібрування сенсора, якого
# немає: писачів у проді нуль, значення завжди дефолтне.
#
# Присуд founder'а 2026-08-13 після двох незалежних досліджень (фізика тракту
# й фізіологія знака): тракт не будуємо. Матеріал і його підстава — `00_07`
# ARCH.86; за `00_06 §5` це гіпотеза, а не канон.
#
# `safety_assured`: pre-launch (нуль вузлів у полі); обидві колонки поза
# індексами, CHECK'ами й FK — перевірено `db/structure.sql`.
class RemoveFictionalImpedanceAxis < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      remove_column :tree_families, :baseline_impedance
      remove_column :device_calibrations, :impedance_offset_ohms
    end
  end

  def down
    safety_assured do
      add_column :tree_families, :baseline_impedance, :integer
      add_column :device_calibrations, :impedance_offset_ohms, :integer
    end
  end
end
