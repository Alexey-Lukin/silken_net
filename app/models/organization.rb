# frozen_string_literal: true

class Organization < ApplicationRecord
  # Працівники цієї організації (Лісники, Менеджери, Інвестори)
  has_many :users, dependent: :destroy
  # Фінансові контракти цієї організації
  has_many :naas_contracts, dependent: :restrict_with_error

  validates :billing_email, presence: true
  validates :name, presence: true, uniqueness: true
end
