# frozen_string_literal: true

class Tree < ApplicationRecord
  belongs_to :cluster, optional: true
  belongs_to :tiny_ml_model
  belongs_to :tree_species
  # Гаманець знищується разом з деревом, якщо воно вмирає/спилюється
  has_one :wallet, dependent: :destroy
  has_one :device_calibration, dependent: :destroy
  # Історія пульсу знищується (або можна залишити nullify для архіву)
  has_many :telemetry_logs, dependent: :destroy
  has_many :maintenance_records, as: :maintainable

  # Додаткові поля в БД:
  # - species: string (Порода: "Дуб", "Сосна")
  # - latitude: decimal (GPS)
  # - longitude: decimal (GPS)
  # - planted_at: datetime (Дата встановлення анкера)

  # Автоматично створюємо гаманець при реєстрації нового дерева
  after_create :build_default_wallet

  # did - це 32-бітний хеш, згенерований в main.c з UID STM32 та шуму кристала
  validates :did, presence: true, uniqueness: true
  # Геопросторовий блок (для DSM та 3D-радіотрас)
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :altitude, numericality: true, allow_nil: true

  # Допоміжний метод перевірки, чи пристрій має фізичну прив'язку на карті
  def geolocated?
    latitude.present? && longitude.present?
  end

  private

  def build_default_wallet
    create_wallet!(balance: 0)
  end
end
