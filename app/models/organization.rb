# frozen_string_literal: true

class Organization < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Web of Responsibility) ---
  # Працівники цієї організації (Інвестори, Лісники, Адміни)
  has_many :users, dependent: :destroy
  
  # Фінансові контракти (Nature-as-a-Service)
  # Не даємо видалити організацію, якщо є активні фінансові зобов'язання
  has_many :naas_contracts, dependent: :restrict_with_error
  
  # Лісові масиви, якими володіє або керує організація
  has_many :clusters, dependent: :destroy
  
  # Прямий доступ до всіх дерев та тривог через кластери
  has_many :trees, through: :clusters
  has_many :ews_alerts, through: :clusters

  # --- НОРМАЛІЗАЦІЯ ---
  normalizes :billing_email, with: ->(e) { e.strip.downcase }
  normalizes :crypto_public_address, with: ->(a) { a.strip.downcase }

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :billing_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  # Валідація гаманця для Web3 операцій (Polygon/Ethereum)
  validates :crypto_public_address, presence: true, uniqueness: true,
            format: { with: /\A0x[a-fA-F0-9]{40}\z/, message: "має бути валідною адресою гаманця 0x..." }

  # --- БІЗНЕС-ЛОГІКА (Value Extraction) ---

  # Загальний обсяг фінансування за активними контрактами
  def active_tokens_count
    naas_contracts.active_contracts.sum(:total_funding) 
  end

  # Загальний вуглецевий баланс організації (сума всіх гаманців дерев)
  def total_carbon_points
    trees.joins(:wallet).sum("wallets.balance")
  end

  # [СИНХРОНІЗОВАНО]: Перевірка наявності активних загроз через скоуп EwsAlert
  def under_threat?
    ews_alerts.unresolved.critical.exists?
  end

  # [НОВЕ]: Агрегований показник здоров'я всього фонду організації
  # Повертає значення від 0.0 до 1.0 (середнє по всіх кластерах)
  def health_score
    return 1.0 if clusters.empty?
    
    # Викликаємо метод health_index, який ми зашліфували в моделі Cluster
    scores = clusters.map(&:health_index)
    (scores.sum / scores.size).round(2)
  end
end
