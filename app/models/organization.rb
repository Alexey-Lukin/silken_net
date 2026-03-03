# frozen_string_literal: true

class Organization < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Web of Responsibility) ---
  # [ВИПРАВЛЕНО: Захист Користувачів]:
  # Ми не видаляємо людей разом з організацією, щоб зберегти аудит-логи (MaintenanceRecords)
  has_many :users, dependent: :restrict_with_error

  # Фінансові контракти (Nature-as-a-Service)
  has_many :naas_contracts, dependent: :restrict_with_error

  # Лісові масиви, якими володіє або керує організація
  has_many :clusters, dependent: :destroy

  # Прямий доступ до всіх дерев та тривог через кластери
  has_many :trees, through: :clusters
  has_many :ews_alerts, through: :clusters

  # ⚡ [СИНХРОНІЗАЦІЯ]: Пряма магістраль до фінансових ресурсів
  # Це замикає ланцюжок User -> Organization -> Wallet без зайвих запитів
  has_many :wallets, through: :trees

  # --- НОРМАЛІЗАЦІЯ ---
  normalizes :billing_email, with: ->(e) { e.strip.downcase }

  # [ВИПРАВЛЕНО: EIP-55 Checksum Preservation]:
  # Прибираємо downcase, щоб не зруйнувати контрольну суму гаманця для Web3-провайдерів
  normalizes :crypto_public_address, with: ->(a) { a.strip }

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :billing_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Валідація гаманця для Web3 операцій (Polygon/Ethereum)
  # Тепер валідація дозволяє змішаний регістр (A-F)
  validates :crypto_public_address, presence: true, uniqueness: true,
            format: { with: /\A0x[a-fA-F0-9]{40}\z/, message: "має бути валідною адресою гаманця 0x..." }

  # --- БІЗНЕС-ЛОГІКА (Value Extraction) ---

  # Загальний обсяг фінансування за активними контрактами
  def active_tokens_count
    naas_contracts.active_contracts.sum(:total_funding)
  end

  # Загальний вуглецевий баланс організації (сума всіх гаманців дерев)
  # Використовуємо нову асоціацію для максимальної швидкодії
  def total_carbon_points
    wallets.sum(:balance)
  end

  # Перевірка наявності активних загроз через скоуп EwsAlert
  def under_threat?
    ews_alerts.unresolved.critical.exists?
  end

  # [ОПТИМІЗАЦІЯ: N+1 Kill]: Агрегований показник здоров'я всього фонду організації
  # Тепер розрахунок відбувається на рівні бази даних
  def health_score
    return 1.0 if clusters.empty?

    # Використовуємо SQL AVG для миттєвого розрахунку середнього значення
    # Формула: $$Health = \frac{\sum_{i=1}^{n} Cluster_{i}.health\_index}{n}$$
    clusters.average(:health_index).to_f.round(2)
  end
end
