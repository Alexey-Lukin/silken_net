# frozen_string_literal: true

class Organization < ApplicationRecord
  # Працівники цієї організації
  has_many :users, dependent: :destroy
  # Фінансові контракти
  has_many :naas_contracts, dependent: :restrict_with_error
  # Лісові масиви, якими володіє або керує організація
  has_many :clusters, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :billing_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  # ВАЖЛИВО: Валідація гаманця для Web3 операцій (Polygon/Ethereum адрес)
  validates :crypto_public_address, presence: true, 
            format: { with: /\A0x[a-fA-F0-9]{40}\z/, message: "має бути валідною адресою гаманця 0x..." }

  # Зручний метод для BlockchainBurningService
  def active_tokens_count
    naas_contracts.active.sum(:total_value) # Приклад логіки
  end
end
