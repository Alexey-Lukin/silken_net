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

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # МЕТОД ДЛЯ БЕКЕНДУ (Розрахунок стабільності)
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    def self.calculate_z(seed, temp, acoustic)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      x, y, z, local_sigma, local_rho = initialize_state(seed, temp, acoustic)

      # [FIX FW.7]: Float арифметика без round() — ідентично firmware bio_contract.rb.
      # mruby на MCU виконує x += dx * DT без будь-якого округлення між ітераціями.
      # Сервер МУСИТЬ робити те саме для Dual Computation Integrity.
      # Overflow protection: з clamped σ∈[5,30] та ρ∈[10,50], Lorenz attractor bounded.
      # Емпірично |x|<25, |y|<35, |z|<50 після 250 ітерацій — далеко від Float64 overflow.
      ITERATIONS.times do
        dx = local_sigma * (y - x)
        dy = x * (local_rho - z) - y
        dz = (x * y) - (BASE_BETA * z)

        x += dx * DT
        y += dy * DT
        z += dz * DT
      end

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      SilkenNet::Metrics::LORENZ_COMPUTATION_DURATION.observe(duration) if defined?(SilkenNet::Metrics)

      z.round(4)
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
    def self.generate_trajectory(seed, temp, acoustic)
      x, y, z, local_sigma, local_rho = initialize_state(seed, temp, acoustic)

      # Результат: [x1, y1, z1, x2, y2, z2, ...]
      Array.new(ITERATIONS * 3) do |i|
        if i % 3 == 0 && i > 0
          # Крок ітерації виконується кожні 3 значення
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

    private_class_method def self.initialize_state(seed, temp, acoustic)
      # Початкові координати (насіння) з використанням DID
      # [FIX FW.7]: Float арифметика — ідентично firmware bio_contract.rb
      x = ((seed % 1000) / 500.0) - 1.0
      y = (((seed >> 4) % 1000) / 500.0) - 1.0
      z = (((seed >> 8) % 1000) / 500.0) - 1.0

      # [СЕРЕДОВИЩНИЙ ЗАПОБІЖНИК]: Clamp запобігає вильоту в нескінченність
      # навіть якщо дерево горить (temp > 100) або датчик видає шум.
      local_sigma = (BASE_SIGMA + (acoustic * 0.1)).clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)
      local_rho   = (BASE_RHO + (temp * 0.2)).clamp(RHO_LIMITS.min, RHO_LIMITS.max)

      [ x, y, z, local_sigma, local_rho ]
    end
  end
end
