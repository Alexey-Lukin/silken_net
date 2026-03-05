# frozen_string_literal: true

module SilkenNet
  # Geospatial utility for GPS-based distance calculations.
  # Used for the anti-sofa-repair drift check in maintenance records.
  module GeoUtils
    EARTH_RADIUS_M = 6_371_000.0

    # Returns the great-circle distance in metres between two WGS-84 points.
    def self.haversine_distance_m(lat1, lng1, lat2, lng2)
      phi1 = lat1 * Math::PI / 180
      phi2 = lat2 * Math::PI / 180
      dphi = (lat2 - lat1) * Math::PI / 180
      dlng = (lng2 - lng1) * Math::PI / 180

      a = Math.sin(dphi / 2)**2 +
          Math.cos(phi1) * Math.cos(phi2) * Math.sin(dlng / 2)**2

      2 * EARTH_RADIUS_M * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end
  end
end
