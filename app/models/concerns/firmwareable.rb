# frozen_string_literal: true

# Спільний OTA lifecycle для пристроїв (Tree, Gateway).
# Визначає enum firmware_update_status із 7 станами оновлення прошивки.
module Firmwareable
  extend ActiveSupport::Concern

  included do
    # --- СТАН ПРОШИВКИ (OTA Status Tracking) ---
    # Відстежуємо процес OTA-оновлення, щоб уникнути «чорної діри» прошивки.
    enum :firmware_update_status, {
      fw_idle: 0,        # Немає активного оновлення
      fw_pending: 1,     # Оновлення заплановано
      fw_downloading: 2, # Завантаження чанків
      fw_verifying: 3,   # Верифікація SHA-256
      fw_flashing: 4,    # Запис у Flash
      fw_failed: 5,      # Оновлення провалене
      fw_completed: 6    # Успішно оновлено
    }, prefix: :firmware, default: :fw_idle
  end
end
