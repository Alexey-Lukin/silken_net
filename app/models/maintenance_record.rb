# frozen_string_literal: true

class MaintenanceRecord < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user
  belongs_to :maintainable, polymorphic: true
  belongs_to :ews_alert, optional: true

  # Фотодокази для аудиту інвесторами (Silken Net Trust Protocol)
  # has_many_attached :photos

  # --- ТИПИ РОБІТ (The Intervention) ---
  enum :action_type, {
    installation: 0,    # Монтаж
    inspection: 1,      # Огляд
    cleaning: 2,        # Очищення (панелі/датчики)
    repair: 3,          # Ремонт заліза
    decommissioning: 4  # Демонтаж
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :action_type, :performed_at, presence: true
  validates :notes, presence: true, length: { minimum: 10 }
  validates :performed_at, comparison: { less_than_or_equal_to: -> { Time.current } }

  # --- СКОУПИ ---
  scope :recent, -> { order(performed_at: :desc) }
  scope :by_type, ->(type) { where(action_type: type) }

  # =========================================================================
  # КОЛБЕКИ (The Healing Protocol)
  # =========================================================================

  # [ВИПРАВЛЕНО]: Ми відмовилися від heal_ecosystem! всередині моделі.
  # Замість цього запускаємо асинхронний воркер, що гарантує 100% доставку
  # змін статусу навіть при тимчасових збоях бази даних.
  after_create_commit :trigger_ecosystem_healing!

  private

  def trigger_ecosystem_healing!
    # Викликаємо "М'яз зцілення" (NAM-ŠID Healing).
    # Він обробить і логіку актуаторів, і закриття EwsAlert із вірними префіксами (status_resolved?).
    EcosystemHealingWorker.perform_async(self.id)
  end
end
