# frozen_string_literal: true

class NaasContract < ApplicationRecord
  # Сторона 1: Інвестор / Клієнт
  belongs_to :organization
  # Сторона 2: Фізичний ліс
  belongs_to :cluster

  enum :status, {
    draft: 0,       # Контракт готується, інвестор ще не переказав фінансування
    active: 1,      # Спонсорування йде, дерева здорові, мінтинг токенів дозволено
    fulfilled: 2,   # Термін дії (напр., 10 років) успішно завершено
    breached: 3     # Контракт розірвано (ліс згорів / вирубаний) - Slashing Protocol
  }, prefix: true

  validates :total_funding, presence: true, numericality: { greater_than: 0 }
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  scope :active_contracts, -> { where(status: :active) }

  # =========================================================================
  # THE SLASHING PROTOCOL (D-MRV Арбітраж)
  # =========================================================================
  # Цей метод має викликатися щоденним cron-job.
  def check_cluster_health!
    return unless status_active?

    total_trees = cluster.trees.count
    return if total_trees.zero?

    # [ЗМІНА]: Використовуємо status_code (2 - Аномалія/Пожежа, 3 - Вандалізм)
    # Це синхронізовано з нашим TelemetryUnpackerService та AlertDispatchService.
    anomalous_trees = cluster.trees
                             .joins(:telemetry_logs)
                             .where(telemetry_logs: { 
                               status_code: [2, 3], 
                               created_at: 24.hours.ago..Time.current 
                             })
                             .distinct
                             .count

    # Жорстке правило Web3 екології: якщо більше 20% кластера знищено,
    # контракт вважається порушеним (Breached).
    if anomalous_trees > (total_trees * 0.20)
      transaction do
        update!(status: :breached)

        # Залишаємо лог для системи та інвесторів
        Rails.logger.warn "🚨 [D-MRV] NaasContract #{id} порушено! Втрата понад 20% дерев."

        # [ЗМІНА]: Активуємо воркер для спалювання токенів (Slashing Protocol)
        # Це змусить інвестора відчути фізичну втрату лісу через блокчейн.
        BurnCarbonTokensWorker.perform_async(self.organization_id, self.id)
      end
    end
  end

  private

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?

    if end_date < start_date
      errors.add(:end_date, "повинна бути пізніше дати початку")
    end
  end
end
