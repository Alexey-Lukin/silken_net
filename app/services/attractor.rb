# frozen_string_literal: true

module SilkenNet
  class Attractor
    # Класичні константи Лоренца
    BASE_SIGMA = 10.0
    BASE_RHO   = 28.0
    BASE_BETA  = 8.0 / 3.0 # Вища точність для тривалих ітерацій

    DT = 0.01
    ITERATIONS = 250

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # МЕТОД ДЛЯ БЕКЕНДУ (Розрахунок стабільності)
    # Викликається TelemetryUnpackerService для кожного лога
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    def self.calculate_z(seed, temp, acoustic)
      x, y, z, local_sigma, local_rho = initialize_state(seed, temp, acoustic)

      # Zero-allocation loop
      ITERATIONS.times do
        dx = local_sigma * (y - x)
        dy = x * (local_rho - z) - y
        dz = (x * y) - (BASE_BETA * z)

        x += dx * DT
        y += dy * DT
        z += dz * DT
      end

      z.round(4)
    end

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # ПЕРЕВІРКА ГOМЕОСТАЗУ
    # Порівнює отриманий Z з критичними межами конкретної породи дерева
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    def self.homeostatic?(z_value, tree_family)
      z_value.between?(tree_family.critical_z_min, tree_family.critical_z_max)
    end

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # ВІЗУАЛІЗАЦІЯ ТРАЄКТОРІЇ
    # Для 3D-дашборду інвестора
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    def self.generate_trajectory(seed, temp, acoustic)
      x, y, z, local_sigma, local_rho = initialize_state(seed, temp, acoustic)
      trajectory = []

      ITERATIONS.times do
        dx = local_sigma * (y - x)
        dy = x * (local_rho - z) - y
        dz = (x * y) - (BASE_BETA * z)

        x += dx * DT
        y += dy * DT
        z += dz * DT

        trajectory << { x: x.round(4), y: y.round(4), z: z.round(4) }
      end

      trajectory
    end

    private_class_method def self.initialize_state(seed, temp, acoustic)
      # Використовуємо DID дерева як зерно для початкових координат
      # Це створює "унікальний почерк" хаосу для кожного дерева
      x = ((seed % 1000) / 500.0) - 1.0
      y = (((seed >> 4) % 1000) / 500.0) - 1.0
      z = (((seed >> 8) % 1000) / 500.0) - 1.0

      # Фізична пертурбація:
      # Акустика (шум/комахи) впливає на зв'язність (Sigma)
      # Температура впливає на енергію системи (Rho)
      local_sigma = BASE_SIGMA + (acoustic * 0.1)
      local_rho   = BASE_RHO + (temp * 0.2)

      [ x, y, z, local_sigma, local_rho ]
    end
  end
end
