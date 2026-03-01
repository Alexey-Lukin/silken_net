# frozen_string_literal: true

class Identity < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Authentication Anchor) ---
  belongs_to :user

  # ⚡ [СИНХРОНІЗАЦІЯ]: Прямий доступ до контексту через користувача
  # Це дозволяє робити виклики на кшталт identity.organization або identity.wallets
  # без зайвих блукань по Матриці.
  delegate :organization, :role, to: :user, allow_nil: true
  delegate :wallets, to: :organization, allow_nil: true

  # --- ВАЛІДАЦІЇ ---
  # provider: "google_oauth2", "apple", "linkedin" тощо
  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider, message: "Цей акаунт вже прив'язаний до іншого користувача." }

  # --- СКОУПИ ---
  scope :by_provider, ->(p) { where(provider: p) }

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # OMNIAUTH ІНТЕГРАЦІЯ (The Gateway Processor)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Цей метод викликається щоразу, коли Архітектор чи Патрульний повертається
  # від зовнішнього провайдера. Він оновлює токени, зберігаючи актуальність зв'язку.
  def self.find_or_create_from_auth_hash(auth_hash)
    identity = find_or_initialize_by(provider: auth_hash.provider, uid: auth_hash.uid)

    # Завжди оновлюємо токени доступу, оскільки вони мають властивість "протухати"
    if auth_hash.credentials.present?
      identity.assign_attributes(
        access_token: auth_hash.credentials.token,
        refresh_token: auth_hash.credentials.refresh_token,
        # Зберігаємо повний зліпок профілю для безпекового аудиту та майбутніх потреб AI
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

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # ЖИТТЄВИЙ ЦИКЛ ТОКЕНА
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Перевірка надійності ключа. Якщо час вийшов — потребує повторної синхронізації.
  def token_expired?
    expires_at.present? && expires_at < Time.current
  end
end
