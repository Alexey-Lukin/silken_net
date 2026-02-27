# frozen_string_literal: true

class User < ApplicationRecord
  # --- АВТЕНТИФІКАЦІЯ ---
  has_secure_password validations: false
  validates :password, presence: true, length: { minimum: 8 }, if: :password_required?

  # --- ЗВ'ЯЗКИ ---
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy
  belongs_to :organization, optional: true

  # --- НОРМАЛІЗАЦІЯ ---
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # --- РОЛЬОВА МОДЕЛЬ (RBAC) ---
  enum :role, {
    investor: 0,
    forester: 1, # Отримує тривоги через AlertNotificationWorker
    admin: 2
  }, prefix: true

  # --- СКОУПИ ДЛЯ ВОРКЕРІВ ---
  scope :notifiable, -> { where.not(phone_number: [nil, ""]) }
  scope :active_foresters, -> { forester_role.notifiable }

  # --- ТОКЕНИ (Rails 8.0) ---
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_verification, expires_in: 24.hours do
    email_address
  end

  # Token для мобільного додатка лісника (Bearer Auth)
  generates_token_for :api_access

  def forest_commander?
    role_admin? || role_forester?
  end

  private

  def password_required?
    new_record? ? identities.empty? : password.present?
  end
end
