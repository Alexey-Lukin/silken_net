# frozen_string_literal: true

class Cluster < ApplicationRecord
  # Якщо кластер видаляється, дерева і шлюзи не знищуються,
  # а просто "відв'язуються" (nullify), щоб не втратити історичні дані.
  has_many :trees, dependent: :nullify
  has_many :gateways, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :region, presence: true

  # Додаткові поля, які ми тримаємо в базі:
  # - geojson_polygon: jsonb (Межі лісу для карти)
  # - climate_type: string (Наприклад, "Помірний", "Тропічний")

  def total_active_trees
    trees.count
  end
end
