# frozen_string_literal: true

module SilkenNet
  class Attractor
    # Класичні константи Лоренца з нашого mruby контракту
    BASE_SIGMA = 10.0
    BASE_RHO   = 28.0
    BASE_BETA  = 2.666 # 8.0 / 3.0

    DT = 0.01
    ITERATIONS = 250

    # Метод генерує масив з 250 точок {x, y, z} для 3D графіка на фронтенді
    def self.generate_trajectory(seed, temp, acoustic)
      # Ініціалізація початкової точки хаосу з DID дерева (seed)
      x = ((seed % 1000) / 500.0) - 1.0
      y = (((seed >> 4) % 1000) / 500.0) - 1.0
      z = (((seed >> 8) % 1000) / 500.0) - 1.0

      # Пертурбація системи фізичними даними з лісу
      local_sigma = BASE_SIGMA + (acoustic * 0.1)
      local_rho = BASE_RHO + (temp * 0.2)

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

    # Метод-дублер: дозволяє серверу швидко перевірити,
    # чи правильно мікроконтролер порахував бали
    def self.verify_z_axis(seed, temp, acoustic)
      generate_trajectory(seed, temp, acoustic).last[:z]
    end
  end
end
