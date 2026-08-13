# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.91] Ознака походження запису обслуговування — персистентна, бо на ній
# стоїть виняток Evidence Protocol.
#
# Доти виняток ніс `attr_accessor :skip_photo_validation`, тобто жив рівно
# один інстанс. Валідація фото оголошена без `on:`, отже біжить на КОЖЕН
# `save` — а після `find` прапорця вже немає. Наслідок вимірювався
# round-trip'ом: запис монтажу, створений системою, віддає `valid? → false`
# і будь-яке оновлення падає 422 назавжди, включно з `verify`. Тобто
# Trust-Protocol-прапорець на вузлах, провіжінених через `POST /provisioning`,
# був недосяжний за побудовою.
#
# Колонка тримає ту саму семантику, що й скинутий accessor («цей рядок
# написала платформа, не лісник із камерою»), але переживає reload — і тим
# самим є фактом провенансу, який MRV-читач бачить у самому рядку.
#
# `safety_assured` не потрібен: `add_column` з дефолтом на PG 11+ не переписує
# таблицю. Бекфілу немає свідомо — pre-launch, а data-INSERT у міграції
# заборонений (дім рецепту — шапка `init_consolidated`).
class AddSystemGeneratedToMaintenanceRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenance_records, :system_generated, :boolean, default: false, null: false
  end
end
