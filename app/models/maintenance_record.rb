# frozen_string_literal: true

class MaintenanceRecord < ApplicationRecord
  include GeoLocatable
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user
  belongs_to :maintainable, polymorphic: true
  belongs_to :ews_alert, optional: true

  # Evidence Protocol (Trust Protocol) — фото до/після для аудиту Series C.
  # Variant :thumb генерується VIPS у фоні (queued job), не блокуючи запит.
  # При десятках мільйонів записів: зберігання на S3 + GCS mirror, роздача через CDN.
  has_many_attached :photos do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 200, 200 ]
  end

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

  # OpEx-метрики для unit-економіки (Series C Financial Tracking)
  validates :labor_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :parts_cost,  numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Hardware State Sync
  validates :hardware_verified, inclusion: { in: [ true, false ] }

  # System-generated records (provisioning, slashing) may skip photo requirement
  attr_accessor :skip_photo_validation

  # Evidence Protocol: фото обов'язкові при монтажі та ремонті
  validate :photos_required_for_critical_actions

  # Тип вкладень — тільки зображення, max 20 МБ кожне, max 10 фото на запис
  validates :photos,
            content_type: { in: %w[image/jpeg image/png image/webp image/heic image/heif],
                            message: "має бути зображенням (JPEG, PNG, WebP, HEIC)" },
            size: { less_than: 20.megabytes, message: "не може перевищувати 20 МБ" },
            limit: { max: 10, message: "не більше 10 фото на запис" }

  # --- СКОУПИ ---
  scope :recent,            -> { order(performed_at: :desc) }
  scope :by_type,           ->(type) { where(action_type: type) }
  scope :hardware_verified, -> { where(hardware_verified: true) }
  scope :with_gps,          -> { where.not(latitude: nil, longitude: nil) }

  # =========================================================================
  # КОЛБЕКИ (The Healing Protocol)
  # =========================================================================

  # [ВИПРАВЛЕНО]: Ми відмовилися від heal_ecosystem! всередині моделі.
  # Замість цього запускаємо асинхронний воркер, що гарантує 100% доставку
  # змін статусу навіть при тимчасових збоях бази даних.
  after_create_commit :trigger_ecosystem_healing!

  # =========================================================================
  # МЕТОДИ
  # =========================================================================

  # OpEx-вартість одного запису для звітності Series C.
  # Базова ставка 50 $/год — override через ENV для регіональних ринків.
  LABOR_RATE_PER_HOUR = ENV.fetch("PATROL_LABOR_RATE", 50).to_f

  def total_cost
    (labor_hours.to_f * LABOR_RATE_PER_HOUR) + parts_cost.to_f
  end

  private

  def trigger_ecosystem_healing!
    # Викликаємо "М'яз зцілення" (NAM-ŠID Healing).
    # Він обробить і логіку актуаторів, і закриття EwsAlert із вірними префіксами (status_resolved?).
    EcosystemHealingWorker.perform_async(self.id)
  end

  # Trust Protocol: ремонт і монтаж без фото — не proof of care, а просто слова.
  def photos_required_for_critical_actions
    return if skip_photo_validation
    return unless action_type_repair? || action_type_installation?
    return if photos.any?

    errors.add(:photos, "обов'язкові для типів 'repair' та 'installation' (Trust Protocol)")
  end
end
