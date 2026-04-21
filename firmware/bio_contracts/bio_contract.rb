# frozen_string_literal: true

module SilkenNet
  # =========================================================================
  # 1. МАТЕМАТИЧНЕ ЯДРО (Теорія Хаосу)
  # =========================================================================
  class Attractor
    # Класичні константи Лоренца
    BASE_SIGMA = 10.0
    BASE_RHO   = 28.0
    BASE_BETA  = 8.0 / 3.0 # [FIX: Attractor Sync] Було 2.666 (обрізано), тепер точне значення

    # Крок інтегрування та глибина симуляції
    DT = 0.01
    ITERATIONS = 250 # Даємо системі час вийти на траєкторію хаосу

    # [FIX: Attractor Sync] Межі стабільності, ідентичні серверу
    # (app/services/silken_net/attractor.rb). Без clamp при екстремальних
    # показниках температури/акустики система вилітає в нескінченність.
    SIGMA_MIN = 5.0
    SIGMA_MAX = 30.0
    RHO_MIN   = 10.0
    RHO_MAX   = 50.0

    # [FW.6] Обчислення Z з початковим станом від chaos_seed.
    # Використовується при першому старті або коли RTC backup стерто.
    def self.calculate_z_axis(seed, temp, acoustic)
      x = ((seed % 1000) / 500.0) - 1.0
      y = (((seed >> 4) % 1000) / 500.0) - 1.0
      z = (((seed >> 8) % 1000) / 500.0) - 1.0

      x, y, z = iterate(x, y, z, temp, acoustic)
      z
    end

    # [FW.6] Обчислення Z з ПРОДОВЖЕННЯМ від збереженого стану (x_prev, y_prev, z_prev).
    # Реалізує безперервну траєкторію атрактора між циклами STOP2.
    # Повертає масив [z, x_final, y_final, z_final] для збереження у RTC.
    def self.calculate_z_axis_continued(x_prev, y_prev, z_prev, temp, acoustic)
      x, y, z = iterate(x_prev, y_prev, z_prev, temp, acoustic)
      [z, x, y, z]
    end

    # Спільне ядро ітерацій Лоренца — уникаємо дублювання коду
    def self.iterate(x, y, z, temp, acoustic)
      # Пертурбація системи: акустика та температура змінюють константи
      local_sigma = BASE_SIGMA + (acoustic * 0.1)
      local_rho = BASE_RHO + (temp * 0.2)

      # [FIX: Attractor Sync] Clamp — запобігаємо вибуху при екстремальних вхідних
      local_sigma = SIGMA_MIN if local_sigma < SIGMA_MIN
      local_sigma = SIGMA_MAX if local_sigma > SIGMA_MAX
      local_rho = RHO_MIN if local_rho < RHO_MIN
      local_rho = RHO_MAX if local_rho > RHO_MAX

      ITERATIONS.times do
        dx = local_sigma * (y - x)
        dy = x * (local_rho - z) - y
        dz = (x * y) - (BASE_BETA * z)

        x += dx * DT
        y += dy * DT
        z += dz * DT
      end

      [x, y, z]
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
      pack_status_byte(z_val)
    end

    # [FW.6] Evaluate з продовженням стану. Повертає [payload_byte, x, y, z].
    def self.evaluate_and_pack_continued(x_prev, y_prev, z_prev, temp, acoustic)
      z_val, x_final, y_final, z_final = Attractor.calculate_z_axis_continued(x_prev, y_prev, z_prev, temp, acoustic)
      payload_byte = pack_status_byte(z_val)
      [payload_byte, x_final, y_final, z_final]
    end

    # Спільна логіка пакування Z → status_byte
    def self.pack_status_byte(z_val)
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

        # Розрахунок винагороди: чим ближче стан дерева до ідеалу (29.0),
        # тим ефективніше воно депонує вуглець і більше балів отримує.
        deviation = (OPTIMAL_Z_TARGET - z_val).abs

        # Базова нагорода 50 балів мінус штраф за відхилення.
        # [FIX FW.13]: Explicit clamp замість ternary + окремих guard'ів.
        # В homeostasis zone deviation ∈ [0, 27], тому reward ∈ [23, 50] — завжди > 0.
        # Але clamp(10, 63) захищає від edge cases + об'єднує guard'и нижче.
        reward = 50 - deviation.round
        growth_points = reward.clamp(10, 63)
      end

      # Захист від переповнення для 6-бітного простору (максимум 63)
      growth_points = growth_points.clamp(0, 63)

      # ПАКУВАННЯ АКТИВУ
      # Зсуваємо статус на 6 бітів вліво і додаємо бали росту.
      # [ Статус (2 біти) | Growth Points (6 бітів) ]
      (status << 6) | growth_points
    end
  end
end

# =========================================================================
# 3. ТОЧКА ВХОДУ (Міст між C та Ruby)
# =========================================================================

# [FW.6] Первинний виклик (перший старт або RTC скинуто).
# C-ядро у файлі main.c знає лише про існування цієї функції.
def calculate_state(seed, temp, acoustic)
  SilkenNet::BioContract.evaluate_and_pack(seed, temp, acoustic)
end

# [FW.6] Виклик з продовженням стану (RTC зберіг x,y,z з попереднього циклу).
# Повертає масив [payload_byte, x_final, y_final, z_final].
# C-код витягує payload_byte з args[0] і зберігає x,y,z у RTC DR16-DR18.
def calculate_state_continued(x_prev, y_prev, z_prev, temp, acoustic)
  SilkenNet::BioContract.evaluate_and_pack_continued(x_prev, y_prev, z_prev, temp, acoustic)
end
