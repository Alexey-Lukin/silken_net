# frozen_string_literal: true

module SilkenNet
  # Lorenz attractor — server-side mirror of firmware/bio_contracts/bio_contract.rb.
  #
  # [SEC.11] After the seed-provenance hard cutover, the attractor has
  # NO concept of `chaos_seed` or DID-derived initial coordinates. The
  # caller (TelemetryUnpackerService) supplies (x₀, y₀, z₀) directly,
  # derived from per-device K_seed via SilkenNet::SeedDerivation. This
  # is what makes Dual Computation Integrity numerically comparable
  # between server-Z and device-Z — both sides start from byte-identical
  # initial coordinates and run the same iteration kernel.
  class Attractor
    # [FIX FW.7] Float (IEEE 754 double) — bit-identical to firmware mruby.
    # BigDecimal давав "юридичну точність", але РІЗНУ від firmware: після 250 ітерацій
    # хаотичного Лоренца Z-значення розходились на десятки одиниць.
    # Dual Computation Integrity вимагає ОДНАКОВОЇ математики на обох сторонах.
    # Фінансові розрахунки (growth_points → SCC мінтинг) виконуються ПІСЛЯ верифікації Z.
    BASE_SIGMA = 10.0
    BASE_RHO   = 28.0
    BASE_BETA  = 8.0 / 3.0  # IEEE 754: 2.6666666666666665 — ідентично firmware

    DT = 0.01
    ITERATIONS = 250

    # Межі стабільності (Chaos Clamps) — захищають σ/ρ від "вибуху"
    # при екстремальних температурах/акустиці.
    SIGMA_LIMITS = (5.0..30.0)
    RHO_LIMITS   = (10.0..50.0)

    # [E.63] β БІЛЬШЕ НЕ збурюється метаболізмом (раніше [FW.5] perturb_beta).
    # β не рухає z-нерухому точку Лоренца (z_eq = ρ−1) → delta_t-сигнал виходив
    # економічно нульовий, vcap — інвертований. Метаболізм тепер задає
    # growth_points НАПРЯМУ на пристрої (firmware BioContract.metabolic_health);
    # backend декодує wire growth_points у TelemetryUnpackerService
    # (`(status_byte & 0x1F) * 2`). Лоренц тут — чистий хаос для DCI: server-Z
    # та device-Z обидва на β=BASE_BETA → категоричний check_z_divergence!
    # лишається валідним. delta_t_s/vcap_mv приймаються лише для сумісності
    # викликів — на Z більше не впливають. Присуд — 00_07 E.63.
    BASELINE_DELTA_T_S = 60
    NOMINAL_VCAP_MV    = 3300

    # [SEC.11] Sole entry-point for Z-axis computation. Both branches —
    # cold start (initial coords from K_seed via SilkenNet::SeedDerivation)
    # and warm continuation (initial coords = previous TelemetryLog tail)
    # — call this method. Returns [z_rounded, x_final, y_final, z_final]
    # so the caller can persist the trajectory tail to
    # `TelemetryLog.lorenz_state_*`.
    def self.calculate_z_from_state(x0, y0, z0, temp, acoustic, delta_t_s = BASELINE_DELTA_T_S, vcap_mv = NOMINAL_VCAP_MV)
      _ = [ delta_t_s, vcap_mv ]  # [E.63] no longer affect Z (kept for call-compat)
      start_time  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # [FIX] Coerce all inputs to Float — DeviceCalibration returns
      # BigDecimal from the DB, and a single BigDecimal operand infects
      # every multiplication in the Lorenz loop with arbitrary-precision
      # arithmetic (exponential precision growth → apparent hang).
      temp_f      = temp.to_f
      acoustic_f  = acoustic.to_f
      local_sigma = (BASE_SIGMA + (acoustic_f * 0.1)).clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)
      local_rho   = (BASE_RHO + (temp_f * 0.2)).clamp(RHO_LIMITS.min, RHO_LIMITS.max)

      x, y, z = iterate_lorenz(x0.to_f, y0.to_f, z0.to_f, local_sigma, local_rho, BASE_BETA)

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      SilkenNet::Metrics::LORENZ_COMPUTATION_DURATION.observe(duration) if defined?(SilkenNet::Metrics)

      [ z.round(4), x, y, z ]
    end

    def self.homeostatic?(z_value, tree_family)
      z_value.between?(tree_family.critical_z_min, tree_family.critical_z_max)
    end

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # ВІЗУАЛІЗАЦІЯ ТРАЄКТОРІЇ
    # [ОПТИМІЗАЦІЯ ПАМ'ЯТІ] Плаский Float-масив [x1,y1,z1,x2,y2,z2,...]
    # ідеальний для Float32Array у JavaScript (Three.js/Deck.gl).
    # [SEC.11] Caller supplies (x₀, y₀, z₀) from K_seed-derived coords —
    # there is no DID-as-seed shortcut.
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    def self.generate_trajectory(x0, y0, z0, temp, acoustic, delta_t_s = BASELINE_DELTA_T_S, vcap_mv = NOMINAL_VCAP_MV)
      _ = [ delta_t_s, vcap_mv ]  # [E.63] no longer affect Z
      x = x0.to_f
      y = y0.to_f
      z = z0.to_f
      local_sigma = (BASE_SIGMA + (acoustic.to_f * 0.1)).clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)
      local_rho   = (BASE_RHO + (temp.to_f * 0.2)).clamp(RHO_LIMITS.min, RHO_LIMITS.max)

      Array.new(ITERATIONS * 3) do |i|
        if i % 3 == 0 && i > 0
          dx = local_sigma * (y - x)
          dy = x * (local_rho - z) - y
          dz = (x * y) - (BASE_BETA * z)

          x += dx * DT
          y += dy * DT
          z += dz * DT
        end

        case i % 3
        when 0 then x.round(4)
        when 1 then y.round(4)
        when 2 then z.round(4)
        end
      end
    end

    # Спільне ядро ітерацій Лоренца.
    # [FIX FW.7] Float арифметика без round() між ітераціями — ідентично firmware mruby.
    # mruby на MCU виконує x += dx * DT без будь-якого округлення між ітераціями.
    # Overflow bounded: з clamped σ∈[5,30] та ρ∈[10,50] → |x|<25, |y|<35, |z|<50
    # після 250 ітерацій — далеко від Float64 overflow.
    private_class_method def self.iterate_lorenz(x, y, z, local_sigma, local_rho, local_beta)
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
end
