# frozen_string_literal: true

module SilkenNet
  class Attractor
    # Класичні константи Лоренца з нашого mruby контракту
    BASE_SIGMA = 10.0
    BASE_RHO   = 28.0
    BASE_BETA  = 2.666 # 8.0 / 3.0

    DT = 0.01
    ITERATIONS = 250

    # =========================================================================
    # МЕТОД ДЛЯ ФРОНТЕНДУ (Візуалізація)
    # Викликається рідко, лише коли юзер/інвестор відкриває 3D графік дерева
    # =========================================================================
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

    # =========================================================================
    # МЕТОД ДЛЯ БЕКЕНДУ (Верифікація Оракулом) - ZERO ALLOCATION
    # Викликається тисячі разів на секунду. Рахує лише математику.
    # =========================================================================
    def self.verify_z_axis(seed, temp, acoustic)
      x, y, z, local_sigma, local_rho = initialize_state(seed, temp, acoustic)

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

    # Інкапсульована ініціалізація (DRY)
    private_class_method def self.initialize_state(seed, temp, acoustic)
      # Ініціалізація початкової точки хаосу з DID дерева (seed)
      x = ((seed % 1000) / 500.0) - 1.0
      y = (((seed >> 4) % 1000) / 500.0) - 1.0
      z = (((seed >> 8) % 1000) / 500.0) - 1.0

      # Пертурбація системи фізичними даними з лісу
      local_sigma = BASE_SIGMA + (acoustic * 0.1)
      local_rho = BASE_RHO + (temp * 0.2)

      [x, y, z, local_sigma, local_rho]
    end
  end
end
