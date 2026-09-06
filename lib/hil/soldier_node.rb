# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Hil
  # = ===================================================================
  # 🌳 HilSoldierNode — Soldier HIL Digital Twin (Lorenz chain + StatusByte)
  # = ===================================================================
  #
  # Source: 00_03 §3.2 (HIL/SIL simulator registry). Sibling of
  # `Hil::QueenSimulator` (envelope/pulse twin) — this one is the LEAF:
  # what a provisioned Soldier computes before it hands bytes to the Queen.
  #
  # 🔴 [E.64] ЧОМУ ЦЕЙ КЛАС ІСНУЄ. `bin/forest_simulator` брав
  # `bio_status = rand(0..3)` і `growth_points = rand(0..31)` — тобто сторона,
  # яку Dual Computation Integrity звіряє з серверним Z, ГЕНЕРУВАЛАСЬ. Вона не
  # сходиться НІКОЛИ, тож перший multi-node прогін на canopy 2026-09-05 запалив
  # критичний `Telemetry fraud detected`, і алерт був істинно-позитивним:
  # «шахраєм» був наш власний симулятор. Уся суть DCI — що зійшлися ДВА
  # обчислення; сторона з `rand` не доводить печатку, а спростовує її за
  # побудовою, тож жоден обсяг прогонів цю вісь не закриє.
  #
  # ЯК ВУЗОЛ РАХУЄ (дзеркало firmware/bio_contracts/bio_contract.rb):
  #   • cold start — (x₀,y₀,z₀) з per-device `K_seed` через
  #     `SilkenNet::SeedDerivation.initial_state(seed, epoch_day)`. Доба береться
  #     з МОМЕНТУ ПРИЙОМУ тим самим виразом, що в
  #     `TelemetryUnpackerService#derivation_epoch_day` (`ts.utc.to_i / 86_400`);
  #     розбіжність тут дала б інший стартовий стан і категоричний DCI-мисматч на
  #     чесному вузлі — рівно клас, який уже коштував нам ARCH.41.
  #   • warm continuation — хвіст ВЛАСНОЇ попередньої траєкторії, як прошивка тягне
  #     його з RTC DR16-DR18. Прошивка вирішує cold-start ВИКЛЮЧНО за маркером
  #     `DR19 == LORENZ_STATE_MAGIC`, без часової компоненти — тому й тут ланцюг не
  #     має вікна давності.
  #
  # 🔑 ЧОМУ ВЛАСНИЙ ЛАНЦЮГ, А НЕ ЧИТАННЯ СЕРВЕРНОГО ХВОСТА з `telemetry_logs`:
  # симулятор, який питає в сервера його ж число, дає зелене за побудовою — та сама
  # беззмістовність, лише протилежного знаку до `rand`. З власним ланцюгом розрив
  # саме в СЕРВЕРНОМУ продовженні (промах партиційного прунінгу, хибний
  # `cold_start_flag`, порушений порядок) чесно почервоніє.
  #
  # ⚠️ ОГОЛОШЕНА СТЕЛЯ ×3 — читай як специфікацію того, чого цей клас НЕ доводить.
  #   (1) Не незалежність ОБЧИСЛЕНЬ: обидві сторони крутять `SilkenNet::Attractor`,
  #       тож доводиться ТРАКТ (пакування → шифр → транспорт → розпакування →
  #       продовження стану → звірка), а не байт-парність із кремнієм. Останню
  #       тримають ІНШІ гейти — 200-кейсовий sweep проти СПРАВЖНЬОГО контракту
  #       (`spec/services/silken_net/attractor_spec.rb` через
  #       `tools/firmware/contract_runner.rb`) і FW.55 QEMU byte-parity.
  #       ⛔ Той міст сюди не переноситься: `firmware/bio_contracts/bio_contract.rb`
  #       перевизначає `SilkenNet::Attractor` у тому ж процесі, а `/firmware` і
  #       `/tools` свідомо не їдуть у Docker-образ (`.dockerignore`, OPS.10) — тобто
  #       на canopy, де симулятор і біжить, того файлу фізично немає.
  #   (2) Ланцюг припускає ПОРЯДОК пакетів на дерево. Пауза між батчами в
  #       `bin/forest_simulator` (3..8 с) на порядки більша за час розпакування, тож
  #       на практиці порядок тримається — і рівно ту саму передумову має справжній
  #       флот, тож це властивість тракту, не артефакт емуляції.
  #   (3) Пороги тут ПРИСТРОЄВІ (`Tree::GLOBAL_LORENZ_Z_MIN/MAX` = 2.0/45.0), а не
  #       per-species: прошивку per-species значеннями не провіжинять, і
  #       `check_z_divergence!` судить саме за пристроєвою смугою [FW.8].
  #
  # Cross-ref:
  #   - docs/03_04 §4 (Z → status), §5.2 (потік верифікації)
  #   - app/services/silken_net/attractor.rb#pack_status_byte (дзеркало формули)
  #   - app/services/telemetry_unpacker_service.rb#compute_server_z (серверний бік)
  # = ===================================================================
  class SoldierNode
    # Один кадр так, як його бачить пристрій ПЕРЕД пакуванням у wire.
    Reading = Data.define(:status_byte, :bio_status, :growth_points, :z, :cold_start)

    class MissingSeedError < StandardError; end

    def initialize
      @tails = {}
    end

    # Скільки DID-ів вузол уже веде (тобто має теплий ланцюг).
    def tracked_count = @tails.size

    def cold?(did) = !@tails.key?(did)

    # Обчислює кадр і РУХАЄ ланцюг. `received_at` мусить бути тим самим моментом,
    # який поїде в `UnpackTelemetryWorker` — з нього деривується `epoch_day`
    # cold-start'у, і розходження тут ламає DCI на чесному вузлі (ARCH.41).
    #
    # `strict:` — форма відмови при непровіженому дереві. `true` (дефолт) кидає:
    # вузла без `K_seed` не існує за SEC.11, і тиха підстановка чого завгодно тут
    # була б фабрикацією. `false` віддає `nil` для батч-циклів, які мусять пережити
    # одне погане дерево, не ховаючи його — викликач ЗОБОВʼЯЗАНИЙ сказати вголос.
    def read(tree, temperature_c:, acoustic:, metabolism_s:, voltage_mv:,
             received_at: Time.now.utc, strict: true)
      seed = tree.hardware_key&.binary_lorenz_seed
      if seed.nil?
        raise MissingSeedError, "Tree #{tree.did} has no provisioned K_seed (SEC.11)" if strict

        return nil
      end

      cold = cold?(tree.did)
      x0, y0, z0 = @tails[tree.did] || restore_rtc(tree) ||
                   SilkenNet::SeedDerivation.initial_state(seed, received_at.utc.to_i / 86_400)

      # `[3]` — СИРИЙ фінальний Z. Прошивка класифікує саме ним
      # (`calculate_z_axis` → `[z, x, y, z]`, без round); `[0]` округлений до 4 знаків
      # і йде в `telemetry_logs.z_value`, тобто це РІЗНІ числа на межі смуги.
      _z_rounded, x_f, y_f, z_f = SilkenNet::Attractor.calculate_z_from_state(
        x0, y0, z0, temperature_c, acoustic, metabolism_s, voltage_mv
      )
      @tails[tree.did] = [ x_f, y_f, z_f ]

      status_byte = SilkenNet::Attractor.pack_status_byte(
        z_f, temperature_c, metabolism_s,
        critical_z_min: Tree::GLOBAL_LORENZ_Z_MIN,
        critical_z_max: Tree::GLOBAL_LORENZ_Z_MAX
      )

      Reading.new(
        status_byte: status_byte,
        bio_status: (status_byte >> 5) & 0x03,
        growth_points: status_byte & 0x1F,
        z: z_f,
        cold_start: cold
      )
    end

    private

    # 🔴 [E.64, 2026-09-06] ВІДНОВЛЕННЯ «RTC» ДВІЙНИКА — знайдено ЖИВИМ СЛОТОМ, не аналізом.
    #
    # Ланцюг цього класу живе в памʼяті ПРОЦЕСУ, а RTC справжнього Солдата переживає
    # перезавантаження (`DR19 == LORENZ_STATE_MAGIC`, без часової компоненти). Тож
    # ПЕРЕЗАПУСК СИМУЛЯТОРА — артефакт емуляції, а не подія пристрою: без цього методу
    # вузол cold-стартував із `K_seed`, тоді як сервер мав хвіст попереднього прогону й
    # продовжував ТЕПЛО — два різні `(x,y,z)`, категоричний DCI-mismatch на ЧЕСНОМУ
    # дереві. Виміряно на canopy: `time_unsynced_fallback = 2` на 147 рядків, і кожен
    # такий кадр ще й ставив `TimeSyncDownlinkWorker`, який ретраївся в Королеву, якої
    # на canopy немає за конструкцією.
    #
    # 🔑 РОЗРІЗНЕННЯ, ЯКЕ ТУТ НЕСУЧЕ — і воно не те, що здається на перший погляд:
    # читати серверний хвіст на КОЖНОМУ пакеті означало б циркулярність (сторона, яку
    # DCI звіряє, годується з того самого джерела — зелене за побудовою). Читати його
    # ОДИН РАЗ на процес — це відновлення памʼяті двійника, бо серверний хвіст і є
    # записом того самого стану RTC. Далі ланцюг знову незалежний, і розрив у
    # СЕРВЕРНОМУ продовженні чесно почервоніє.
    #
    # ⚠️ ОГОЛОШЕНА СТЕЛЯ: перший кадр на дерево після рестарту процесу ПРОДОВЖЕННЯ НЕ
    # ДОВОДИТЬ — він узгоджений за побудовою. Це вакуумно, але чесно; доти було
    # хибно-червоно, що гірше. Форма запиту дзеркалить `previous_lorenz_state_for`
    # (найновіший рядок із трьома НЕ-nil координатами), бо емулюємо ту саму памʼять.
    def restore_rtc(tree)
      row = tree.telemetry_logs
                .where.not(lorenz_state_x: nil, lorenz_state_y: nil, lorenz_state_z: nil) # rubocop:disable Rails/WhereNotWithMultipleConditions
                .order(created_at: :desc)
                .limit(1)
                .pluck(:lorenz_state_x, :lorenz_state_y, :lorenz_state_z)
                .first
      return nil if row.nil? || row.any? { |v| v.nil? || !v.finite? }

      row
    end
  end
end
