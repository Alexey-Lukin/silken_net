# frozen_string_literal: true

class Organization < ApplicationRecord
  include EthAddressValidatable

  # --- ЗВ'ЯЗКИ (The Web of Responsibility) ---
  # [ВИПРАВЛЕНО: Захист Користувачів]:
  # Ми не видаляємо людей разом з організацією, щоб зберегти аудит-логи (MaintenanceRecords)
  has_many :users, dependent: :restrict_with_error

  # Фінансові контракти (Nature-as-a-Service)
  has_many :naas_contracts, dependent: :restrict_with_error

  # Лісові масиви, якими володіє або керує організація
  has_many :clusters, dependent: :destroy

  # [ARCH.57] Compliance-журнал переживає організацію: delete_all стирав
  # integrity-chain разом із Org (carbon-registry вимагає незнищенність).
  # Узгоджено з users/naas_contracts — Org з журналом не видаляється.
  has_many :audit_logs, dependent: :restrict_with_error

  # Прямий доступ до всіх дерев, шлюзів та тривог через кластери
  has_many :trees, through: :clusters
  has_many :gateways, through: :clusters
  has_many :ews_alerts, through: :clusters

  # ⚡ [ВИПРАВЛЕНО: The Join Abyss]: Пряма магістраль до фінансових ресурсів.
  # Денормалізований зв'язок через organization_id у wallets замість 4-рівневого JOIN
  # (Organization → Clusters → Trees → Wallets). Це критично для total_carbon_points.
  has_many :wallets, dependent: :nullify

  # Логотип організації (The Brain Map)
  has_one_attached :logo

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
  validates_eth_address :crypto_public_address, presence: true, uniqueness: true

  # [KYC.1] KYC чіпляється до АДРЕСИ-бенефіціара (custodial-мінт іде сюди, коли
  # wallet без власної адреси): зміна адреси = новий суб'єкт верифікації →
  # статус скидається у pending і верифікація йде заново (Hadron / dev-simulate).
  HADRON_KYC_STATUSES = %w[pending approved rejected].freeze
  validates :hadron_kyc_status, inclusion: { in: HADRON_KYC_STATUSES }

  before_update :reset_hadron_kyc_on_address_change
  after_commit :enqueue_hadron_kyc_verification, if: :saved_change_to_crypto_public_address?

  # Пороги тривоги та AI-чутливість (The Brain Map)
  validates :alert_threshold_critical_z, numericality: { greater_than: 0, less_than_or_equal_to: 10 }, allow_nil: true
  validates :ai_sensitivity, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  # --- Data Residency (Зона 4: GDPR/Sharding) ---
  SUPPORTED_DATA_REGIONS = %w[eu-west eu-central us-east us-west ap-southeast].freeze
  validates :data_region, inclusion: { in: SUPPORTED_DATA_REGIONS }, allow_nil: true

  # --- БІЗНЕС-ЛОГІКА (Value Extraction) ---

  # Кешований лічильник дерев для масштабування (уникає повільного COUNT на мільйонах записів)
  def cached_trees_count
    Rails.cache.fetch("organization_#{id}_trees_count", expires_in: 1.hour) do
      trees.count
    end
  end

  # Кількість кластерів організації
  def total_clusters
    clusters.count
  end

  # Загальна сума інвестицій за всіма контрактами
  def total_invested
    naas_contracts.sum(:total_funding).to_f
  end

  # Загальний обсяг фінансування за активними контрактами
  def active_tokens_count
    naas_contracts.active.sum(:total_funding)
  end

  # Загальний вуглецевий баланс організації (сума всіх гаманців дерев)
  # [ОПТИМІЗАЦІЯ]: Використовуємо прямий зв'язок (один SELECT замість 4-рівневого JOIN)
  def total_carbon_points
    wallets.sum(:balance)
  end

  # Перевірка наявності активних загроз через скоуп EwsAlert
  def under_threat?
    ews_alerts.unresolved.critical.exists?
  end

  # [ОПТИМІЗАЦІЯ: N+1 Kill]: Агрегований показник здоров'я всього фонду організації
  # health_index — денормалізована колонка в clusters, оновлюється ClusterHealthCheckWorker
  # раз на добу після звіту Оракула. Тому AVG виконується на кешованих значеннях.
  def health_score
    return 1.0 if clusters.empty?

    # Використовуємо SQL AVG для миттєвого розрахунку середнього значення
    # Формула: $$Health = \frac{\sum_{i=1}^{n} Cluster_{i}.health\_index}{n}$$
    clusters.average(:health_index).to_f.round(2)
  end

  private

  # [KYC.1] Явний одночасний сет статусу (verify-воркер / seeds) має пріоритет.
  def reset_hadron_kyc_on_address_change
    return unless will_save_change_to_crypto_public_address?
    return if will_save_change_to_hadron_kyc_status?

    self.hadron_kyc_status = "pending"
  end

  def enqueue_hadron_kyc_verification
    HadronKycVerificationWorker.perform_async("Organization", id)
  end
end
