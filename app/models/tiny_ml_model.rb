# frozen_string_literal: true

require "digest"

class TinyMlModel < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Дерева, що використовують цей інтелект
  has_many :trees, dependent: :nullify
  # Специфікація породи (Акустика дуба != Акустика сосни)
  belongs_to :tree_family, optional: true

  # --- СТРУКТУРОВАНІ ДАНІ ---
  # Параметри: { input_shape: [1, 64], threshold: 0.85, quantized: true }
  store_accessor :metadata, :input_shape, :accuracy_score, :threshold

  # --- ВАЛІДАЦІЇ ---
  validates :version, presence: true, uniqueness: true
  validates :binary_weights_payload, presence: true
  
  # 256KB — це межа для стабільного OTA-циклу в складних погодних умовах
  validates :binary_weights_payload, length: { maximum: 256.kilobytes }

  # --- КОЛБЕКИ ---
  before_save :generate_checksum, if: :binary_weights_payload_changed?

  # --- СКОУПИ ---
  scope :active, -> { where(is_active: true) }
  scope :latest, -> { order(version: :desc) }

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
  # ДЕПЛОЙМЕНТ (The Awakening)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  def activate!
    transaction do
      # Деактивуємо застарілі знання для цієї породи
      self.class.where(tree_family_id: tree_family_id).active.update_all(is_active: false)
      update!(is_active: true)
      
      Rails.logger.info "🧠 [TinyML] Модель #{version} активована. Готовність до OTA-дифузії."
    end
  end

  private

  def generate_checksum
    # SHA256 гарантує, що жоден біт не був пошкоджений при завантаженні
    self.checksum = Digest::SHA256.hexdigest(binary_weights_payload)
  end
end
