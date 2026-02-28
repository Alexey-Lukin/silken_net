# frozen_string_literal: true

class BioContractFirmware < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Кластери (Ліси), які зараз працюють на цій версії контракту
  has_many :clusters

  # --- ВАЛІДАЦІЇ ---
  # version: "1.0.4"
  validates :version, presence: true, uniqueness: true
  
  # Сувора перевірка, що це дійсно HEX, інакше .pack("H*") може видати несподіваний результат
  validates :bytecode_payload, presence: true, format: { 
    with: /\A[a-fA-F0-9]+\z/, 
    message: "Має бути чистим HEX-рядком" 
  }

  # --- СКОУПИ ---
  scope :active, -> { where(is_active: true) }

  # =========================================================================
  # БІНАРНА МАТЕМАТИКА (OTA Chunking)
  # =========================================================================

  def binary_payload
    [bytecode_payload].pack("H*")
  end

  def payload_size
    binary_payload.bytesize
  end

  # Розрізаємо прошивку на чанки для відправки через CoAP (напр. по 512 байт)
  # Це ідеально лягає на логіку нашого OtaTransmissionWorker
  def chunks(chunk_size = 512)
    binary_payload.b.scan(/.{1,#{chunk_size}}/m)
  end

  # Скільки всього чанків потрібно відправити (корисно для Uri-Query: ?total=10)
  def total_chunks(chunk_size = 512)
    (payload_size.to_f / chunk_size).ceil
  end

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ (The Awakening)
  # =========================================================================

  def deploy_globally!
    transaction do
      # Деактивуємо всі ІНШІ прошивки
      self.class.active.where.not(id: id).update_all(is_active: false)
      update!(is_active: true)

      # Викликаємо "Патрульного" для доставки знань
      # BroadcastFirmwareWorker.perform_async(self.id)
    end
    
    Rails.logger.info "🚀 [OTA] Біо-Контракт #{version} активовано. Розмір: #{payload_size} байт (#{total_chunks} чанків)."
  end
end
