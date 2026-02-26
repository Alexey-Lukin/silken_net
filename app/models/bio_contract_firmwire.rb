# frozen_string_literal: true

class BioContractFirmware < ApplicationRecord
  # Кластери (Ліси), які зараз працюють на цій версії контракту
  has_many :clusters

  # version: рядок, наприклад "1.0.4"
  # bytecode_payload: текст (HEX-рядок скомпільованого mruby коду, напр. "52495445...")
  validates :version, presence: true, uniqueness: true
  validates :bytecode_payload, presence: true

  # СКОУПИ
  scope :active, -> { where(is_active: true) }

  # Метод для перетворення HEX-рядка з бази на сирі байти для відправки
  def payload_bytes
    # Розбиваємо рядок по 2 символи і перетворюємо з 16-річної системи в числа
    bytecode_payload.scan(/../).map { |b| b.to_i(16) }
  end

  # Розмір прошивки в байтах. Королеві (qmain.c) потрібно знати розмір,
  # щоб вона могла розбити його на свої 13-байтні шматки (chunk_size).
  def payload_size
    payload_bytes.size
  end

  # Метод для глобального релізу нової прошивки на весь ліс
  def deploy_globally!
    transaction do
      # Деактивуємо всі старі версії
      self.class.update_all(is_active: false)

      # Активуємо поточну
      update!(is_active: true)

      # TODO: Створити фонову задачу (ActiveJob), яка почне по черзі
      # "дзвонити" всім онлайн-Королевам і передавати їм новий bytecode_payload
      # BroadcastFirmwareJob.perform_later(self.id)
    end
  end
end
