# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [FW.66 (Б) · S8, ратифіковано 2026-10-10 — `05_02 §E.60`] Лист Меркла v2: версія листа — на
# РЯДКУ, не глобальна, а CCM-рядок несе сирий кадр ефіру (`raw_record`, 30 Б). Дефолт `1` живе рівно
# один крок: він заповнює наявні (ECB) рядки, а далі версію мусить назвати кожен писач — тихий дефолт
# зробив би CCM-рядок забудькуватого писача листом v1 з хибною міткою.
# CHECK — замість AR-валідації, яку гарячий шлях свідомо не тримає (KENOSIS): інваріант, на якому
# стоїть диспетчер версій (`Mrv::TelemetryLeaf`), мусить триматись і для `insert_all`/сирого SQL —
# один битий рядок інакше зупинив би тижневий якір L1, що ланцюжиться від останнього підтвердженого.
# ⚠️ `raw_record IS NOT NULL` у v2-гілці несучий: CHECK приймає вираз, що дав NULL, а
# `octet_length(NULL) = 30` — це NULL, тож без нього v2-рядок без кадру проходив би.
# `safety_assured` — названа підстава, як у `RemoveFw8ThresholdColumns`: повний скан під CHECK
# небезпечний для живої таблиці, а canopy у Фазі ∅ без даних (перестворення бази дозволено founder-ом).
# ⚠️ Стеля rolling-деплою: `db:prepare` у web-entrypoint знімає дефолт, поки старий job-контейнер ще
# пише рядки без версії — його INSERT упаде на NOT NULL, і розпакувальник проковтне кадр у своєму
# rescue. З живими даними — спершу код, що пише версію, потім ця міграція.
class AddLeafV2ToTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :telemetry_logs, :raw_record, :binary
    add_column :telemetry_logs, :leaf_version, :integer, limit: 2, null: false, default: 1
    change_column_default :telemetry_logs, :leaf_version, from: 1, to: nil
    safety_assured do
      add_check_constraint :telemetry_logs,
                           "(leaf_version = 1 AND raw_record IS NULL) OR " \
                           "(leaf_version = 2 AND raw_record IS NOT NULL AND octet_length(raw_record) = 30)",
                           name: "telemetry_logs_leaf_version_shape"
    end
  end
end
