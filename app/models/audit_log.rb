# frozen_string_literal: true

class AuditLog < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user
  belongs_to :organization
  belongs_to :auditable, polymorphic: true, optional: true

  # --- ВАЛІДАЦІЇ ---
  validates :action, presence: true

  # --- СКОУПИ ---
  scope :recent, -> { order(created_at: :desc) }
  scope :by_action, ->(action) { where(action: action) if action.present? }
  scope :by_user, ->(user_id) { where(user_id: user_id) if user_id.present? }
end
