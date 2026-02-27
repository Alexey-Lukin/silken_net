# frozen_string_literal: true

class Identity < ApplicationRecord
  belongs_to :user

  # provider: рядок (наприклад, "google_oauth2", "linkedin", "facebook")
  # uid: рядок (унікальний ID користувача в системі Гугла чи Фейсбука)

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: { scope: :provider }

  # Скоуп для швидкої перевірки типу входу
  scope :by_provider, ->(p) { where(provider: p) }
end
