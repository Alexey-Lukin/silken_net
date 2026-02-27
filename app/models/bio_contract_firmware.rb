# frozen_string_literal: true

class BioContractFirmware < ApplicationRecord
  # Кластери (Ліси), які зараз працюють на цій версії контракту
  has_many :clusters

  # version: рядок, наприклад "1.0.4"
  # bytecode_payload: HEX-рядок скомпільованого mruby коду
  validates :version, presence: true, uniqueness: true
  validates :bytecode_payload, presence: true

  scope :active, -> { where(is_active: true) }

  # [ОПТИМІЗАЦІЯ]: Перетворюємо HEX у бінарний рядок одним подихом
  # Це ідеально для CoapClient.put(url, firmware.binary_payload)
  def binary_payload
    [bytecode_payload].pack("H*")
  end

  def payload_size
    binary_payload.bytesize
  end

  def deploy_globally!
    transaction do
      self.class.active.update_all(is_active: false)
      update!(is_active: true)

      # Викликаємо "Патрульного" для доставки знань
      # BroadcastFirmwareWorker.perform_async(self.id)
    end
  end
end
