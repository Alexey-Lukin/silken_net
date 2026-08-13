# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class TreeFamily < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Захист цілісності: не можна видалити геном, поки живий хоч один його носій
  has_many :trees, dependent: :restrict_with_error

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :critical_z_min, presence: true, numericality: true

  # [Series D: Глобальний Аудит]: Латинська назва для міжнародних контрактів та страхування
  validates :scientific_name, uniqueness: true, allow_nil: true

  # [Series C: Tokenomics]: Коефіцієнт секвестрації вуглецю для зваженого нарахування балів
  validates :carbon_sequestration_coefficient,
            numericality: { greater_than: 0 }

  # [ВИПРАВЛЕНО: Захист законів фізики]:
  # Гарантуємо, що межі Атрактора не перехрещуються
  validates :critical_z_max,
            presence: true,
            numericality: true,
            comparison: { greater_than: :critical_z_min }

  # --- JSONB PROPERTIES (The TinyML Support) ---
  # Гнучкі властивості для специфічного аналізу кожної породи
  store_accessor :biological_properties,
                 :sap_flow_index,
                 :bark_thickness,
                 :foliage_density,
                 :fire_resistance_rating,
                 :optimal_z_target

  # [ВИПРАВЛЕНО: Типізація JSONB-полів]:
  # Виганяємо "Data Type Phantom" — гарантуємо, що параметри для TinyML є числами
  validates :sap_flow_index, :bark_thickness, :foliage_density, :fire_resistance_rating,
            numericality: true,
            allow_nil: true

  # [FW.8] Per-species OPTIMAL_Z_TARGET (Lorenz attractor sweet spot for max CO2 sequestration).
  # Default 29.0 mirrors firmware/bio_contracts/bio_contract.rb BioContract::OPTIMAL_Z_TARGET.
  validates :optimal_z_target,
            numericality: { greater_than: :critical_z_min, less_than: :critical_z_max },
            allow_nil: true

  # --- СКОУПИ ---
  scope :alphabetical, -> { order(name: :asc) }

  # --- МЕТОДИ (The Lens of Truth) ---

  # [FW.8] Effective OPTIMAL_Z_TARGET — per-species value or global default 29.0.
  # Mirrored on firmware as BioContract::OPTIMAL_Z_TARGET.
  # Дім порогів Лоренца для споживачів — `Tree#effective_lorenz_thresholds`
  # (він накладає ще й cluster-overrides); тут лише per-species значення.
  def effective_optimal_z_target
    optimal_z_target.present? ? optimal_z_target.to_f : 29.0
  end

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

  # Перевірка гомеостазу: чи вписується Z-значення в межі стабільності даної породи
  def healthy_z?(z_value)
    # Завдяки валідації comparison, цей метод тепер завжди працює коректно
    z_value.to_f.between?(critical_z_min, critical_z_max)
  end
end
