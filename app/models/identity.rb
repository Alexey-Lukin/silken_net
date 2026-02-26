# frozen_string_literal: true

class Identity < ApplicationRecord
  belongs_to :user

  # provider: рядок (наприклад, "google_oauth2", "linkedin", "facebook")
  # uid: рядок (унікальний ID користувача в системі Гугла чи Фейсбука)

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
