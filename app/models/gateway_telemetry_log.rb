# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class GatewayTelemetryLog < ApplicationRecord
  # PostgreSQL PK is composite (id, created_at) for declarative partitioning,
  # but Rails should use id alone for lookups, dom_id, and associations —
  # otherwise record.id returns [id, created_at] (дзеркало BlockchainTransaction).
  self.primary_key = "id"

  # --- КОНСТАНТИ ПОРОГІВ (Single Source of Truth) ---
  LOW_BATTERY_THRESHOLD     = 3300  # mV: нижче цього — виснаження батареї/сонячної панелі
  OVERHEAT_THRESHOLD        = 65    # °C: SIM7070G починає деградувати при перевищенні
  LOW_SIGNAL_THRESHOLD      = 5     # CSQ: нижче 5 — ризик втрати батчів телеметрії
  # SSOT — docs/02_05 §4а.5: LiFePO4 розряд безпечний до −20°C; нижче
  # графітове плакування деградує і Queen уходить offline у найгірший
  # момент (зимова буря — коли HIL-симуляція не врятує). Hardware
  # доповнення (NTC + charge MOSFET cut-off) — HW.16 у docs/00_07.
  LOW_TEMPERATURE_THRESHOLD = -20   # °C: нижче — ризик відмови LiFePO4 / brownout
  # [ARCH.54] Стільки провалених flush-розмов у пульсі = LTE/Starlink
  # деградує системно (лічильник сатурований, скидається power-cycle'ом).
  COAP_FAIL_ALERT_THRESHOLD = 10

  # [ARCH.54] health_flags бітфілд (wire-дім: queen_attest.h QATT_HFLAG_*)
  HFLAG_CCM_ERA      = 0x01
  HFLAG_RING         = 0x02
  # [FW.2 гейт (а)] Wire-видимість atomic-cutover'а: Королева бачила
  # 16B-легасі-телеметрію (непрошиті Солдати поруч) / DID=0 CCM-спуфи.
  HFLAG_LEGACY_DROPS = 0x04
  HFLAG_CCM_SPOOF    = 0x08

  # --- ЗВ'ЯЗКИ ---
  # Зв'язок через UID дозволяє зберігати логіку ідентифікації заліза
  # навіть якщо записи в базі будуть перенесені або архівуватися.
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid

  # --- ВАЛІДАЦІЇ ---
  # [KENOSIS TITAN]: Валідації видалено з hot path.
  # На Series C/D масштабі (тисячі шлюзів, пакет кожні 5-10 хв) дані перевіряються
  # в GatewayTelemetryWorker.valid_gateway_stats? до створення запису.
  # ActiveRecord валідації на кожному INSERT (зокрема при insert_all) — зайві цикли CPU.

  # --- СКОУПИ ---
  # [ARCH.54] Пульс v2 напруги/температури НЕ несе (Королева без ADC) —
  # battery/thermal-скоупи лишаються для ери залізного тракту (nil-рядки
  # ці WHERE природно відсіюють), джерело даних сьогодні = health-блок.
  scope :recent, -> { order(created_at: :desc) }
  scope :critical_battery, -> { where("voltage_mv < ?", LOW_BATTERY_THRESHOLD) }
  scope :overheated, -> { where("temperature_c > ?", OVERHEAT_THRESHOLD) }
  scope :freezing, -> { where("temperature_c < ?", LOW_TEMPERATURE_THRESHOLD) }
  scope :weak_signal, -> { where("cellular_signal_csq < ? AND cellular_signal_csq != 99", LOW_SIGNAL_THRESHOLD) }
  scope :uplink_degraded, -> { where("coap_fail_count >= ?", COAP_FAIL_ALERT_THRESHOLD) }

  # [PERF.1 (а)] «Останній пульс на КОЖЕН шлюз набору» — і форма тут ІНША, ніж у
  # дзеркального `TelemetryLog.latest_per_tree`, попри дослівно те саме питання.
  #
  # 🔴 Виміряно EXPLAIN'ом, а не виведено з прецеденту: `DISTINCT ON` дає `Unique`
  # над ТИМ САМИМ `Sort` над `Append` по всіх партиціях, тобто скану не скорочує
  # взагалі. Його виграш у дзеркальному випадку був у КІЛЬКОСТІ запитів (N→1), а
  # сторінка шлюзів уже робила ОДИН запит — преload `has_one`; отже там лишалась
  # би сама економія Ruby-обʼєктів. LATERAL натомість дає `Limit` → `Merge Append`
  # → `Index Scan Backward`, тобто планувальник спиняється РАНО на індексі
  # `(queen_uid, created_at)`, який уже стоїть на кожній партиції.
  #
  # ⚠️ Часової межі НЕМА свідомо: питання звучить «останній, хоч би коли він був»,
  # тож будь-яке вікно змінило б ВІДПОВІДЬ — довго мовчазна Королева віддала б
  # порожньо замість останнього відомого стану. Це та сама пастка, на якій PERF.1
  # уже спіткнувся з `2.months` у `previous_lorenz_state_for`.
  #
  # ⚠️ Порожній набір перевірено окремо: `unnest(ARRAY[]::character varying[])`
  # віддає нуль рядків і НЕ кидає, тож ранній `return` тут про вартість, не про
  # безпеку.
  def self.latest_per_gateway(uids)
    return {} if uids.blank?

    find_by_sql(sanitize_sql_array([ <<~SQL, uids ])).index_by(&:queen_uid)
      SELECT l.*
      FROM unnest(ARRAY[?]::character varying[]) AS g(uid)
      JOIN LATERAL (
        SELECT * FROM gateway_telemetry_logs t
        WHERE t.queen_uid = g.uid
        ORDER BY t.created_at DESC
        LIMIT 1
      ) l ON TRUE
    SQL
  end

  # --- МЕТОДИ (Health Intelligence) ---

  # Допоміжний метод для дашборду (переведення CSQ у відсотки)
  # [ARCH.84] 🔴 `99` — це «unknown» за 3GPP (канон `04_01` про `cellular_signal_csq`),
  # а не нульовий сигнал: доти обидва стани віддавали **0**, тобто «модем на звʼязку,
  # якість нульова» замість «модем не відповів». Сусідній `signal_dbm` від початку
  # робив ПРАВИЛЬНО (`nil` на 99/nil) — і саме він мертвий, тоді як брехливий читали
  # два екрани. Тепер обидва методи відповідають на «немає даних» однаково.
  def signal_quality_percentage
    return nil if cellular_signal_csq == 99 || cellular_signal_csq.nil?
    ((cellular_signal_csq / 31.0) * 100.0).round(1)
  end

  # [НОВЕ]: Перерахунок CSQ у dBm (стандарт 3GPP)
  # Формула: RSSI (dBm) = 2 * CSQ - 113
  # Результат від -113 dBm (гранична чутливість) до -51 dBm (ідеальний сигнал)
  def signal_dbm
    return nil if cellular_signal_csq == 99 || cellular_signal_csq.nil?
    (2 * cellular_signal_csq) - 113
  end

  # [ARCH.54] Прапорці ери з пульсу (wire: queen_attest.h)
  def ccm_era?  = health_flags.to_i.anybits?(HFLAG_CCM_ERA)
  def ring_mounted? = health_flags.to_i.anybits?(HFLAG_RING)
  # [FW.2 гейт (а)] Cutover-вікно: поруч дихають непрошиті Солдати / спуфи
  def legacy_drops_seen? = health_flags.to_i.anybits?(HFLAG_LEGACY_DROPS)
  def ccm_spoof_seen?    = health_flags.to_i.anybits?(HFLAG_CCM_SPOOF)

  # [НОВЕ]: Швидка перевірка на критичний стан заліза
  # Використовується GatewayTelemetryWorker для ініціації EwsAlert.
  # Nil-safe: пульс v2 не несе напруги/температури (nil = «не виміряно»,
  # НЕ «нуль») — кожен критерій перевіряє власне поле незалежно.
  def critical_fault?
    (voltage_mv.present? && voltage_mv < LOW_BATTERY_THRESHOLD) ||
      (temperature_c.present? && temperature_c > OVERHEAT_THRESHOLD) ||
      (temperature_c.present? && temperature_c < LOW_TEMPERATURE_THRESHOLD) ||
      (cellular_signal_csq.present? && cellular_signal_csq != 99 &&
        cellular_signal_csq < LOW_SIGNAL_THRESHOLD) ||
      coap_fail_count.to_i >= COAP_FAIL_ALERT_THRESHOLD
  end
end
