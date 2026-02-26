# frozen_string_literal: true

module SilkenNet
  # =========================================================================
  # 1. МАТЕМАТИЧНЕ ЯДРО (Теорія Хаосу)
  # =========================================================================
  class Attractor
    # Класичні константи Лоренца
    BASE_SIGMA = 10.0
    BASE_RHO   = 28.0
    BASE_BETA  = 2.666 # 8.0 / 3.0

    # Крок інтегрування та глибина симуляції
    DT = 0.01
    ITERATIONS = 250 # Даємо системі час вийти на траєкторію хаосу

    def self.calculate_z_axis(seed, temp, acoustic)
      x = ((seed % 1000) / 500.0) - 1.0
      y = (((seed >> 4) % 1000) / 500.0) - 1.0
      z = (((seed >> 8) % 1000) / 500.0) - 1.0

      # Пертурбація системи: акустика та температура змінюють константи
      local_sigma = BASE_SIGMA + (acoustic * 0.1)
      local_rho = BASE_RHO + (temp * 0.2)

      ITERATIONS.times do
        dx = local_sigma * (y - x)
        dy = x * (local_rho - z) - y
        dz = (x * y) - (BASE_BETA * z)

        x += dx * DT
        y += dy * DT
        z += dz * DT
      end

      # Повертаємо чисту інтенсивність конвекції (руху соку)
      z
    end
  end

  # =========================================================================
  # 2. ЛОГІКА ПРИЙНЯТТЯ РІШЕНЬ ТА ТОКЕНОМІКА (Біо-Контракт)
  # =========================================================================
  class BioContract
    # Межі детермінованого хаосу здорового дерева
    CRITICAL_Z_MIN = 2.0  # Падіння нижче = втрата тургору / посуха
    CRITICAL_Z_MAX = 45.0 # Стрибок вище = аномальний стрес / втручання

    # Ідеальний стан конвекції для максимізації поглинання CO2
    OPTIMAL_Z_TARGET = 29.0

    def self.evaluate_and_pack(seed, temp, acoustic)
      z_val = Attractor.calculate_z_axis(seed, temp, acoustic)

      status = 0
      growth_points = 0 # Бали росту (Proof of Growth)

      # ФІНАНСОВА ЛОГІКА
      if z_val < CRITICAL_Z_MIN
        status = 1 # Сигнал раннього попередження (Посуха)
        growth_points = 1 # Мінімальна генерація, дерево виживає
      elsif z_val > CRITICAL_Z_MAX
        status = 2 # Аномалія (Критичний стрес)
        growth_points = 0 # Емісія зупиняється
      else
        status = 0 # Гомеостаз (Здоровий Хаос)

        # Розрахунок винагороди: чим ближче стан дерева до ідеалу (20.0),
        # тим ефективніше воно депонує вуглець і більше балів отримує.
        deviation = (OPTIMAL_Z_TARGET - z_val).abs

        # Базова нагорода 50 балів мінус штраф за відхилення
        reward = 50 - deviation.to_i
        growth_points = reward > 0 ? reward : 10
      end

      # Захист від переповнення для 6-бітного простору (максимум 63)
      growth_points = 63 if growth_points > 63
      growth_points = 0  if growth_points < 0

      # ПАКУВАННЯ АКТИВУ
      # Зсуваємо статус на 6 бітів вліво і додаємо бали росту.
      # [ Статус (2 біти) | Growth Points (6 бітів) ]
      payload_byte = (status << 6) | growth_points

      payload_byte
    end
  end
end

# =========================================================================
# 3. ТОЧКА ВХОДУ (Міст між C та Ruby)
# =========================================================================
# C-ядро у файлі main.c знає лише про існування цієї функції.
def calculate_state(seed, temp, acoustic)
  SilkenNet::BioContract.evaluate_and_pack(seed, temp, acoustic)
end
