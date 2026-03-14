# frozen_string_literal: true

module Dclimate
  # [COSMIC EYE]: Помилка орбітальної затримки — супутник не зміг верифікувати
  # через хмарність або кронопокрив. Sidekiq ретраїтиме до 48+ годин.
  class OrbitalLagError < StandardError; end

  # = ===================================================================
  # 🛰️ DCLIMATE VERIFICATION SERVICE (Cosmic Eye — Double Consensus)
  # = ===================================================================
  # Верифікація EWS-алертів через супутникові дані dClimate.
  # Запобігає страховому шахрайству шляхом подвійного консенсусу:
  #   1. fire_confirmed   → satellite_verified  → InsurancePayoutWorker
  #   2. clear_sky_no_fire → rejected_fraud      → BurnCarbonTokensWorker (Slashing)
  #   3. obscured_by_clouds → OrbitalLagError    → Sidekiq retry (до 48 годин)
  #
  # Використання:
  #   Dclimate::VerificationService.new(ews_alert).perform
  class VerificationService
    OUTCOMES = %i[fire_confirmed clear_sky_no_fire obscured_by_clouds].freeze

    def initialize(alert)
      @alert = alert
    end

    def perform
      outcome = query_dclimate_api

      case outcome
      when :fire_confirmed
        handle_fire_confirmed
      when :clear_sky_no_fire
        handle_clear_sky_no_fire
      when :obscured_by_clouds
        handle_obscured_by_clouds
      end
    end

    private

    # [MOCK]: Симуляція API-виклику до dClimate.
    # У продакшені замінити на реальний HTTP-запит до dClimate API
    # з координатами алерту та часовим вікном.
    def query_dclimate_api
      OUTCOMES.sample
    end

    # Супутник підтвердив пожежу/посуху → виплата страховки
    def handle_fire_confirmed
      @alert.update!(
        satellite_status: :verified,
        dclimate_ref: generate_dclimate_ref
      )

      Rails.logger.info "🛰️ [Cosmic Eye] Алерт ##{@alert.id} підтверджено супутником. Ініціація виплати."

      trigger_insurance_payout
    end

    # Супутник бачить ясне небо без пожежі → шахрайство → slashing
    def handle_clear_sky_no_fire
      @alert.update!(
        satellite_status: :rejected_fraud,
        dclimate_ref: generate_dclimate_ref
      )

      Rails.logger.warn "🚨 [Cosmic Eye] Алерт ##{@alert.id} відхилено — ясне небо. Slashing Protocol."

      trigger_slashing
    end

    # Хмарність/кронопокрив → ретрай через Sidekiq
    def handle_obscured_by_clouds
      Rails.logger.info "☁️ [Cosmic Eye] Алерт ##{@alert.id} — хмарність/кронопокрив. Очікуємо наступний проліт."

      raise Dclimate::OrbitalLagError,
            "Satellite pass obscured by clouds/canopy for alert ##{@alert.id}. Retrying on next orbit."
    end

    def generate_dclimate_ref
      "dclimate:#{SecureRandom.hex(12)}"
    end

    # Знаходимо активні страховки кластера та тригеримо виплату
    def trigger_insurance_payout
      return unless @alert.cluster

      ParametricInsurance.where(cluster: @alert.cluster, status: :triggered).find_each do |insurance|
        InsurancePayoutWorker.perform_async(insurance.id)
      end
    end

    # Ініціюємо slashing через BurnCarbonTokensWorker
    def trigger_slashing
      return unless @alert.cluster

      organization = @alert.cluster.organization
      return unless organization

      NaasContract.where(cluster: @alert.cluster).where.not(status: :breached).find_each do |contract|
        BurnCarbonTokensWorker.perform_async(organization.id, contract.id, @alert.tree_id)
      end
    end
  end
end
