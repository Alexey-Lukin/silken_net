# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [FW.66 (Б) · S8b, ратифіковано founder 2026-10-11 — `05_02 §E.60`] Вміст листа Меркла v2:
# (1) підписаний конверт QATT кожного атестованого батча зберігається (`qatt_envelopes`), рядок
# телеметрії несе його sha256, лист v2 — полем; (2) лист v2 несе вхід формули балів
# (`ema_delta_t_s`, доти транзієнт) і зараховані бали кадру.
#
# Ідентичність конверта тримає СХЕМА: CHECK `sha256 = sha256(envelope)` — ключ не можна записати
# поруч із чужими байтами жодним писачем, а FK рядка на конверт не дає хешу, що ні на що не вказує,
# потрапити в лист: заякорений лист із «висячим» хешем читався б верифікатором підробкою назавжди. Зберігаються лише атестовані конверти, тож публічний
# ключ, що їх перевірив, обовʼязковий (знімок на мить прийому — ключ Королеви ротується).
# Таблиця не партиційована й без ретенції. ⚠️ Єдиний дозволений механізм ретенції телеметрії — дроп
# партицій (ARCH.59) — ще не збудовано (`00_07` ARCH.70); коли збудують, конверт переживе рядки, що на
# нього посилались, тож ретенцію конвертів вирішувати разом із ним, а не тут.
#
# `safety_assured` — названа підстава, як у `AddLeafV2ToTelemetryLogs`: CHECK і FK зі сканом небезпечні
# для живої таблиці, а canopy у Фазі ∅ без даних. ⚠️ Порядок rolling-деплою тут ЗВОРОТНИЙ до
# `AddLeafV2ToTelemetryLogs`: спершу міграція, потім код — новий код пише в нові колонки й таблицю, а
# старий новий CHECK не порушує (CCM-рядки вже несуть цілі бали). ⚠️ З живими даними FK сканує всі
# партиції під локом, а `NOT VALID` для FK партиційованої таблиці PG17 не приймає — тоді у вікні обслуговування.
class AddQattEnvelopesAndLeafV2Content < ActiveRecord::Migration[8.1]
  def change
    create_table :qatt_envelopes do |t|
      t.binary :sha256, null: false
      t.references :gateway, null: false, foreign_key: true
      t.string :gateway_uid, null: false
      t.binary :envelope, null: false
      t.string :public_key_hex, limit: 64, null: false
      t.datetime :received_at, null: false
      # Єдине змінне поле: воркер ставить його, коли з батча закомічено хоч один рядок, — довговічна
      # половина «done», що переживає втрату Redis-nonce (повтор відкидається лише на розпакованому).
      t.datetime :unpacked_at
      t.datetime :created_at, null: false
    end
    add_index :qatt_envelopes, :sha256, unique: true

    add_column :telemetry_logs, :qatt_envelope_sha256, :binary
    add_column :telemetry_logs, :ema_delta_t_s, :integer

    safety_assured do
      add_check_constraint :qatt_envelopes, "sha256 = sha256(envelope)", name: "qatt_envelopes_sha256_is_envelope_hash"
      add_check_constraint :qatt_envelopes, "public_key_hex ~ '^[0-9a-f]{64}$'", name: "qatt_envelopes_public_key_hex_shape"

      add_check_constraint :telemetry_logs,
                           "qatt_envelope_sha256 IS NULL OR octet_length(qatt_envelope_sha256) = 32",
                           name: "telemetry_logs_qatt_envelope_sha256_shape"
      add_check_constraint :telemetry_logs,
                           "ema_delta_t_s IS NULL OR ema_delta_t_s BETWEEN 0 AND 65535",
                           name: "telemetry_logs_ema_delta_t_s_range"
      add_foreign_key :telemetry_logs, :qatt_envelopes, column: :qatt_envelope_sha256, primary_key: :sha256

      # Лист v2 тепер несе бали — цілі й невідʼємні за побудовою (`ccm_growth_points`), тож серіалізатор
      # віддає ціле без втрат, а NULL у листі неможливий.
      remove_check_constraint :telemetry_logs,
                              "(leaf_version = 1 AND raw_record IS NULL) OR " \
                              "(leaf_version = 2 AND raw_record IS NOT NULL AND octet_length(raw_record) = 30)",
                              name: "telemetry_logs_leaf_version_shape"
      add_check_constraint :telemetry_logs,
                           "(leaf_version = 1 AND raw_record IS NULL) OR " \
                           "(leaf_version = 2 AND raw_record IS NOT NULL AND octet_length(raw_record) = 30 " \
                           "AND growth_points IS NOT NULL AND growth_points >= 0 AND growth_points = trunc(growth_points))",
                           name: "telemetry_logs_leaf_version_shape"
    end
  end
end
