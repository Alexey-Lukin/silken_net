# frozen_string_literal: true

class BioContractFirmware < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Кластери (Ліси), які зараз працюють на цій версії
  has_many :clusters, foreign_key: :active_firmware_id

  # --- ВАЛІДАЦІЇ ---
  validates :version, presence: true, uniqueness: true

  # Строга HEX-валідація (Case-insensitive)
  validates :bytecode_payload, presence: true, format: {
    with: /\A([a-fA-F0-9]{2})+\z/,
    message: "має бути чистим HEX-рядком парної довжини (кратним байту)"
  }

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
  # ЖИТТЄВИЙ ЦИКЛ (The Global Evolution)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  def deploy_globally!
    transaction do
      # 1. Кенозис старих версій
      self.class.active.where.not(id: id).update_all(is_active: false)

      # 2. Активація нової істини
      update!(is_active: true)

      # 3. Синхронізація кластерів
      # Ми лише позначаємо версію, а OtaTransmissionWorker підхопить її за розкладом
      Rails.logger.info "🚀 [OTA] Біо-Контракт #{version} активовано. Готовність: #{payload_size} байт."
    end
  end
end
