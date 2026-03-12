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

    # =========================================================================
    # OTA LIFECYCLE (AASM State Machine — firmware_update_status)
    # =========================================================================
    aasm :firmware, column: :firmware_update_status, enum: true, namespace: :firmware, whiny_persistence: true do
      state :fw_idle, initial: true
      state :fw_pending
      state :fw_downloading
      state :fw_verifying
      state :fw_flashing
      state :fw_failed
      state :fw_completed

      # Планування OTA оновлення
      event :schedule_update do
        transitions from: [ :fw_idle, :fw_completed, :fw_failed ], to: :fw_pending
      end

      # Початок завантаження чанків
      event :start_download do
        transitions from: :fw_pending, to: :fw_downloading
      end

      # Перехід до верифікації SHA-256
      event :start_verification do
        transitions from: :fw_downloading, to: :fw_verifying
      end

      # Запис у Flash
      event :start_flashing do
        transitions from: :fw_verifying, to: :fw_flashing
      end

      # Успішне завершення OTA
      event :complete_update do
        transitions from: :fw_flashing, to: :fw_completed
      end

      # Збій OTA на будь-якому етапі
      event :fail_update do
        transitions from: [ :fw_pending, :fw_downloading, :fw_verifying, :fw_flashing ], to: :fw_failed
      end

      # Скидання до idle (після збою або для повторного оновлення)
      event :reset_firmware do
        transitions from: [ :fw_failed, :fw_completed ], to: :fw_idle
      end
    end
  end
end
