# frozen_string_literal: true

require "digest"

class BioContractFirmware < ApplicationRecord
  # --- КОНСТАНТИ ---
  # 256KB — межа для стабільного OTA-циклу через CoAP/LoRa в складних погодних умовах.
  # HEX-рядок займає 2x від бінарного розміру, тому 256KB binary = 512KB HEX.
  MAX_BYTECODE_SIZE = 512.kilobytes

  # Допустимі типи обладнання для прошивки
  HARDWARE_TYPES = %w[Tree Gateway].freeze

  # --- ЗВ'ЯЗКИ ---
  # Кластери (Ліси), які зараз працюють на цій версії
  has_many :clusters, foreign_key: :active_firmware_id
  # Специфікація породи (прошивка для Дуба != прошивка для Сосни)
  belongs_to :tree_family, optional: true

  # --- ВАЛІДАЦІЇ ---
  validates :version, presence: true, uniqueness: true

  # Строга HEX-валідація (Case-insensitive)
  validates :bytecode_payload, presence: true, format: {
    with: /\A([a-fA-F0-9]{2})+\z/,
    message: "має бути чистим HEX-рядком парної довжини (кратним байту)"
  }

  # [DB Bloat Protection]: Обмежуємо розмір HEX-пейлоаду (512KB HEX ≈ 256KB binary)
  validates :bytecode_payload, length: { maximum: MAX_BYTECODE_SIZE,
    message: "перевищує ліміт #{MAX_BYTECODE_SIZE / 1.kilobyte} КБ" }

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

  def payload_size
    binary_payload.bytesize
  end

  # Розрізаємо прошивку на чанки для CoAP (MTU-friendly)
  # Наприклад, для 512 байт: N = ceil(Size / 512)
  def chunks(chunk_size = 512)
    return [] if payload_size.zero?

    binary_payload.b.scan(/.{1,#{chunk_size}}/m)
  end

  # Скільки всього чанків у даній еволюції
  def total_chunks(chunk_size = 512)
    return 0 if payload_size.zero?

    (payload_size.to_f / chunk_size).ceil
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

      # 1. Кенозис старих версій
      self.class.active.where.not(id: id).update_all(is_active: false)

      # 2. Активація нової істини з фіксацією відсотка розгортання
      update!(is_active: true, rollout_percentage: clamped)

      # 3. Синхронізація кластерів
      # Ми лише позначаємо версію, а OtaTransmissionWorker підхопить її за розкладом
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
      errors.add(:compatible_hardware_versions, "має бути масивом")
      return
    end

    unless compatible_hardware_versions.all? { |v| v.is_a?(String) && v.present? }
      errors.add(:compatible_hardware_versions, "кожна версія має бути непорожнім рядком")
    end
  end
end
