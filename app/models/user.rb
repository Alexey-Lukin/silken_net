# frozen_string_literal: true

class User < ApplicationRecord
  # --- АВТЕНТИФІКАЦІЯ ---
  # Вимикаємо стандартні валідації has_secure_password, щоб дозволити
  # створення користувачів без пароля (через Google, LinkedIn тощо)
  has_secure_password validations: false

  validates :password, presence: true, length: { minimum: 8 }, if: :password_required?

  # --- ЗВ'ЯЗКИ ---
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy # Міст до Monument Valley (OAuth провайдери)
  belongs_to :organization, optional: true

  # --- НОРМАЛІЗАЦІЯ ТА ВАЛІДАЦІЇ ---
  # Rails 7.1+: автоматично обрізає пробіли та переводить у нижній регістр
  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # --- РОЛЬОВА МОДЕЛЬ (RBAC) ---
  enum :role, {
    investor: 0, # Бачить лише фінансові дашборди та контракти
    forester: 1, # Користується мобільним додатком, отримує тривоги (EWS)
    admin: 2     # Адміністратор системи, має доступ до OTA прошивок
  }, prefix: true

  # --- ТОКЕНИ (Rails 8.0) ---

  # 1. Токен для скидання пароля (живе 15 хвилин).
  # Прив'язується до солі пароля — якщо пароль змінено, токен миттєво згорає.
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  # 2. Токен для підтвердження email при реєстрації (живе 24 години).
  generates_token_for :email_verification, expires_in: 24.hours do
    email_address
  end

  # 3. Токен для мобільного додатка лісника.
  # Безстроковий, ідеальний для відправки Bearer токена з телефону.
  generates_token_for :api_access

  private

  # Пароль вимагається ТІЛЬКИ якщо:
  # 1. Це новий користувач і він реєструється без соціальної мережі (identities порожні).
  # 2. Або якщо користувач свідомо передає пароль (наприклад, під час зміни пароля).
  def password_required?
    new_record? ? identities.empty? : password.present?
  end
end
