# frozen_string_literal: true

class Identity < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user

  # --- ВАЛІДАЦІЇ ---
  # provider: "google_oauth2", "apple", "linkedin"
  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider, message: "Цей акаунт вже прив'язаний." }

  # --- СКОУПИ ---
  scope :by_provider, ->(p) { where(provider: p) }

  # =========================================================================
  # OMNIAUTH ІНТЕГРАЦІЯ (The Auth Processor)
  # =========================================================================

  # Цей метод викликатиметься щоразу, коли користувач повертається від провайдера
  def self.find_or_create_from_auth_hash(auth_hash)
    identity = find_or_initialize_by(provider: auth_hash.provider, uid: auth_hash.uid)

    # Завжди оновлюємо токени доступу, оскільки вони мають властивість "протухати"
    if auth_hash.credentials.present?
      identity.assign_attributes(
        access_token: auth_hash.credentials.token,
        refresh_token: auth_hash.credentials.refresh_token,
        # Зберігаємо повний зліпок профілю для безпекового аудиту
        auth_data: auth_hash.to_h
      )

      # Обробляємо час життя токена (якщо провайдер його надає)
      if auth_hash.credentials.expires_at.present?
        identity.expires_at = Time.zone.at(auth_hash.credentials.expires_at)
      end
    end

    identity.save!
    identity
  end

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТОКЕНА
  # =========================================================================

  def token_expired?
    expires_at.present? && expires_at < Time.current
  end
end
