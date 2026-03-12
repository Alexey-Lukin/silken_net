# frozen_string_literal: true

# = ===================================================================
# 🌍 GEO LOCATABLE (Shared Geospatial Validations)
# = ===================================================================
# Уніфікована валідація координат WGS-84 для всіх гео-об'єктів SilkenNet:
# - Tree (координати дерева)
# - Gateway (координати шлюзу)
# - MaintenanceRecord (GPS телефону патрульного)
#
# Валідація:
#   latitude:  -90..90   (WGS-84 діапазон)
#   longitude: -180..180 (WGS-84 діапазон)
#   Обидва поля необов'язкові (allow_nil: true)
module GeoLocatable
  extend ActiveSupport::Concern

  included do
    validates :latitude,  numericality: { in: -90..90 },   allow_nil: true
    validates :longitude, numericality: { in: -180..180 },  allow_nil: true
  end

  # Перевірка, чи об'єкт має координати
  def geolocated?
    latitude.present? && longitude.present?
  end
end
