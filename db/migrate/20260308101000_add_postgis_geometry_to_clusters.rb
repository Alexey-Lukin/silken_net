# frozen_string_literal: true

# PostGIS Spatial Indexing для Cluster (Zone 1.2: Стіна масштабування)
#
# ПРОБЛЕМА: geojson_polygon зберігається як JSONB. Для Point-in-Polygon
# запитів на масштабі країни (мільйони кластерів) JSONB-пошук — це O(n) sequential scan.
#
# РІШЕННЯ: Додаємо geometry колонку з GIST індексом для O(log n) spatial queries.
# PostgreSQL тригер автоматично синхронізує geo_boundary з geojson_polygon,
# тому зміни через Rails, raw SQL чи прямий доступ до БД завжди консистентні.
#
# Зберігаємо JSONB для API-відповідей та зворотної сумісності.
class AddPostgisGeometryToClusters < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE EXTENSION IF NOT EXISTS postgis"

    execute <<~SQL
      ALTER TABLE clusters ADD COLUMN geo_boundary geometry(Geometry, 4326)
    SQL

    # Тригер-функція: автоматична синхронізація geo_boundary з geojson_polygon
    # Працює незалежно від джерела запису (Rails, raw SQL, DBA)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION sync_cluster_geo_boundary()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.geojson_polygon IS NOT NULL
           AND NEW.geojson_polygon->>'type' IS NOT NULL
           AND NEW.geojson_polygon->>'coordinates' IS NOT NULL THEN
          BEGIN
            NEW.geo_boundary := ST_SetSRID(ST_GeomFromGeoJSON(NEW.geojson_polygon::text), 4326);
          EXCEPTION WHEN OTHERS THEN
            NEW.geo_boundary := NULL;
          END;
        ELSE
          NEW.geo_boundary := NULL;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql
    SQL

    execute <<~SQL
      CREATE TRIGGER trigger_sync_cluster_geo_boundary
        BEFORE INSERT OR UPDATE OF geojson_polygon ON clusters
        FOR EACH ROW
        EXECUTE FUNCTION sync_cluster_geo_boundary()
    SQL

    # Backfill: конвертуємо існуючі JSONB-полігони в geometry
    execute <<~SQL
      UPDATE clusters
      SET geo_boundary = ST_SetSRID(ST_GeomFromGeoJSON(geojson_polygon::text), 4326)
      WHERE geojson_polygon IS NOT NULL
        AND geojson_polygon->>'type' IS NOT NULL
        AND geojson_polygon->>'coordinates' IS NOT NULL
    SQL

    # GIST індекс для O(log n) spatial queries (ST_Contains, ST_Within, ST_Intersects)
    execute <<~SQL
      CREATE INDEX index_clusters_on_geo_boundary ON clusters USING gist (geo_boundary)
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS trigger_sync_cluster_geo_boundary ON clusters"
    execute "DROP FUNCTION IF EXISTS sync_cluster_geo_boundary()"
    execute "DROP INDEX IF EXISTS index_clusters_on_geo_boundary"
    execute "ALTER TABLE clusters DROP COLUMN IF EXISTS geo_boundary"
  end
end
