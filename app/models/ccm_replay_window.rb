# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.40, ⚖️ founder 2026-10-05] Ковзне вікно анти-повтору CCM на пару (DID, епоха ключа) —
# RFC 4303 у Postgres. Канон — 03_05 §2.1; DR після відкату БД — 06_06 §5.8.
#
# Вікно стоїть у просторі FC, а не в часі: кадр, повторений через добу чи через рік,
# відкидається так само. Доти анти-повтор тримав запис `Rails.cache` із TTL 25 год, і
# справжній кадр, повторений після вікна, нараховував бали вдруге.
#   top_fc   — найвищий прийнятий FC;
#   seen     — біт k (зліва, з нуля) = кадр top_fc − k уже прийнято;
#   floor_fc — на цьому FC і нижче кадр відкидається завжди (DR-фенс).
# Кадр приймається, якщо він вище floor_fc і або вище top_fc, або в межах WINDOW під ним
# і ще не бачений. Бэклог кільця Королеви (ARCH.35) приходить ПІСЛЯ живих кадрів, тож
# кадр під top_fc — норма, а не атака.
# ⚠️ Стеля WINDOW: бэклог, старший за WINDOW кадрів від живого top_fc, відкидається як
# «нижче вікна». На каденції CCM-ери за моделлю ARCH.8 (1 TX за 1.81 год) це ≈ 300 діб
# мовчання uplink'а, на відвантаженому циклі 26–32 с — лише ≈ 34 год; каденція ARCH.8 —
# передумова фліпу FW.2, тож і цього вікна.
class CcmReplayWindow < ApplicationRecord
  WINDOW = 4096 # = ширина колонки `seen bit(4096)` (db/structure.sql); розходження ловить пін у ccm_replay_window_spec

  # Один атомарний оператор під рядковим локом ON CONFLICT — кадр або приймається й
  # позначається, або не змінює нічого. SET бачить СТАРИЙ рядок `w`, тож зсув карти й
  # новий top_fc рахуються від одного стану.
  ADMIT_SQL = <<~SQL.squish
    INSERT INTO ccm_replay_windows AS w (device_uid, key_epoch, top_fc, floor_fc, seen, created_at, updated_at)
    VALUES (:device_uid, :key_epoch, :frame_counter, 0, ('1' || repeat('0', #{WINDOW - 1}))::bit(#{WINDOW}), now(), now())
    ON CONFLICT (device_uid, key_epoch) DO UPDATE SET
      seen = CASE
        WHEN EXCLUDED.top_fc > w.top_fc
          THEN set_bit(w.seen >> LEAST(EXCLUDED.top_fc - w.top_fc, #{WINDOW}), 0, 1)
        ELSE set_bit(w.seen, w.top_fc - EXCLUDED.top_fc, 1)
      END,
      top_fc = GREATEST(w.top_fc, EXCLUDED.top_fc),
      updated_at = now()
    WHERE EXCLUDED.top_fc > w.floor_fc
      AND (EXCLUDED.top_fc > w.top_fc
           OR (w.top_fc - EXCLUDED.top_fc < #{WINDOW} AND get_bit(w.seen, w.top_fc - EXCLUDED.top_fc) = 0))
    RETURNING 1
  SQL

  # Поточна епоха ключа дерева вже має вікно (фенс створює вікно лише тим, у кого його нема).
  WINDOW_EXISTS_SQL = <<~SQL.squish
    EXISTS (SELECT 1 FROM ccm_replay_windows w
            WHERE w.device_uid = hardware_keys.device_uid AND w.key_epoch = hardware_keys.epoch)
  SQL

  class << self
    # Авторитетний допуск. Кличеться в ТІЙ САМІЙ транзакції, що й рядок `TelemetryLog`
    # (`TelemetryUnpackerService#commit_telemetry`): відкат рядка відкочує й допуск, тож
    # Sidekiq-ретрай кадру не загубить. true — прийнято; false — повтор або нижче вікна.
    def admit!(device_uid:, key_epoch:, frame_counter:)
      sql = sanitize_sql([ ADMIT_SQL, { device_uid:, key_epoch:, frame_counter: } ])
      connection.select_value(sql) == 1
    end

    # Нелокуюче читання — пре-фільтр ДО побічних ефектів кадру (DCI, CMD_TIME_SYNC):
    # очевидний повтор далі не йде. Рішення ухвалює лише `admit!`.
    # nil — кадр свіжий; :duplicate — уже прийнятий; :below_window — під вікном.
    def rejection(device_uid:, key_epoch:, frame_counter:)
      window = find_by(device_uid:, key_epoch:) or return nil
      return :below_window if frame_counter <= window.floor_fc
      return nil if frame_counter > window.top_fc

      depth = window.top_fc - frame_counter
      return :below_window if depth >= WINDOW

      window.seen[depth] == "1" ? :duplicate : nil
    end

    # DR після відкату БД (06_06 §5.8): кадри, прийняті після точки бекапу, могли вже
    # дати ончейн-мінт, а відновлене вікно їх не памʼятає. Фенс піднімає підлогу на
    # `frames` над відновленим top_fc — FRAMES має перевищувати число кадрів, що дерево
    # могло передати після точки бекапу. Дерево поточної епохи без вікна дістає вікно з
    # підлогою `frames`: його FC після заводського якоря SEC.41 стартує біля нуля.
    # ⚠️ Стеля: дерево, провіжнене до SEC.41 (FC із HRNG) й без жодного кадру до бекапу,
    # фенс не покриває. Ціна — чесні кадри до FC вище підлоги відкидаються.
    # Повертає [піднято, створено].
    def fence!(frames:)
      raise ArgumentError, "frames мусить бути додатним цілим" unless frames.is_a?(Integer) && frames.positive?

      raised = where("floor_fc < top_fc + ?", frames)
               .update_all([ "floor_fc = top_fc + ?, updated_at = now()", frames ])
      missing = HardwareKey.where(device_uid: Tree.select(:did)).where.not(WINDOW_EXISTS_SQL).pluck(:device_uid, :epoch)
      if missing.any?
        now = Time.current
        insert_all(missing.map do |uid, epoch|
          { device_uid: uid, key_epoch: epoch, top_fc: 0, floor_fc: frames, seen: "0" * WINDOW, created_at: now, updated_at: now }
        end)
      end
      [ raised, missing.size ]
    end
  end
end
