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
  #     mbedTLS HKDF-SHA256 → HMAC-SHA256 → signed-unit-float unpack
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

    # [FW.5] β-perturbation від EBFC-метаболізму. Дзеркало
    # app/services/silken_net/attractor.rb#perturb_beta.
    # delta_t (час заряду іоністора) та vcap (напруга) — фізично значущі
    # індикатори здоров'я дерева. Мапимо їх на β (геометричний параметр
    # конвективної клітини у системі Лоренца): швидший заряд + стабільна
    # vcap → активніший метаболізм → β зростає → траєкторія тяжіє до
    # OPTIMAL_Z_TARGET → більше growth_points.
    BETA_DELTA_T_COEFF = 0.0001  # 1 с швидше за baseline → β +0.0001
    BETA_VCAP_COEFF    = 0.001   # 1 mV вище nominal → β +0.001
    BETA_MIN           = 2.0     # clamp: класичний β ≈ 2.667 ± 50%
    BETA_MAX           = 4.0
    BASELINE_DELTA_T_S = 60      # очікуваний час заряду EBFC, секунди
    NOMINAL_VCAP_MV    = 3300    # 3.3 V nominal

    # Sole entry-point: takes initial (x, y, z) directly. Returns
    # [z, x_final, y_final, z_final] for RTC persistence.
    def self.calculate_z_axis(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s = BASELINE_DELTA_T_S, vcap_mv = NOMINAL_VCAP_MV)
      x, y, z = iterate(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)
      [ z, x, y, z ]
    end

    # Спільне ядро ітерацій Лоренца.
    def self.iterate(x, y, z, temp, acoustic, delta_t_s, vcap_mv)
      local_sigma = BASE_SIGMA + (acoustic * 0.1)
      local_rho   = BASE_RHO + (temp * 0.2)

      # [FIX: Attractor Sync] Clamp — запобігаємо вибуху при екстремальних вхідних
      local_sigma = SIGMA_MIN if local_sigma < SIGMA_MIN
      local_sigma = SIGMA_MAX if local_sigma > SIGMA_MAX
      local_rho = RHO_MIN if local_rho < RHO_MIN
      local_rho = RHO_MAX if local_rho > RHO_MAX

      # [FW.5] Лише позитивний внесок delta_t: чим швидше за baseline → тим більше β.
      # vcap_centered може бути від'ємним при просадці — від β-зменшення захищає clamp.
      delta_t_improvement_s = BASELINE_DELTA_T_S - delta_t_s
      delta_t_improvement_s = 0 if delta_t_improvement_s < 0
      vcap_centered = vcap_mv - NOMINAL_VCAP_MV

      local_beta = BASE_BETA + (delta_t_improvement_s * BETA_DELTA_T_COEFF) +
                               (vcap_centered * BETA_VCAP_COEFF)
      local_beta = BETA_MIN if local_beta < BETA_MIN
      local_beta = BETA_MAX if local_beta > BETA_MAX

      ITERATIONS.times do
        dx = local_sigma * (y - x)
        dy = x * (local_rho - z) - y
        dz = (x * y) - (local_beta * z)

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
    OPTIMAL_Z_TARGET = 29.0  # Ідеальний стан конвекції — максимальне поглинання CO2

    # Sole evaluation entry-point. Returns [payload_byte, x, y, z] —
    # C-side persists the trajectory tail back to RTC DR16-DR18.
    def self.evaluate_and_pack(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s = Attractor::BASELINE_DELTA_T_S, vcap_mv = Attractor::NOMINAL_VCAP_MV)
      z_val, x_final, y_final, z_final = Attractor.calculate_z_axis(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)
      payload_byte = pack_status_byte(z_val)
      [ payload_byte, x_final, y_final, z_final ]
    end

    # [FW.29-PACK] Спільна логіка пакування Z → status_byte.
    # Wire-формат байту 10: [PanicFlag:1 (bit 7) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)].
    # PanicFlag заповнюється C-side (firmware/soldier/main.c), а нормальні
    # пакети завжди виконують `lora_payload[10] &= ~PANIC_FLAG_BIT`. Тому
    # mruby тут гарантує, що pack_status_byte НІКОЛИ не встановлює bit 7 —
    # status (2 біти) лежить у bits 6..5, growth_points (5 біт) — у bits 4..0.
    # До FW.29-PACK status паковано як `<< 6` → bit 7 status'у конфліктував
    # з PANIC_FLAG_BIT mask'ом і status=2 (anomaly) / status=3 (tamper) тихо
    # деградували до homeostasis / stress на бекенді.
    def self.pack_status_byte(z_val)
      status = 0
      growth_points = 0  # Бали росту (Proof of Growth)

      if z_val < CRITICAL_Z_MIN
        status = 1  # Сигнал раннього попередження (посуха / втрата тургору)
        growth_points = 1  # Мінімальна генерація — дерево виживає
      elsif z_val > CRITICAL_Z_MAX
        status = 2  # Аномалія (критичний стрес)
        growth_points = 0  # Емісія зупиняється
      else
        status = 0  # Гомеостаз (здоровий хаос)
        deviation = (OPTIMAL_Z_TARGET - z_val).abs
        # Базова нагорода 50 балів мінус штраф за відхилення від OPTIMAL_Z_TARGET.
        # [FIX FW.13] Explicit clamp замість окремих guard'ів.
        # [FW.29-PACK] Перейшли з 6-бітного wire-діапазону (10..63) на 5-бітний
        # (5..31): значення масштабоване ÷2 щоб зберегти приблизно ту ж саму
        # tokenomic емісію після backend ×2 upscale (effective stored 10..62
        # vs old 10..63 — <2% resolution loss).
        reward = 50 - deviation.round
        growth_points = (reward / 2).clamp(5, 31)
      end

      # Захист від переповнення для 5-бітного wire-простору (максимум 31).
      growth_points = growth_points.clamp(0, 31)

      # [PanicFlag:1 (bit 7, 0 у нормальному пакеті) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)]
      (status << 5) | growth_points
    end
  end
end

# =========================================================================
# 3. ТОЧКА ВХОДУ (Міст між C та Ruby)
# =========================================================================
# [SEC.11] Sole entry-point. C-side passes (x, y, z) — either restored
# from RTC DR16-DR18 (FW.6 warm continuation) or freshly derived from
# K_seed via mbedTLS HKDF/HMAC (SEC.11 cold start). Returns
# [payload_byte, x_final, y_final, z_final] for RTC persistence.
def calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s = SilkenNet::Attractor::BASELINE_DELTA_T_S, vcap_mv = SilkenNet::Attractor::NOMINAL_VCAP_MV)
  SilkenNet::BioContract.evaluate_and_pack(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)
end
