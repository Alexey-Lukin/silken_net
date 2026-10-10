# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class TreeFamily < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Захист цілісності: не можна видалити геном, поки живий хоч один його носій
  has_many :trees, dependent: :restrict_with_error

  # ⚖️ [FW.66, делеговано 2026-10-09 — врізка `03_04 §7.3`] Пару `critical_z_min/max`
  # знято разом із видачею смуги FW.8: вердиктного читача вона не мала в жодній ері,
  # тобто була порогом, яким не судить ніщо (клас `СЛОВО`, `05_05 §3.2`). Колонки
  # лишаються в БД до другого кроку — `remove_column` окремим комітом ПІСЛЯ деплою
  # цього (`db:prepare` у entrypoint мігрує під живим старим контейнером).
  self.ignored_columns += %w[critical_z_min critical_z_max]

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true

  # [Series D: Глобальний Аудит]: Латинська назва для міжнародних контрактів та страхування
  validates :scientific_name, uniqueness: true, allow_nil: true

  # [Series C: Tokenomics]: Коефіцієнт секвестрації вуглецю для зваженого нарахування балів
  # [ARCH.84] `allow_nil` тут НЕ ставити: схемний `DEFAULT 1.0` є авторським значенням
  # (шкала відносна — дуб 1.5, сосна 0.8, тож 1.0 = «рівно середній вид»), а не
  # підстановкою на місце невиміряного. Порожнє поле мусить відповідати 422, інакше
  # дефолт почне спрацьовувати мовчки на грошовому тракті (→ `Wallet#credit!`).
  validates :carbon_sequestration_coefficient,
            numericality: { greater_than: 0 }

  # --- JSONB PROPERTIES (The TinyML Support) ---
  # Гнучкі властивості для специфічного аналізу кожної породи
  # [ARCH.102 ⚖️ 08-20] `sap_flow_index` ЗНЯТО: єдиний алгоритмічний споживач
  # (pest-множник) демонтовано 08-16 разом із вердиктами, і поле лишалось
  # фікцією без одиниць та літературного якоря, яку адмін мусив вигадувати.
  # [FW.66] `optimal_z_target` знято тим самим кроком, що й пару `critical_z_*`:
  # його читала лише видача смуги FW.8. Історичні ключі в jsonb нешкідливі.
  store_accessor :biological_properties,
                 :bark_thickness,
                 :foliage_density,
                 :fire_resistance_rating

  # [ВИПРАВЛЕНО: Типізація JSONB-полів]:
  # Виганяємо "Data Type Phantom" — гарантуємо, що параметри для TinyML є числами
  validates :bark_thickness, :foliage_density, :fire_resistance_rating,
            numericality: true,
            allow_nil: true

  # --- КОЛБЕКИ ---
  # [ARCH.84] `store_accessor` кладе в JSONB рівно те, що приїхало з форми, — а з
  # HTML-форми приїжджає РЯДОК. Звідси дві незалежні поломки, і обидві живі:
  #
  # (1) порожній `<input type="number">` шле `""`, тож `allow_nil` вище не
  #     спрацьовує (порожній рядок не `nil`) і кожна ОПЦІЙНА властивість ставала
  #     де-факто обовʼязковою: єдиний UI-шлях завести породу відповідав 422
  #     «is not a number». `normalizes` сюди не дістає — виміряно: воно працює над
  #     справжніми атрибутами, а `store_accessor` ним не є (клас `Organization#locale`).
  #
  # (2) заповнене поле осідає рядком, а `AlertDispatchService` ним АРИФМЕТИЧИТЬ:
  #     `temperature_c >= fire_resistance_rating` кидає `ArgumentError`. Виміряно
  #     рантаймом, і ціна не там, де здається: виняток ловить сусідній
  #     `rescue ArgumentError` в `UnpackTelemetryWorker` і пише в лог «Корупція
  #     Base64 від <gateway>» — тобто провина приписується шлюзу за те, що
  #     адміністратор увів у довідник, і жоден слід не веде до причини.
  #
  # ⚠️ Звужено до РЯДКІВ навмисно: `compact_blank` зʼїв би й `false`, тож майбутня
  # булева властивість зникала б мовчки при кожному збереженні.
  before_validation :normalize_biological_properties

  # --- СКОУПИ ---
  scope :alphabetical, -> { order(name: :asc) }

  # --- МЕТОДИ (The Lens of Truth) ---

  # [Series D]: Назва для відображення в UI та міжнародних контрактах
  # Формат: "Quercus robur (Дуб звичайний)" або просто "Дуб звичайний"
  def display_name
    if scientific_name.present?
      "#{scientific_name} (#{name})"
    else
      name
    end
  end

  # [Series C: Tokenomics]: Зважене нарахування балів росту залежно від породи.
  # Дуб (Quercus) акумулює вуглець швидше за Сосну (Pinus),
  # тому коефіцієнт використовується у Wallet#credit! для справедливого розподілу.
  def weighted_growth_points(raw_points)
    (raw_points * carbon_sequestration_coefficient).round(2)
  end

  private

  def normalize_biological_properties
    return if biological_properties.blank?

    self.biological_properties = biological_properties.filter_map { |key, value|
      # Число/`nil`/boolean — не наша справа: нормалізуємо лише те, що приїхало
      # рядком, тобто рівно вантаж HTML-форми.
      next [ key, value ] unless value.is_a?(String)
      next if value.blank?

      # ⚠️ `to_f` тут був би НАЙГІРШИМ можливим ліком: «abc» стало б `0.0`, тобто
      # `numericality` перестала б скаржитись, а поріг пожежі став би нулем.
      # `Integer`/`Float` з `exception: false` лишають нечисловий рядок як є —
      # і валідація доповідає про нього, як і мусить.
      [ key, Integer(value, exception: false) || Float(value, exception: false) || value ]
    }.to_h
  end
end
