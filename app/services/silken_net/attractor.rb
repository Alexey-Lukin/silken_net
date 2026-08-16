# SPDX-License-Identifier: AGPL-3.0-or-later
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

    # [E.63/E.64] growth_points wire-band guaranteed by firmware pack_status_byte
    # (bio_contracts/bio_contract.rb) — mirrored here for the stateless conformance
    # check TelemetryUnpackerService#check_metabolic_divergence!: homeostasis →
    # GP ∈ [GP_HOMEO_MIN, GP_HOMEO_MAX]; stress → GP_STRESS.
    # [E.63 (г), wire-rev2.1 2026-07-03] The wire now ALSO carries the
    # EMA-smoothed delta_t — the exact number metabolic_health consumed on
    # the device (contract «wire = GP input») → the exact stateless recompute
    # below (expected_homeostasis_gp) is possible; it stays OBSERVATIONAL
    # (warn+metric, no gate) until the bench calibrates the placeholder
    # thresholds. Raw dT keeps riding bytes 12..13 for diagnostics (03_01 §13.6).
    GP_HOMEO_MIN = 5
    GP_HOMEO_MAX = 31
    GP_STRESS    = 1

    # [E.63 (г)] Byte-identical mirror of firmware BioContract.metabolic_health →
    # growth_points quantization (bio_contract.rb §4.3 — the One-Home of the
    # formula and the calibration-pending thresholds; edit THERE first).
    DELTA_T_FAST_S = 600
    DELTA_T_SLOW_S = 7200

    # [ARCH.102] «Метаболізм не виміряно» — сентинел, не число (дім значення й
    # підстави — `bio_contract.rb`). Пристрій віддає його, коли guard'и wall-time
    # спрацювали або EMA ще не прогрілась; тоді при `status = 0` на дроті стоїть
    # `growth_points = 0`. Дзеркало мусить давати ТЕ САМЕ, інакше DCI-звірка
    # оголосила б розходженням якраз чесну відмову.
    DELTA_T_UNKNOWN_S = 0

    def self.expected_homeostasis_gp(ema_delta_t_s)
      return 0 if ema_delta_t_s == DELTA_T_UNKNOWN_S

      m  = (DELTA_T_SLOW_S - ema_delta_t_s).to_f / (DELTA_T_SLOW_S - DELTA_T_FAST_S)
      m  = m.clamp(0.0, 1.0)
      gp = (GP_HOMEO_MIN + (m * (GP_HOMEO_MAX - GP_HOMEO_MIN))).round
      gp.clamp(GP_HOMEO_MIN, GP_HOMEO_MAX)
    end

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

    # [E.64] ρ-відносна верхня межа аномалії: ceiling = ρ(temp) + (critical_z_max − BASE_RHO).
    # Зберігає absolute critical_z_max при ρ=BASE_RHO; ambient-temp більше НЕ тригерить
    # хибну аномалію (дзеркало firmware bio_contract.rb pack_status_byte). Присуд — 00_07 E.64.
    def self.anomaly_ceiling(temp, critical_z_max)
      rho = (BASE_RHO + temp.to_f * 0.2).clamp(RHO_LIMITS.min, RHO_LIMITS.max)
      rho + (critical_z_max.to_f - BASE_RHO)
    end

    # [E.64] homeostasis = вище stress-підлоги (absolute critical_z_min) і нижче
    # ρ-відносної anomaly-стелі. `temp` обов'язковий (потрібен для ρ).
    def self.homeostatic?(z_value, tree_family, temp)
      z_value >= tree_family.critical_z_min &&
        z_value <= anomaly_ceiling(temp, tree_family.critical_z_max)
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
