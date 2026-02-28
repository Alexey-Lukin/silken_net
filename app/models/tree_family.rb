# frozen_string_literal: true

class TreeFamily < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Захист цілісності: не можна видалити геном, поки живий хоч один його носій
  has_many :trees, dependent: :restrict_with_error

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :baseline_impedance, :critical_z_min, :critical_z_max, 
            presence: true, numericality: true

  # --- JSONB PROPERTIES (The TinyML Support) ---
  # Гнучкі властивості для специфічного аналізу кожної породи
  store_accessor :biological_properties, 
                 :sap_flow_index, 
                 :bark_thickness, 
                 :foliage_density,
                 :fire_resistance_rating

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

  # "Межа Смерті": Якщо імпеданс падає нижче 30% від базового,
  # дерево втратило провідні тканини (фізична загибель або зруб).
  def death_threshold_impedance
    baseline_impedance * 0.3
  end

  # Назва для відображення в UI (напр. "Quercus robur (Дуб звичайний)")
  def display_name
    name
  end

  # Перевірка гомеостазу: чи вписується Z-значення в межі стабільності даної породи
  def healthy_z?(z_value)
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
end
