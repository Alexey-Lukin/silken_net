# frozen_string_literal: true

class User < ApplicationRecord
  # --- АВТЕНТИФІКАЦІЯ ---
  has_secure_password validations: false
  validates :password, presence: true, length: { minimum: 8 }, if: :password_required?

  # --- ЗВ'ЯЗКИ ---
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy
  belongs_to :organization, optional: true
  
  # Зв'язок з журналом робіт (не даємо видалити лісника, якщо він ремонтував шлюзи)
  has_many :maintenance_records, dependent: :restrict_with_error

  # --- НОРМАЛІЗАЦІЯ ---
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  # [ВИПРАВЛЕНО]: Зберігаємо цифри ТА знак плюса для E.164 формату
  normalizes :phone_number, with: ->(p) { p.to_s.gsub(/[^0-9+]/, "") }

  # --- РОЛЬОВА МОДЕЛЬ (RBAC) ---
  enum :role, {
    investor: 0, # Дашборд, фінанси
    forester: 1, # Мобільний додаток, тривоги
    admin: 2     # Повний доступ
  }, prefix: true

  # --- СКОУПИ ДЛЯ ВОРКЕРІВ ---
  scope :notifiable, -> { where.not(phone_number: [nil, ""]) }
  
  # [ВИПРАВЛЕНО]: Використовуємо правильний префікс role_forester
  scope :active_foresters, -> { role_forester.notifiable }
  
  # Скоуп для тих, хто реально в полі (перевіряємо їхній пульс)
  scope :online, -> { where("last_seen_at >= ?", 30.minutes.ago) }

  # --- ТОКЕНИ (Rails 8.0) ---
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_verification, expires_in: 24.hours do
    email_address
  end

  # Токен для довготривалих API-сесій (мобільний додаток)
  generates_token_for :api_access

  # --- МЕТОДИ ---
  def forest_commander?
    role_admin? || role_forester?
  end

  # Зручний хелпер для фронтенду
  def full_name
    "#{first_name} #{last_name}".strip.presence || email_address
  end

  private

  def password_required?
    new_record? ? identities.empty? : password.present?
  end
end
