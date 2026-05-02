# frozen_string_literal: true

module SilkenNet
  class Attractor
    # [FIX FW.7]: Використовуємо Float (IEEE 754 double) — ІДЕНТИЧНО firmware (mruby).
    # BigDecimal давав "юридичну точність", але РІЗНУ від firmware — після 250 ітерацій
    # хаотичної системи Лоренца Z-значення розходились на десятки одиниць.
    # Dual Computation Integrity вимагає ОДНАКОВОЇ математики на обох сторонах.
    # Фінансові розрахунки (growth_points → SCC мінтинг) виконуються ПІСЛЯ верифікації Z.
    BASE_SIGMA = 10.0
    BASE_RHO   = 28.0
    BASE_BETA  = 8.0 / 3.0  # IEEE 754: 2.6666666666666665 — ідентично firmware

    DT = 0.01
    ITERATIONS = 250

    # МЕЖІ СТАБІЛЬНОСТІ (Chaos Clamps):
    # Захищаємо систему від "вибуху" при екстремальних температурах.
    SIGMA_LIMITS = (5.0..30.0)
    RHO_LIMITS   = (10.0..50.0)

    # [FW.5] β-perturbation від EBFC-метаболізму. Дзеркало firmware/bio_contracts/bio_contract.rb.
    # delta_t (час заряду іоністора, секунди) та vcap (mV після калібрування) —
    # фізично значущі індикатори здоров'я. Мапимо їх на β (геометричний параметр
    # конвективної клітини): швидший заряд + стабільна vcap → активніший
    # метаболізм → β зростає → Z тяжіє до OPTIMAL_Z_TARGET → більше GP.
    BETA_DELTA_T_COEFF = 0.0001  # 1 с швидше за baseline → β +0.0001
    BETA_VCAP_COEFF    = 0.001   # 1 mV вище nominal → β +0.001
    BETA_LIMITS        = (2.0..4.0)
    BASELINE_DELTA_T_S = 60      # 60 с очікуваний час заряду EBFC
    NOMINAL_VCAP_MV    = 3300    # 3.3 V nominal

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # МЕТОД ДЛЯ БЕКЕНДУ (Розрахунок стабільності)
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # [FW.5] delta_t_s і vcap_mv опціональні; коли не передані — β = BASE_BETA
    # (історична поведінка). TelemetryUnpackerService завжди передає реальні значення.
    def self.calculate_z(seed, temp, acoustic, delta_t_s = BASELINE_DELTA_T_S, vcap_mv = NOMINAL_VCAP_MV)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      x, y, z, local_sigma, local_rho, local_beta = initialize_state(seed, temp, acoustic, delta_t_s, vcap_mv)

      # [FIX FW.7]: Float арифметика без round() — ідентично firmware bio_contract.rb.
      # mruby на MCU виконує x += dx * DT без будь-якого округлення між ітераціями.
      # Сервер МУСИТЬ робити те саме для Dual Computation Integrity.
      # Overflow protection: з clamped σ∈[5,30] та ρ∈[10,50], Lorenz attractor bounded.
      # Емпірично |x|<25, |y|<35, |z|<50 після 250 ітерацій — далеко від Float64 overflow.
      x, y, z = iterate_lorenz(x, y, z, local_sigma, local_rho, local_beta)

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      SilkenNet::Metrics::LORENZ_COMPUTATION_DURATION.observe(duration) if defined?(SilkenNet::Metrics)

      z.round(4)
    end

    # [FW.6] Обчислення Z з продовженням стану.
    # Використовується для перевірки безперервної траєкторії атрактора,
    # коли firmware зберігає (x, y, z) між циклами STOP2.
    # Повертає [z_rounded, x_final, y_final, z_final] для подальшого ланцюгування.
    def self.calculate_z_continued(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s = BASELINE_DELTA_T_S, vcap_mv = NOMINAL_VCAP_MV)
      local_sigma = (BASE_SIGMA + (acoustic * 0.1)).clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)
      local_rho   = (BASE_RHO + (temp * 0.2)).clamp(RHO_LIMITS.min, RHO_LIMITS.max)
      local_beta  = perturb_beta(delta_t_s, vcap_mv)

      x, y, z = iterate_lorenz(x_prev, y_prev, z_prev, local_sigma, local_rho, local_beta)

      [ z.round(4), x, y, z ]
    end

    # [SEC.11] Compute Z from explicit initial coordinates (x₀, y₀, z₀)
    # rather than deriving them from a `seed`. This is the post-SEC.11
    # entry-point: backend feeds the same (x₀, y₀, z₀) the firmware used
    # — derived from K_seed via SilkenNet::SeedDerivation — so device-Z
    # and server-Z become byte-comparable and `check_z_divergence!` can
    # be flipped to a numeric tolerance band once the field migration
    # is complete.
    #
    # Returns [z_rounded, x_final, y_final, z_final] like
    # `calculate_z_continued` so the caller can persist the trajectory
    # tail on `TelemetryLog.lorenz_state_*`.
    def self.calculate_z_from_state(x0, y0, z0, temp, acoustic, delta_t_s = BASELINE_DELTA_T_S, vcap_mv = NOMINAL_VCAP_MV)
      start_time  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      local_sigma = (BASE_SIGMA + (acoustic * 0.1)).clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)
      local_rho   = (BASE_RHO + (temp * 0.2)).clamp(RHO_LIMITS.min, RHO_LIMITS.max)
      local_beta  = perturb_beta(delta_t_s, vcap_mv)

      x, y, z = iterate_lorenz(x0.to_f, y0.to_f, z0.to_f, local_sigma, local_rho, local_beta)

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      SilkenNet::Metrics::LORENZ_COMPUTATION_DURATION.observe(duration) if defined?(SilkenNet::Metrics)

      [ z.round(4), x, y, z ]
    end

    def self.homeostatic?(z_value, tree_family)
      z_value.between?(tree_family.critical_z_min, tree_family.critical_z_max)
    end

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # ВІЗУАЛІЗАЦІЯ ТРАЄКТОРІЇ
    # [ОПТИМІЗАЦІЯ ПАМ'ЯТІ]: Замість масиву з 250 хешів повертаємо
    # плаский масив Float. Це в 5 разів легше для пам'яті сервера та
    # ідеально для Float32Array у JavaScript (Three.js/Deck.gl).
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    def self.generate_trajectory(seed, temp, acoustic, delta_t_s = BASELINE_DELTA_T_S, vcap_mv = NOMINAL_VCAP_MV)
      x, y, z, local_sigma, local_rho, local_beta = initialize_state(seed, temp, acoustic, delta_t_s, vcap_mv)

      # Результат: [x1, y1, z1, x2, y2, z2, ...]
      Array.new(ITERATIONS * 3) do |i|
        if i % 3 == 0 && i > 0
          # Крок ітерації виконується кожні 3 значення
          dx = local_sigma * (y - x)
          dy = x * (local_rho - z) - y
          dz = (x * y) - (local_beta * z)

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

    # [FW.5] Обчислює β з врахуванням метаболічної перфузії дерева.
    # Зберігається ідентичним firmware/bio_contracts/bio_contract.rb#iterate.
    def self.perturb_beta(delta_t_s, vcap_mv)
      delta_t_improvement_s = BASELINE_DELTA_T_S - delta_t_s
      delta_t_improvement_s = 0 if delta_t_improvement_s < 0
      vcap_centered = vcap_mv - NOMINAL_VCAP_MV

      beta = BASE_BETA + (delta_t_improvement_s * BETA_DELTA_T_COEFF) +
                         (vcap_centered * BETA_VCAP_COEFF)
      beta.clamp(BETA_LIMITS.min, BETA_LIMITS.max)
    end

    # Спільне ядро ітерацій Лоренца — використовується в calculate_z та calculate_z_continued
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

    private_class_method def self.initialize_state(seed, temp, acoustic, delta_t_s, vcap_mv)
      # Початкові координати (насіння) з використанням DID
      # [FIX FW.7]: Float арифметика — ідентично firmware bio_contract.rb
      x = ((seed % 1000) / 500.0) - 1.0
      y = (((seed >> 4) % 1000) / 500.0) - 1.0
      z = (((seed >> 8) % 1000) / 500.0) - 1.0

      # [СЕРЕДОВИЩНИЙ ЗАПОБІЖНИК]: Clamp запобігає вильоту в нескінченність
      # навіть якщо дерево горить (temp > 100) або датчик видає шум.
      local_sigma = (BASE_SIGMA + (acoustic * 0.1)).clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)
      local_rho   = (BASE_RHO + (temp * 0.2)).clamp(RHO_LIMITS.min, RHO_LIMITS.max)
      local_beta  = perturb_beta(delta_t_s, vcap_mv)

      [ x, y, z, local_sigma, local_rho, local_beta ]
    end
  end
end
