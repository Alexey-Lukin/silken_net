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

    SIGMA_MIN = 5.0
    SIGMA_MAX = 30.0
    RHO_MIN   = 10.0
    RHO_MAX   = 50.0

    # [FW.5] β-perturbation від EBFC-метаболізму. Дзеркало
    # app/services/silken_net/attractor.rb#perturb_beta.
    BETA_DELTA_T_COEFF = 0.0001
    BETA_VCAP_COEFF    = 0.001
    BETA_MIN           = 2.0
    BETA_MAX           = 4.0
    BASELINE_DELTA_T_S = 60
    NOMINAL_VCAP_MV    = 3300

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

      local_sigma = SIGMA_MIN if local_sigma < SIGMA_MIN
      local_sigma = SIGMA_MAX if local_sigma > SIGMA_MAX
      local_rho = RHO_MIN if local_rho < RHO_MIN
      local_rho = RHO_MAX if local_rho > RHO_MAX

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
    CRITICAL_Z_MIN = 2.0
    CRITICAL_Z_MAX = 45.0
    OPTIMAL_Z_TARGET = 29.0

    # Sole evaluation entry-point. Returns [payload_byte, x, y, z] —
    # C-side persists the trajectory tail back to RTC DR16-DR18.
    def self.evaluate_and_pack(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s = Attractor::BASELINE_DELTA_T_S, vcap_mv = Attractor::NOMINAL_VCAP_MV)
      z_val, x_final, y_final, z_final = Attractor.calculate_z_axis(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)
      payload_byte = pack_status_byte(z_val)
      [ payload_byte, x_final, y_final, z_final ]
    end

    # Спільна логіка пакування Z → status_byte.
    def self.pack_status_byte(z_val)
      status = 0
      growth_points = 0

      if z_val < CRITICAL_Z_MIN
        status = 1
        growth_points = 1
      elsif z_val > CRITICAL_Z_MAX
        status = 2
        growth_points = 0
      else
        status = 0
        deviation = (OPTIMAL_Z_TARGET - z_val).abs
        reward = 50 - deviation.round
        growth_points = reward.clamp(10, 63)
      end

      growth_points = growth_points.clamp(0, 63)

      # [ Status (2 bits) | Growth Points (6 bits) ]
      (status << 6) | growth_points
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
