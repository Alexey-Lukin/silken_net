# frozen_string_literal: true

class Cluster < ApplicationRecord
  # Кожен лісовий кластер має належати юридичній особі (інвестору/власнику)
  belongs_to :organization
  
  has_many :trees, dependent: :nullify
  has_many :gateways, dependent: :nullify
  has_many :naas_contracts, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :region, presence: true

  # - geojson_polygon: jsonb (Межі лісу для карти)
  # - climate_type: string (Наприклад, "Помірний", "Тропічний")

  def total_active_trees
    trees.count
  end
end
