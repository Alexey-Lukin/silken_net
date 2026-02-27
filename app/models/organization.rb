# frozen_string_literal: true

class Organization < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Web of Responsibility) ---
  # Працівники цієї організації (Інвестори, Лісники, Адміни)
  has_many :users, dependent: :destroy
  # Фінансові контракти (Nature-as-a-Service)
  has_many :naas_contracts, dependent: :restrict_with_error
  # Лісові масиви, якими володіє або керує організація
  has_many :clusters, dependent: :destroy
  # Прямий доступ до всіх дерев через кластери
  has_many :trees, through: :clusters

  # --- НОРМАЛІЗАЦІЯ ---
  normalizes :billing_email, with: ->(e) { e.strip.downcase }
  # Нормалізація крипто-адреси (завжди зберігаємо в нижньому регістрі для уникнення дублікатів)
  normalizes :crypto_public_address, with: ->(a) { a.strip.downcase }

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :billing_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  # ВАЖЛИВО: Валідація гаманця для Web3 операцій (Polygon/Ethereum адрес)
  # [ЗМІНА]: Додано uniqueness: true, щоб уникнути конфліктів при нарахуванні токенів
  validates :crypto_public_address, presence: true, uniqueness: true,
            format: { with: /\A0x[a-fA-F0-9]{40}\z/, message: "має бути валідною адресою гаманця 0x..." }

  # --- БІЗНЕС-ЛОГІКА (Value Extraction) ---

  # Зручний метод для BlockchainBurningService
  # [КОРЕКЦІЯ]: Використовуємо scope :active_contracts, який ми прописали в NaasContract
  def active_tokens_count
    naas_contracts.active_contracts.sum(:total_funding) 
  end

  # [НОВЕ]: Загальний вуглецевий баланс організації по всіх деревах
  def total_carbon_points
    trees.joins(:wallet).sum("wallets.balance")
  end

  # [НОВЕ]: Чи є в організації активні алерти в будь-якому кластері?
  def under_threat?
    clusters.joins(:ews_alerts).where(ews_alerts: { resolved_at: nil }).exists?
  end
end
