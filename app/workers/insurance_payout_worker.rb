# frozen_string_literal: true

class InsurancePayoutWorker
  include ApplicationWeb3Worker
  # Найвищий пріоритет: виконання фінансових зобов'язань перед інвесторами
  # є критичним для репутації Цитаделі. Черга critical гарантує, що виплати
  # не застрягнуть за повільними Polygon-мінтингами у web3.
  sidekiq_options queue: "critical", retry: 10

  def perform(insurance_id)
    insurance = ParametricInsurance.includes(cluster: :organization).find_by(id: insurance_id)
    return unless insurance

    # 1. ПЕРЕВІРКА ТРИГЕРА
    # Виконуємо лише якщо Оракул активував тригер, але виплата ще не зафіксована як завершена.
    return unless insurance.status_triggered?

    organization = insurance.cluster.organization

    # Шукаємо гаманець-якір для аудиторського логування в Ledger.
    # Спочатку шукаємо активне дерево; якщо катастрофа знищила всі активні дерева —
    # беремо будь-яке дерево кластера (незалежно від статусу) лише для аудит-зв'язку.
    audit_wallet = insurance.cluster.trees.active.first&.wallet ||
                   insurance.cluster.trees.first&.wallet

    unless audit_wallet
      Rails.logger.error "🛑 [Insurance] Спроба виплати ##{insurance_id} без жодного дерева в кластері."
      return
    end

    # 2. АТОМАРНА ФІКСАЦІЯ ВИПЛАТИ (Postgres Domain)
    tx = nil
    ActiveRecord::Base.transaction do
      # Pessimistic lock для запобігання подвійних виплат (Double Spend Protection)
      insurance.lock!
      # [next vs return]: next виходить тільки з блоку, а не з методу perform.
      # return тут виходив би з методу — семантична пастка при рефакторингу на proc/lambda.
      next unless insurance.status_triggered?

      # Створюємо запис у блокчейн-черзі для виконання емісії/переказу
      tx = insurance.create_blockchain_transaction!(
        wallet: audit_wallet,
        amount: insurance.payout_amount,
        token_type: insurance.token_type, # Тип токена обирається при підписанні контракту
        to_address: organization.crypto_public_address,
        status: :pending,
        notes: "Страхове відшкодування ##{insurance.id}. Подія: #{insurance.trigger_event}."
      )

      # Переводимо страховку в стан виплати (AASM: triggered → paid)
      insurance.pay!
    end

    # 3. WEB3 ЕКЗЕКУЦІЯ (Blockchain Domain)
    # Тепер, коли транзакція зафіксована в базі, ми передаємо її нашому
    # загартованому BlockchainMintingService для підпису та відправки в Polygon.
    if tx
      Rails.logger.info "🚀 [Insurance] Ініціація виплати #{tx.amount} SCC для #{organization.name}..."

      # Транслюємо "Flash" повідомлення Архітектору
      broadcast_insurance_update(insurance, tx)

      BlockchainMintingService.call(tx.id)
    end

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ [Insurance] Запис ##{insurance_id} зник із Матриці."
  rescue StandardError => e
    Rails.logger.error "🚨 [Insurance Error] Критичний збій виплати ##{insurance_id}: #{e.message}"
    raise # Дозволяємо Sidekiq спробувати ще 10 разів (SLA 99.9%)
  end

  private

  def broadcast_insurance_update(insurance, transaction)
    # Оновлюємо статус картки страхування на Dashboard
    Turbo::StreamsChannel.broadcast_replace_to(
      insurance.cluster.organization,
      target: "insurance_card_#{insurance.id}",
      html: Shared::StatusBadge.new(status: insurance.status, id: "insurance_card_#{insurance.id}").call
    )

    # Додаємо запис у глобальний потік подій
    Turbo::StreamsChannel.broadcast_prepend_to(
      "global_events",
      target: "events_feed",
      html: Dashboard::EventRow.new(
        event: transaction,
        icon: "shield-check",
        color: "blue"
      ).call
    )
  end
end
