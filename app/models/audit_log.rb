# frozen_string_literal: true

class AuditLog < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user
  belongs_to :organization
  belongs_to :auditable, polymorphic: true, optional: true

  # --- ВАЛІДАЦІЇ ---
  validates :action, presence: true
  validates :ip_address, length: { maximum: 45 }, allow_blank: true

  # --- СКОУПИ ---
  scope :recent, -> { order(created_at: :desc) }
  scope :by_action, ->(action) { where(action: action) if action.present? }
  scope :by_user, ->(user_id) { where(user_id: user_id) if user_id.present? }
  scope :by_ip, ->(ip) { where(ip_address: ip) if ip.present? }
  scope :for_period, ->(from, to) { where(created_at: from..to) if from.present? && to.present? }

  # ---------------------------------------------------------------------------
  # Hot-Path: асинхронний запис через Sidekiq (не блокує основну дію користувача)
  # ---------------------------------------------------------------------------
  def self.record_async!(attrs)
    AuditLogWorker.perform_async(attrs.deep_stringify_keys)
  end

  # ---------------------------------------------------------------------------
  # Hot-Path: масовий запис через insert_all (один INSERT замість N)
  # ---------------------------------------------------------------------------
  def self.bulk_record!(entries)
    return if entries.blank?

    now = Time.current
    rows = entries.map do |entry|
      entry.reverse_merge(created_at: now, updated_at: now).stringify_keys
    end

    insert_all(rows)
  end
end
