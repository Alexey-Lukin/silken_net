# frozen_string_literal: true

class TreeFamily < ApplicationRecord
  has_many :trees, dependent: :restrict_with_error

  # name: рядок (напр., "Quercus robur" або "Дуб звичайний")
  # baseline_impedance: базова лінія опору для цієї породи (Ом)
  # critical_z_min, critical_z_max: межі осі Z для розрахунку стресу (з bio_contract.rb)

  validates :name, presence: true, uniqueness: true
  validates :baseline_impedance, :critical_z_min, :critical_z_max, presence: true, numericality: true

  # [НОВЕ]: Повертає параметри для математичної моделі Атрактора
  # Це дозволяє сервісу Attractor бути "чистим" від знань про породи
  def attractor_thresholds
    {
      min: critical_z_min,
      max: critical_z_max,
      baseline: baseline_impedance
    }
  end

  # Додаткові фізичні властивості для майбутнього Edge AI аналізу
  # Наприклад, густина деревини (кг/м3) для точнішого розрахунку метаболізму
  # store_accessor :biological_properties, :wood_density, :sap_flow_rate
end
