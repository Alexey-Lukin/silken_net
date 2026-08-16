# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module SilkenNet
  # =========================================================================
  # 1. МАТЕМАТИЧНЕ ЯДРО (Теорія Хаосу)
  # =========================================================================
  # [SEC.11] After the Lorenz Seed Provenance hard cutover, the
  # attractor has NO concept of `chaos_seed` or DID-derived initial
  # coordinates. The C-side supplies (x₀, y₀, z₀) directly — either:
  #   * (x, y, z) restored from RTC DR16-DR18 (warm STOP2 continuation,
  #     FW.6), or
  #   * (x₀, y₀, z₀) derived on-device from per-device K_seed via
  #     pure-C silken_sha256.h HKDF-SHA256 → HMAC-SHA256 → signed-unit-float unpack
  #     (SEC.11 cold start after VBAT loss).
  # Both branches yield byte-identical (x, y, z) on backend (Ruby) and
  # firmware (mruby) for the same inputs — that is what makes Dual
  # Computation Integrity numerically comparable on top of the
  # categorical bio_status check.
  # =========================================================================
  class Attractor
    BASE_SIGMA = 10.0
    BASE_RHO   = 28.0
    BASE_BETA  = 8.0 / 3.0  # 2.6666666666666665 — bit-identical to backend

    DT = 0.01
    ITERATIONS = 250

    # Межі стабільності (Chaos Clamps) — ідентичні серверу
    # (app/services/silken_net/attractor.rb). Без clamp при екстремальних
    # показниках температури/акустики система вилітає в нескінченність.
    SIGMA_MIN = 5.0
    SIGMA_MAX = 30.0
    RHO_MIN   = 10.0
    RHO_MAX   = 50.0

    # [E.63] β БІЛЬШЕ НЕ збурюється метаболізмом. Раніше [FW.5] мапив
    # delta_t/vcap на β, але β НЕ рухає z-нерухому точку Лоренца
    # (z_eq = ρ−1 залежить від ρ, не від β) → delta_t-сигнал виходив
    # економічно нульовий, а vcap — інвертований (здорове дерево → менше
    # балів). Метаболізм тепер задає growth_points НАПРЯМУ та МОНОТОННО
    # (BioContract.metabolic_health); Лоренц лишається чистим хаос-детектором
    # стану. Емпіричний присуд + докази — 00_07 E.63 / 03_04.
    # BASELINE_DELTA_T_S / NOMINAL_VCAP_MV лишаються лише як default-аргументи
    # сигнатур (C-bridge передає 7 аргументів); на Z вони більше не впливають.
    BASELINE_DELTA_T_S = 60
    NOMINAL_VCAP_MV    = 3300

    # [ARCH.102] «Метаболізм не виміряно» — окремий СТАН, не число. Нуль секунд
    # між пробудженнями не є інтервалом перезаряду в жодному прочитанні (ні як
    # вимір, ні як фізика), тож він вільний під сентинел і не забирає жодного
    # досяжного значення. Guard-и `wall_time.h` (cold-start · зсув годинника
    # назад · стрибок епохи · HAL-збій) і непрогріта EMA віддають САМЕ його.
    #
    # 🔴 Чому це несуче: доти ті ж гілки віддавали `BASELINE_DELTA_T_S = 60`,
    # поданий як «нейтральний», — а `metabolic_health(60)` = 1.08 → clamp 1.0 →
    # `growth_points = GP_HOMEO_MAX`. Тобто відмова виміряти мінтила МАКСИМУМ,
    # і на кремнії це не крайній випадок: `Wall_Seconds_Now()` повертає 0 до
    # LSE/RTC bring-up (FW.49), отже cold-start-гілка спрацьовує щоцикла.
    DELTA_T_UNKNOWN_S  = 0

    # Sole entry-point: takes initial (x, y, z) directly. Returns
    # [z, x_final, y_final, z_final] for RTC persistence. [E.63] Чистий
    # хаос — без delta_t/vcap (метаболізм перенесено у growth_points).
    def self.calculate_z_axis(x_prev, y_prev, z_prev, temp, acoustic)
      x, y, z = iterate(x_prev, y_prev, z_prev, temp, acoustic)
      [ z, x, y, z ]
    end

    # Спільне ядро ітерацій Лоренца. β = BASE_BETA (фіксований).
    def self.iterate(x, y, z, temp, acoustic)
      local_sigma = BASE_SIGMA + (acoustic * 0.1)
      local_rho   = BASE_RHO + (temp * 0.2)

      # [FIX: Attractor Sync] Clamp — запобігаємо вибуху при екстремальних вхідних
      local_sigma = SIGMA_MIN if local_sigma < SIGMA_MIN
      local_sigma = SIGMA_MAX if local_sigma > SIGMA_MAX
      local_rho = RHO_MIN if local_rho < RHO_MIN
      local_rho = RHO_MAX if local_rho > RHO_MAX

      ITERATIONS.times do
        dx = local_sigma * (y - x)
        dy = x * (local_rho - z) - y
        dz = (x * y) - (BASE_BETA * z)

        x += dx * DT
        y += dy * DT
        z += dz * DT
      end

      [ x, y, z ]
    end
  end

  # =========================================================================
  # 2. ЛОГІКА ПРИЙНЯТТЯ РІШЕНЬ ТА ТОКЕНОМІКА (Біо-Контракт)
  # =========================================================================
  class BioContract
    CRITICAL_Z_MIN = 2.0   # Падіння нижче = втрата тургору / посуха
    CRITICAL_Z_MAX = 45.0  # Стрибок вище = аномальний стрес / втручання
    # Здоровий центр атрактора — використовується для інсайтів/інтерпретації
    # статусу. [E.63] БІЛЬШЕ не входить у формулу growth_points (та була
    # хаотичним шумом, не сигналом).
    OPTIMAL_Z_TARGET = 29.0

    # [E.63] Метаболічна винагорода: швидкість перезаряду EBFC (delta_t) →
    # growth_points, МОНОТОННО і у польовому масштабі. Лоренц лише гейтить
    # статус (стрес / аномалія / гомеостаз); у гомеостазі магнітуда балів =
    # метаболічна жвавість m(delta_t), а не |OPTIMAL−Z| (хаотичний шум).
    # Калібрувальні пороги — placeholder, чекають bench recharge-кривої
    # (firmware/scripts/bench/RUNBOOK.md §3.3 / 00_07 E.63); фінал —
    # per-deployment/species, не хардкод.
    DELTA_T_FAST_S = 600     # ≤ цього → пік жвавості (m = 1.0)
    DELTA_T_SLOW_S = 7200    # ≥ цього → мінімум (m = 0.0)
    GP_HOMEO_MIN   = 5       # 5-бітний wire-діапазон гомеостазу (FW.29-PACK)
    GP_HOMEO_MAX   = 31

    # Монотонна метаболічна жвавість ∈ [0.0, 1.0]: швидший перезаряд → вище.
    def self.metabolic_health(delta_t_s)
      m = (DELTA_T_SLOW_S - delta_t_s).to_f / (DELTA_T_SLOW_S - DELTA_T_FAST_S)
      m = 0.0 if m < 0.0
      m = 1.0 if m > 1.0
      m
    end

    # Sole evaluation entry-point. Returns [payload_byte, x, y, z] —
    # C-side persists the trajectory tail back to RTC DR16-DR18.
    def self.evaluate_and_pack(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s = Attractor::BASELINE_DELTA_T_S, vcap_mv = Attractor::NOMINAL_VCAP_MV)
      _ = vcap_mv  # [E.63] vcap прибрано з винагороди (FW.50 raw-ADC); reserved
      z_val, x_final, y_final, z_final = Attractor.calculate_z_axis(x_prev, y_prev, z_prev, temp, acoustic)
      # [E.64] ρ для ρ-відносної anomaly — той самий вираз і clamp, що в Attractor.iterate
      # (DCI: backend рахує ідентично з temp у пакеті).
      local_rho = Attractor::BASE_RHO + (temp * 0.2)
      local_rho = Attractor::RHO_MIN if local_rho < Attractor::RHO_MIN
      local_rho = Attractor::RHO_MAX if local_rho > Attractor::RHO_MAX
      payload_byte = pack_status_byte(z_val, delta_t_s, local_rho)
      [ payload_byte, x_final, y_final, z_final ]
    end

    # [FW.29-PACK] Z → status (Лоренц-гейт), delta_t → growth_points (метаболізм).
    # Wire-формат байту 10: [PanicFlag:1 (bit 7) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)].
    # PanicFlag заповнюється C-side; нормальні пакети завжди роблять
    # `lora_payload[10] &= ~PANIC_FLAG_BIT`. Тому pack_status_byte НІКОЛИ не
    # ставить bit 7 — status (2 біти) у bits 6..5, growth_points (5 біт) у 4..0.
    def self.pack_status_byte(z_val, delta_t_s = Attractor::BASELINE_DELTA_T_S, local_rho = Attractor::BASE_RHO)
      # [E.64] Аномалія — ρ-ВІДНОСНА: z поза temp-очікуваною обвідною. Поріг
      # anomaly_ceiling = ρ + (CRITICAL_Z_MAX − BASE_RHO) (offset 17 → зберігає 45 при
      # ρ=28). Раніше absolute z>45 → теплий день (високий z_eq=ρ−1) хибно тригерив
      # anomaly й обнуляв growth_points. Присуд + докази — 00_07 E.64. Stress (колапс
      # конвекції до ~origin) лишається absolute (z<2) — справжній зрив, рідкісний.
      anomaly_ceiling = local_rho + (CRITICAL_Z_MAX - Attractor::BASE_RHO)
      if z_val < CRITICAL_Z_MIN
        status = 1            # Раннє попередження (посуха / втрата тургору / колапс)
        growth_points = 1     # Мінімальна генерація — дерево виживає
      elsif z_val > anomaly_ceiling
        status = 2            # Аномалія (вихід за temp-обвідну — справжній зрив)
        growth_points = 0     # Емісія зупиняється
      elsif delta_t_s == Attractor::DELTA_T_UNKNOWN_S
        # [ARCH.102] Гомеостаз ВИМІРЯНО (Лоренц-гейт відпрацював на живих
        # temp/acoustic), а метаболізм — НІ. Емісія без доказу росту не
        # нараховується: `growth_points = 0` при `status = 0` — вільна пара,
        # бо виміряний гомеостаз починається з `GP_HOMEO_MIN`, а нуль у полі
        # балів доти належав лише аномалії (`status = 2`). Тож бекенд і людина
        # розрізняють «зрив» від «не міряли» за СТАТУСОМ, не за балами.
        status = 0
        growth_points = 0
      else
        status = 0            # Гомеостаз (здоровий хаос)
        # [E.63] growth_points = метаболічна жвавість (швидкість перезаряду),
        # монотонно: швидший перезаряд → більше балів. 5-бітний wire (5..31).
        m = metabolic_health(delta_t_s)
        growth_points = (GP_HOMEO_MIN + (m * (GP_HOMEO_MAX - GP_HOMEO_MIN))).round
        growth_points = GP_HOMEO_MIN if growth_points < GP_HOMEO_MIN
        growth_points = GP_HOMEO_MAX if growth_points > GP_HOMEO_MAX
      end

      # Захист від переповнення для 5-бітного wire-простору (максимум 31).
      growth_points = 0 if growth_points < 0
      growth_points = 31 if growth_points > 31

      (status << 5) | growth_points
    end
  end
end

# =========================================================================
# 3. ТОЧКА ВХОДУ (Міст між C та Ruby)
# =========================================================================
# [SEC.11] Sole entry-point. C-side passes (x, y, z) — either restored
# from RTC DR16-DR18 (FW.6 warm continuation) or freshly derived from
# K_seed via pure-C silken_sha256.h HKDF/HMAC (SEC.11 cold start). Returns
# [payload_byte, x_final, y_final, z_final] for RTC persistence.
# delta_t_s → growth_points (метаболізм, E.63); vcap_mv reserved.
def calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s = SilkenNet::Attractor::BASELINE_DELTA_T_S, vcap_mv = SilkenNet::Attractor::NOMINAL_VCAP_MV)
  SilkenNet::BioContract.evaluate_and_pack(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)
end
