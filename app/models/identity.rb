# frozen_string_literal: true

class Identity < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user

  # ⚡ [СИНХРОНІЗАЦІЯ]: Прямий доступ до контексту через користувача
  delegate :organization, :role, to: :user, allow_nil: true
  delegate :wallets, to: :organization, allow_nil: true

  # --- ВАЛІДАЦІЇ ---
  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider, message: "Цей акаунт вже прив'язаний." }

  # --- СКОУПИ ---
  scope :by_provider, ->(p) { where(provider: p) }

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # OMNIAUTH ІНТЕГРАЦІЯ
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  def self.find_or_create_from_auth_hash(auth_hash)
    identity = find_or_initialize_by(provider: auth_hash.provider, uid: auth_hash.uid)

    if auth_hash.credentials.present?
      identity.assign_attributes(
        access_token: auth_hash.credentials.token,
        refresh_token: auth_hash.credentials.refresh_token,
        auth_data: auth_hash.to_h # Зберігаємо для аудиту
      )

      if auth_hash.credentials.expires_at.present?
        identity.expires_at = Time.zone.at(auth_hash.credentials.expires_at)
      end
    end

    identity.save!
    identity
  end

  def token_expired?
    expires_at.present? && expires_at < Time.current
  end
end
