# frozen_string_literal: true

class TinyMlModel < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Дерева, які зараз використовують ці ваги нейромережі
  has_many :trees, dependent: :nullify
  # Модель специфічна для родини (напр. акустичний профіль Сосни відрізняється від Дуба)
  belongs_to :tree_family, optional: true

  # --- ВАЛІДАЦІЇ ---
  validates :version, presence: true, uniqueness: true
  validates :binary_weights_payload, presence: true
  
  # Обмеження для LoRa/CoAP OTA: зазвичай TinyML моделі для мікроконтролерів 
  # вкладаються в 256KB. Більше — ризик для стабільності мережі.
  validates :binary_weights_payload, length: { maximum: 256.kilobytes }

  # --- СКОУПИ ---
  scope :active, -> { where(is_active: true) }
  scope :for_family, ->(family_id) { where(tree_family_id: family_id) }

  # --- МЕТОДИ (The Binary Bridge) ---

  # Розмір у байтах для розбивки на чанки в OtaTransmissionWorker
  def payload_size
    binary_weights_payload.bytesize
  end

  # Аліас для уніфікації з OtaTransmissionWorker
  def binary_payload
    binary_weights_payload
  end

  # Перевірка цілісності (використовується для верифікації після завантаження)
  def checksum
    Digest::SHA256.hexdigest(binary_weights_payload)
  end

  # =========================================================================
  # ДЕПЛОЙМЕНТ (The Awakening)
  # =========================================================================
  
  def activate!
    transaction do
      # Деактивуємо попередні моделі для цієї родини дерев
      self.class.where(tree_family_id: tree_family_id).active.update_all(is_active: false)
      update!(is_active: true)
    end
    
    Rails.logger.info "🧠 [TinyML] Модель #{version} активована для родини #{tree_family&.name}."
  end
end
