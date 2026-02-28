# frozen_string_literal: true

class InsurancePayoutWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 10 # Найвищий пріоритет: фінансові зобов'язання непорушні

  def perform(insurance_id)
    insurance = ParametricInsurance.find(insurance_id)

    # Виконуємо лише якщо тригер активовано, але виплата ще не проведена
    return unless insurance.status_triggered?

    organization = insurance.cluster.organization

    # 1. ПІДГОТОВКА ТРАНЗАКЦІЇ (Internal Ledger)
    # Шукаємо гаманець-якір (напр. гаманець першого дерева в кластері)
    # або системний гаманець для аудиту.
    audit_wallet = insurance.cluster.trees.first&.wallet

    unless audit_wallet
      Rails.logger.error "🛑 [Insurance] Спроба виплати ##{insurance_id} без валідного гаманця в кластері."
      return
    end

    ActiveRecord::Base.transaction do
      # Блокуємо запис страховки для запобігання Race Condition
      insurance.lock!
      return unless insurance.status_triggered? # Подвійна перевірка після блокування

      # Створюємо запис у блокчейн-черзі
      tx = insurance.create_blockchain_transaction!(
        wallet: audit_wallet,
        amount: insurance.payout_amount,
        token_type: :carbon_coin, # В майбутньому може бути :usdc_stable
        to_address: organization.crypto_public_address,
        status: :pending,
        notes: "Страхове відшкодування за контрактом ##{insurance.id}. Тригер: #{insurance.trigger_event}."
      )

      # 2. ЗАПУСК ВЕБ3-КОНВЕЄРА
      # Викликаємо спеціалізований сервіс для переказу стейблкоїнів/токенів
      # BlockchainInsuranceService.call(tx.id)

      # Оновлюємо статус страховки (вона тепер в процесі виплати)
      insurance.status_paid!

      Rails.logger.info "💳 [Insurance] Виплата ##{tx.id} ініційована для #{organization.name}."
    end

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ [Insurance] Запис ##{insurance_id} не знайдено."
  rescue StandardError => e
    Rails.logger.error "🚨 [Insurance Error] Критичний збій виплати: #{e.message}"
    raise e # Ретрай Sidekiq спробує ще раз через експоненціальну паузу
  end
end
