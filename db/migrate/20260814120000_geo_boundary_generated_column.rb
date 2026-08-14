# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [E.36] `clusters.geo_boundary` — тригер → GENERATED ALWAYS ... STORED.
#
# 🔴 Це НЕ чистий рефактор, і саме тому потребувало присуду власника
# (2026-08-14): тригер ТОЛЕРУВАВ битий GeoJSON — `EXCEPTION WHEN OTHERS` писав
# NULL, і запис проходив. Вираз generated column винятків ловити НЕ МОЖЕ, тож
# семантика помилки міняється з тихого NULL на **hard-fail при записі**.
#
# Підстава присуду: кордон кластера, тихо записаний як NULL, — це втрата
# геометрії на платформі, де координата є частиною ДОКАЗУ (MRV-лінійка, Field
# Audit). Гучна відмова чесніша за NULL, якого ніхто не помітить.
#
# ⚠️ ВІКНО: зараз це `DROP COLUMN` + `ADD COLUMN` на майже порожній таблиці —
# практично безкоштовно. Після польового деплою та сама операція означала б
# `ACCESS EXCLUSIVE` rewrite tenant-root плюс GIST-rebuild плюс ризик
# backfill'у на битих рядках. Тобто «КОЛИ» тут важило більше за «чи».
#
# ⊕ Побічно зникає функція, яку `pg_dump` не вміє зберігати з `OR REPLACE` —
# тобто клас «неідемпотентна функція у structure.sql» закривається сам собою.
class GeoBoundaryGeneratedColumn < ActiveRecord::Migration[8.1]
  # 🔴 `safety_assured` з НАЗВАНОЮ підставою, не для тиші. Strong Migrations
  # блокує тут два класи, і обидва блокує правильно — небезпечні вони саме на
  # заповненій таблиці:
  #   · `remove_column` (втрата даних + кеш типів у старих процесах);
  #   · сирий `execute` (інструмент не бачить, що всередині).
  # Підстава зняття блоку — ВИМІР, а не поспіх: `clusters` тут порожня в проді
  # (польового деплою ще не було, TRL 3 gated на anchor/EBFC), тож `DROP+ADD`
  # не переписує жодного рядка. **Саме тому цей крок і робиться ЗАРАЗ:** та сама
  # операція після деплою означала б `ACCESS EXCLUSIVE` rewrite tenant-root.
  # ⚠️ Колонка обчислювана — даних, які можна втратити, у ній не буває за
  # побудовою: вона повністю деривується з `geojson_polygon`.
  def up
    safety_assured do
      execute <<~SQL.squish
        DROP TRIGGER IF EXISTS trigger_sync_cluster_geo_boundary ON clusters
      SQL
      execute "DROP FUNCTION IF EXISTS sync_cluster_geo_boundary()"

      remove_column :clusters, :geo_boundary

      # `CASE` без `ELSE` віддає NULL на відсутньому/неповному GeoJSON — це
      # лишається легальним станом (кордон не заданий). Змінюється лише доля
      # НЕВАЛІДНОГО GeoJSON: доти EXCEPTION-хендлер зводив його до того самого
      # NULL, тепер `ST_GeomFromGeoJSON` кидає, і запис не проходить.
      #
      # Обидві функції виразу перевірені на IMMUTABLE (`pg_proc.provolatile = i`)
      # — інакше PostgreSQL відхилив би generated column за побудовою.
      execute <<~SQL.squish
        ALTER TABLE clusters
          ADD COLUMN geo_boundary geometry(Geometry, 4326)
          GENERATED ALWAYS AS (
            CASE
              WHEN geojson_polygon IS NOT NULL
               AND geojson_polygon->>'type' IS NOT NULL
               AND geojson_polygon->>'coordinates' IS NOT NULL
              THEN ST_SetSRID(ST_GeomFromGeoJSON(geojson_polygon::text), 4326)
            END
          ) STORED
      SQL

      add_index :clusters, :geo_boundary, using: :gist, name: "index_clusters_on_geo_boundary"
    end
  end

  def down
    safety_assured do
      remove_column :clusters, :geo_boundary
    add_column :clusters, :geo_boundary, :geometry, limit: { srid: 4326, type: "geometry" }
    add_index :clusters, :geo_boundary, using: :gist, name: "index_clusters_on_geo_boundary"

    execute <<~SQL
      CREATE FUNCTION sync_cluster_geo_boundary() RETURNS trigger
        LANGUAGE plpgsql AS $$
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
      $$;
    SQL

    execute <<~SQL.squish
      CREATE TRIGGER trigger_sync_cluster_geo_boundary
        BEFORE INSERT OR UPDATE OF geojson_polygon ON clusters
        FOR EACH ROW EXECUTE FUNCTION sync_cluster_geo_boundary()
    SQL
    end
  end
end
