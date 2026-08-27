# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "digest"

class BioContractFirmware < ApplicationRecord
  include OtaChunkable

  # --- КОНСТАНТИ ---
  # 256KB — межа для стабільного OTA-циклу через CoAP/LoRa в складних погодних умовах.
  # HEX-рядок займає 2x від бінарного розміру, тому 256KB binary = 512KB HEX.
  MAX_BYTECODE_SIZE = 512.kilobytes

  # Допустимі типи обладнання для прошивки
  HARDWARE_TYPES = %w[Tree Gateway].freeze

  # --- ЗВ'ЯЗКИ ---
  # Трекінг версій — per-device SemVer-РЯДОК, і це вся правда:
  #   * `Tree.firmware_version` + `Gateway.firmware_version` (рядок SemVer)
  #   * `BioContractFirmware.is_active` + `rollout_percentage` (global toggle)
  #   * `deployment_count` рахує string-match: `Tree.where(firmware_version: ...)`
  #
  # 🔴 Тут стояв TODO про per-cluster трекінг через `clusters.active_firmware_id`
  # разом із закоментованою асоціацією — і його останній рядок ЦИТУВАВ ВЛАСНЕ
  # СПРОСТУВАННЯ: «запис у 00_07 (E.62) тримає намір видимим», тоді як E.62 є
  # рядком §🗄️ Архіву «Dead `clusters.active_firmware_id` assoc removed». Колонки
  # немає в `db/structure.sql`, наміру не тримає жоден живий пункт, а форма
  # посилання при цьому бездоганна — ID резолвиться, тож не червоніє НІЩО
  # [DOC-T.93]. Знято 2026-08-27: сам патерн лишається citable під тим же ID —
  # `04_01` описує його на СУСІДНЬОМУ випадку (`firmware_version_id` як
  # wire-ідентифікатор, mis-join trap), і саме там він і живий.

  # Специфікація породи (прошивка для Дуба != прошивка для Сосни)
  belongs_to :tree_family, optional: true

  # --- ВАЛІДАЦІЇ ---
  validates :version, presence: true, uniqueness: true

  # Строга HEX-валідація (Case-insensitive)
  validates :bytecode_payload, presence: true, format: {
    with: /\A([a-fA-F0-9]{2})+\z/,
    message: :must_be_even_length_hex
  }

  # [DB Bloat Protection]: Обмежуємо розмір HEX-пейлоаду (512KB HEX ≈ 256KB binary)
  validates :bytecode_payload, length: { maximum: MAX_BYTECODE_SIZE,
    message: :exceeds_size_limit }

  # [Species Specificity]: Тип обладнання (Tree/Gateway)
  validates :target_hardware_type, inclusion: { in: HARDWARE_TYPES }, allow_nil: true

  # [Phased Rollout]: Відсоток розгортання (0–100)
  validates :rollout_percentage, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  }

  # [Hardware Compatibility Matrix]: Масив сумісних версій заліза.
  # Прошивка для Hardware Revision v1.0 (STM32L4) вб'є пристрій v2.0 (STM32H7).
  validate :compatible_hardware_versions_format

  # --- КОЛБЕКИ ---
  # [SHA-256 Integrity]: Автоматичний розрахунок хешу при збереженні
  before_save :compute_binary_sha256, if: :bytecode_payload_changed?

  # --- СКОУПИ ---
  scope :active, -> { where(is_active: true) }
  scope :latest, -> { order(version: :desc) }

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # БІНАРНА МАТЕМАТИКА (OTA Chunking)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Перетворення HEX у бінарний потік з мемоізацією
  def binary_payload
    @binary_payload ||= [ bytecode_payload ].pack("H*").freeze
  end

  # Number of devices currently running this firmware version
  def deployment_count
    Tree.where(firmware_version: version).count + Gateway.where(firmware_version: version).count
  end

  def payload_size
    binary_payload.bytesize
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # ЦІЛІСНІСТЬ (Integrity Verification)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Перевірка SHA-256 хешу перед OTA-передачею.
  # STM32 також отримає цей хеш для верифікації після збірки всіх чанків у Flash.
  # Повертає true, якщо хеш збігається; інакше піднімає IntegrityError.
  def verify_integrity!
    expected = Digest::SHA256.hexdigest(binary_payload)
    return true if binary_sha256 == expected

    raise IntegrityError, "SHA-256 mismatch: очікувано #{binary_sha256}, отримано #{expected}"
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # ЖИТТЄВИЙ ЦИКЛ (The Phased Evolution)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Поступове розгортання прошивки (Phased Rollout).
  # percentage: 1–100 — частка пристроїв для оновлення.
  # Спочатку оновлюємо 1% кластера, чекаємо на телеметрію, потім далі.
  def deploy_globally!(percentage: 100)
    clamped = percentage.to_i.clamp(1, 100)

    transaction do
      # [BUG FIX]: Песимістичне блокування для захисту від гонки конкурентних деплоїв
      lock!

      # 1. Кенозис старих версій СВОГО класу обладнання: Gateway-реліз не гасить
      # активний Tree-контракт (latest_tree_firmware_id живиться скоупом .active)
      #
      # 🔴 [ARCH.85] Типізований реліз гасить і БЕЗТИПНИХ предків, і це не
      # розширення про всяк випадок. `where(target_hardware_type: "Tree")` — це
      # SQL `= 'Tree'`, а **NULL не дорівнює нічому**, тож рядки без типу не
      # гасились НІКОЛИ. Писальників цієї колонки в дереві не було взагалі до
      # фіксу форми завантаження, отже безтипні — це геть усі наявні рядки:
      # перший же типізований реліз лишав би їх усіх `is_active`.
      #
      # ⚠️ Чому гасити безтипного БЕЗПЕЧНО, а не ризиковано: активний рядок без
      # типу вже недосяжний для типізованого читача (`latest_tree_firmware_id`
      # фільтрує по типу), тобто він зомбі за визначенням — присутній у `.active`
      # і не обраний ніким. Лишати його означало б тримати другий «активний»
      # контракт, який мовчки зіпсує будь-якого майбутнього читача, що
      # прочитає `.active` без фільтра.
      #
      # ⊕ Безтипний реліз поводиться як раніше (`IS NULL` → гасить лише
      # безтипних): legacy гасить legacy, і нової семантики це не вводить.
      superseded = self.class.active.where.not(id: id)
      superseded = if target_hardware_type.present?
                     superseded.where(target_hardware_type: [ target_hardware_type, nil ])
      else
                     superseded.where(target_hardware_type: nil)
      end
      superseded.update_all(is_active: false)

      # 2. Активація нової істини з фіксацією відсотка розгортання
      update!(is_active: true, rollout_percentage: clamped)

      # 3. Позначення активної істини — і НІЯКОЇ синхронізації тут не стається.
      # ⚠️ Тут доти стояло «OtaTransmissionWorker підхопить її за розкладом»:
      # розкладу не існує, а сам воркер `OtaTransmissionWorker` не має ЖОДНОГО
      # enqueuer'а з часів [FW.60] — це канон і фіксує (`04_02` картка воркера
      # каже «Тригер — ЖОДНОГО»). Тобто коментар обіцяв автомат, якого немає, і
      # читач `deploy_globally!` виносив із нього хибну модель роботи.
      #
      # ✅ Як воно ПРАЦЮЄ насправді: когорту вибирає й hiwater палить
      # `Ota::DeploymentDispatcherService` у ТОМУ САМОМУ виклику (він і кличе цей
      # метод), а чанки Королева забирає власним poll'ом. Тобто розгортання
      # синхронне з дією оператора, а `rollout_percentage` тут — ЗАПИС про
      # відвантажену когорту, не ручка, яку хтось прочитає пізніше.
      Rails.logger.info "🚀 [OTA] Біо-Контракт #{version} активовано (#{clamped}%). Готовність: #{payload_size} байт."
    end
  end

  # Спеціалізований клас помилки цілісності
  class IntegrityError < StandardError; end

  private

  # Обчислення SHA-256 хешу бінарного вмісту прошивки
  def compute_binary_sha256
    # Скидаємо мемоізований бінарний payload, бо bytecode_payload змінився
    @binary_payload = nil
    self.binary_sha256 = Digest::SHA256.hexdigest([ bytecode_payload ].pack("H*"))
  end

  # [Hardware Compatibility Matrix]: Валідація формату масиву сумісних версій.
  # Кожен елемент — рядок (наприклад, "v1.0", "v2.1-STM32H7").
  def compatible_hardware_versions_format
    unless compatible_hardware_versions.is_a?(Array)
      errors.add(:compatible_hardware_versions, :must_be_array)
      return
    end

    unless compatible_hardware_versions.all? { |v| v.is_a?(String) && v.present? }
      errors.add(:compatible_hardware_versions, :version_must_be_non_blank_string)
    end
  end
end
