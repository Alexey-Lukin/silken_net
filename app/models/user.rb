# frozen_string_literal: true

class User < ApplicationRecord
  # --- АВТЕНТИФІКАЦІЯ ---
  has_secure_password validations: false
  validates :password, presence: true, length: { minimum: 8 }, if: :password_required?

  # --- ЗВ'ЯЗКИ ---
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy
  belongs_to :organization, optional: true
  
  # [НОВЕ]: Зв'язок з журналом робіт
  has_many :maintenance_records, dependent: :restrict_with_error

  # --- НОРМАЛІЗАЦІЯ ---
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  # Додаємо нормалізацію телефону для SMS-шлюзів
  normalizes :phone_number, with: ->(p) { p.gsub(/\D/, "") }

  # --- РОЛЬОВА МОДЕЛЬ (RBAC) ---
  enum :role, {
    investor: 0,
    forester: 1, # Отримує тривоги через AlertNotificationWorker
    admin: 2
  }, prefix: true

  # --- СКОУПИ ДЛЯ ВОРКЕРІВ ---
  scope :notifiable, -> { where.not(phone_number: [nil, ""]) }
  scope :active_foresters, -> { forester_role.notifiable }
  # [НОВЕ]: Скоуп для тих, хто реально в полі
  scope :online, -> { where("last_seen_at >= ?", 30.minutes.ago) }

  # --- ТОКЕНИ (Rails 8.0) ---
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_verification, expires_in: 24.hours do
    email_address
  end

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
