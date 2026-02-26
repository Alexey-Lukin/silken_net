# app/models/parametric_insurance.rb
class ParametricInsurance < ApplicationRecord
  belongs_to :organization # Страхова компанія
  belongs_to :cluster      # Застрахований ліс

  enum :status, { active: 0, triggered: 1, paid: 2, expired: 3 }, prefix: true
  enum :trigger_event, { critical_fire: 0, extreme_drought: 1, insect_epidemic: 2 }

  # payout_amount: сума виплати (в стейблкоїнах або фіаті)
  # threshold_value: % знищеного лісу, при якому смарт-контракт автоматично переказує гроші
  validates :payout_amount, :threshold_value, presence: true
end
