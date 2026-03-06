# frozen_string_literal: true

require "digest"
require "bigdecimal"

class TinyMlModel < ApplicationRecord
  # --- КОНСТАНТИ ---
  # Допустимі формати вагових файлів для STM32 TinyML
  MODEL_FORMATS = %w[tflite edge_impulse onnx c_array].freeze

  # --- ЗВ'ЯЗКИ ---
  # Дерева, що використовують цей інтелект
  has_many :trees, dependent: :nullify
  # Специфікація породи (Акустика дуба != Акустика сосни)
  belongs_to :tree_family, optional: true

  # --- СТРУКТУРОВАНІ ДАНІ ---
  # Параметри: { input_shape: [1, 64], quantized: true }
  store_accessor :metadata, :input_shape

  # --- ВАЛІДАЦІЇ ---
  validates :version, presence: true, uniqueness: true
  validates :binary_weights_payload, presence: true

  # 256KB — це межа для стабільного OTA-циклу в складних погодних умовах
  validates :binary_weights_payload, length: { maximum: 256.kilobytes }

  # [Weights Layout]: Формат моделі (tflite, edge_impulse, onnx, c_array)
  validates :model_format, inclusion: { in: MODEL_FORMATS }, allow_nil: true

  # [Compatibility Gap]: Семантичне версіонування прошивки (напр. "v2.1.0")
  validates :min_firmware_version, format: {
    with: /\Av?\d+\.\d+\.\d+/,
    message: "має відповідати формату семантичного версіонування (напр. v2.1.0)"
  }, allow_nil: true

  # [Phased Diffusion]: Відсоток розгортання (0–100)
  validates :rollout_percentage, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  }

  # [Inference Confidence]: BigDecimal валідація для критичних порогів
  validate :validate_decimal_precision_fields

  # --- КОЛБЕКИ ---
  before_save :generate_checksum, if: :binary_weights_payload_changed?

  # --- СКОУПИ ---
  scope :active, -> { where(is_active: true) }
  scope :latest, -> { order(version: :desc) }

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # ВПЕВНЕНІСТЬ ОРАКУЛА (Inference Confidence — BigDecimal Bridge)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # BigDecimal для accuracy_score, щоб уникнути похибок Float при порівнянні
  def accuracy_score
    val = metadata&.dig("accuracy_score")
    val.nil? ? nil : BigDecimal(val.to_s)
  end

  def accuracy_score=(value)
    self.metadata = (metadata || {}).merge("accuracy_score" => value&.to_s)
  end

  # BigDecimal для threshold, щоб P(anomaly) > threshold був детермінованим тригером EwsAlert
  def threshold
    val = metadata&.dig("threshold")
    val.nil? ? nil : BigDecimal(val.to_s)
  end

  def threshold=(value)
    self.metadata = (metadata || {}).merge("threshold" => value&.to_s)
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # БІНАРНИЙ МІСТОК (The Binary Bridge)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  def binary_payload
    binary_weights_payload
  end

  def payload_size
    binary_payload&.bytesize || 0
  end

  # Розбиття на сегменти для OtaTransmissionWorker (MTU-friendly)
  def chunks(chunk_size = 512)
    return [] if payload_size.zero?
    binary_payload.b.scan(/.{1,#{chunk_size}}/m)
  end

  def total_chunks(chunk_size = 512)
    return 0 if payload_size.zero?
    (payload_size.to_f / chunk_size).ceil
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # СУМІСНІСТЬ (The Compatibility Gate)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Перевіряє, чи сумісна модель з поточною активною прошивкою BioContractFirmware.
  # Повертає true, якщо min_firmware_version не задано або прошивка >= min_firmware_version.
  def firmware_compatible?(firmware_version)
    return true if min_firmware_version.blank?

    Gem::Version.new(sanitize_version(firmware_version)) >= Gem::Version.new(sanitize_version(min_firmware_version))
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # ДЕПЛОЙМЕНТ (The Phased Awakening)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Поступове розгортання моделі (Phased Diffusion).
  # percentage: 1–100 — частка пристроїв для оновлення.
  def activate!(percentage: 100)
    clamped = percentage.to_i.clamp(1, 100)

    transaction do
      # Деактивуємо застарілі знання для цієї породи
      self.class.where(tree_family_id: tree_family_id).active.update_all(is_active: false)
      update!(is_active: true, rollout_percentage: clamped)

      Rails.logger.info "🧠 [TinyML] Модель #{version} активована (#{clamped}%). Готовність до OTA-дифузії."
    end
  end

  private

  def generate_checksum
    # SHA256 гарантує, що жоден біт не був пошкоджений при завантаженні
    self.checksum = Digest::SHA256.hexdigest(binary_weights_payload)
  end

  # Нормалізація версії: "v2.1.0-silken" → "2.1.0" для Gem::Version порівняння
  def sanitize_version(ver)
    ver.to_s.sub(/\Av/i, "").split("-").first
  end

  # Валідація числових полів metadata як коректних десяткових значень
  def validate_decimal_precision_fields
    { accuracy_score: "accuracy_score", threshold: "threshold" }.each do |method, field|
      raw = metadata&.dig(field)
      next if raw.nil?

      begin
        val = BigDecimal(raw.to_s)
      rescue ArgumentError, TypeError
        errors.add(method, "має бути коректним числовим значенням")
        next
      end

      if val.negative? || val > 1
        errors.add(method, "має бути в діапазоні 0..1")
      end
    end
  end
end
