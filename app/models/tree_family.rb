# frozen_string_literal: true

class TreeFamily < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Захист цілісності: не можна видалити геном, поки живий хоч один його носій
  has_many :trees, dependent: :restrict_with_error

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :baseline_impedance, :critical_z_min, presence: true, numericality: true

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
                 :fire_resistance_rating

  # [ВИПРАВЛЕНО: Типізація JSONB-полів]:
  # Виганяємо "Data Type Phantom" — гарантуємо, що параметри для TinyML є числами
  validates :sap_flow_index, :bark_thickness, :foliage_density, :fire_resistance_rating,
            numericality: true,
            allow_nil: true

  # --- КОЛБЕКИ ---
  # [Hot Path Cache]: Інвалідація кешу при зміні генетичних параметрів
  after_update :invalidate_thresholds_cache, if: :thresholds_changed?

  # --- СКОУПИ ---
  scope :alphabetical, -> { order(name: :asc) }

  # --- МЕТОДИ (The Lens of Truth) ---

  # Повертає параметри для математичної моделі Атрактора Лоренца
  # Використовується в SilkenNet::Attractor та InsightGeneratorService
  def attractor_thresholds
    {
      min: critical_z_min.to_f,
      max: critical_z_max.to_f,
      baseline: baseline_impedance.to_f
    }
  end

  # [Hot Path Cache]: Кешована версія attractor_thresholds для обробки телеметрії.
  # Геном змінюється вкрай рідко, але attractor_thresholds викликається
  # при обробці кожного пакету від мільйонів дерев.
  def attractor_thresholds_cached
    Rails.cache.fetch(thresholds_cache_key, expires_in: 24.hours) do
      attractor_thresholds
    end
  end

  # "Межа Смерті": Якщо імпеданс падає нижче 30% від базового,
  # дерево втратило провідні тканини (фізична загибель або зруб).
  def death_threshold_impedance
    baseline_impedance * 0.3
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

  # [НОВЕ]: Повертає статус стресу на основі імпедансу
  # Допомагає AI-Оракулу класифікувати рівень загрози
  def stress_level(current_impedance)
    return :dead if current_impedance <= death_threshold_impedance
    return :critical if current_impedance <= baseline_impedance * 0.6
    return :warning if current_impedance <= baseline_impedance * 0.8
    :normal
  end

  private

  def thresholds_cache_key
    "tree_family_#{id}_thresholds"
  end

  def thresholds_changed?
    saved_change_to_critical_z_min? || saved_change_to_critical_z_max? || saved_change_to_baseline_impedance?
  end

  def invalidate_thresholds_cache
    Rails.cache.delete(thresholds_cache_key)
  end
end
