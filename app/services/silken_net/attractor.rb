# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module SilkenNet
  class Attractor
    # Використовуємо BigDecimal для абсолютної крос-платформної детермінованості
    # Це гарантує, що Slashing-вирок буде однаковим на будь-якому процесорі.
    BASE_SIGMA = "10.0".to_d
    BASE_RHO   = "28.0".to_d
    BASE_BETA  = ("8.0".to_d / "3.0".to_d).round(18)

    DT = "0.01".to_d
    ITERATIONS = 250

    # МЕЖІ СТАБІЛЬНОСТІ (Chaos Clamps):
    # Захищаємо систему від "вибуху" при екстремальних температурах.
    SIGMA_LIMITS = (5.0..30.0)
    RHO_LIMITS   = (10.0..50.0)

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # МЕТОД ДЛЯ БЕКЕНДУ (Розрахунок стабільності)
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    def self.calculate_z(seed, temp, acoustic)
      x, y, z, local_sigma, local_rho = initialize_state(seed, temp, acoustic)

      # Обчислення в BigDecimal сповільнюють процес, але дають
      # "Юридичну Точність" для Web3-аудиту.
      ITERATIONS.times do
        dx = local_sigma * (y - x)
        dy = x * (local_rho - z) - y
        dz = (x * y) - (BASE_BETA * z)

        x += dx * DT
        y += dy * DT
        z += dz * DT
      end

      z.to_f.round(4)
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
        when 0 then x.to_f.round(4)
        when 1 then y.to_f.round(4)
        when 2 then z.to_f.round(4)
        end
      end
    end

    private_class_method def self.initialize_state(seed, temp, acoustic)
      # Початкові координати (насіння) з використанням DID
      x = (((seed % 1000) / 500.0) - 1.0).to_d
      y = ((((seed >> 4) % 1000) / 500.0) - 1.0).to_d
      z = ((((seed >> 8) % 1000) / 500.0) - 1.0).to_d

      # [СЕРЕДОВИЩНИЙ ЗАПОБІЖНИК]: Clamp запобігає вильоту в нескінченність
      # навіть якщо дерево горить (temp > 100) або датчик видає шум.
      local_sigma = (BASE_SIGMA + (acoustic.to_d * "0.1".to_d)).clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)
      local_rho   = (BASE_RHO + (temp.to_d * "0.2".to_d)).clamp(RHO_LIMITS.min, RHO_LIMITS.max)

      [ x, y, z, local_sigma, local_rho ]
    end
  end
end
