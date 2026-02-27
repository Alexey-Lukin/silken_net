class ParametricInsurance < ApplicationRecord
  belongs_to :organization # Страхова компанія або пул інвесторів
  belongs_to :cluster      # Застрахований ліс

  enum :status, { active: 0, triggered: 1, paid: 2, expired: 3 }, prefix: true
  enum :trigger_event, { critical_fire: 0, extreme_drought: 1, insect_epidemic: 2 }

  # payout_amount: сума виплати (в стейблкоїнах)
  # threshold_value: % знищеного/аномального лісу для виплати
  validates :payout_amount, :threshold_value, presence: true
  validates :threshold_value, numericality: { greater_than: 0, less_than_or_equal_to: 100 }

  # [НОВЕ]: Зв'язок з блокчейн-транзакцією виплати
  has_one :blockchain_transaction, as: :sourceable

  # Метод автоматичної перевірки умов виплати (аналогічно до NaasContract)
  def evaluate_trigger!(anomalous_percentage)
    return unless status_active?

    if anomalous_percentage >= threshold_value
      transaction do
        update!(status: :triggered)
        Rails.logger.warn "💸 [INSURANCE] Поріг #{threshold_value}% перевищено (#{anomalous_percentage}%). Страховий випадок активовано."
        
        # TODO: Запустити InsurancePayoutWorker.perform_async(self.id)
      end
    end
  end
end
