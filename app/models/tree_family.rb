# frozen_string_literal: true

class TreeFamily < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Ми не дозволяємо видаляти породу, якщо в лісі ще є хоч одне таке дерево
  has_many :trees, dependent: :restrict_with_error

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :baseline_impedance, :critical_z_min, :critical_z_max, presence: true, numericality: true

  # [НОВЕ]: Підтримка гнучких біологічних властивостей через JSONB
  # Це дозволить нам зберігати специфічні дані для TinyML моделей без міграцій
  # Наприклад: sap_flow_index, bark_thickness, foliage_density
  # store_accessor :biological_properties, :sap_flow_index, :fire_resistance_rating

  # --- МЕТОДИ (The Lens of Truth) ---

  # Повертає параметри для математичної моделі Атрактора
  def attractor_thresholds
    {
      min: critical_z_min.to_f,
      max: critical_z_max.to_f,
      baseline: baseline_impedance.to_f
    }
  end

  # [НОВЕ]: Розрахунок "Межі Смерті"
  # Якщо імпеданс падає нижче 30% від базового — дерево фізично мертве (немає сокоруху)
  def death_threshold_impedance
    baseline_impedance * 0.3
  end

  # [НОВЕ]: Опис для UI/Мобільного додатка
  def display_name
    # Можна додати логіку перекладу або виводу латини поруч із народною назвою
    name
  end

  # Допоміжний метод для швидкої перевірки, чи вписується Z-значення в межі породи
  def healthy_z?(z_value)
    z_value.between?(critical_z_min, critical_z_max)
  end
end
