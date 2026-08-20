# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🌿 PURO PASSPORT CONFIRMATION (PERF.1(д) — The Passport Notary)
# = ===================================================================
# Довершує lifecycle Puro-анкера ВЛАСНИМ поллером (присуд founder 2026-08-20,
# «третя форма» за прецедентом EthereumAnchorConfirmationWorker): доти
# конфірмейшн-нога вела в `BlockchainConfirmationWorker`, який шукає хеш у
# `blockchain_transactions` — таблиці, куди паспортний хеш не потрапляє НІКОЛИ.
# Поллер завжди знаходив порожнечу, «доказ» їхав у зовнішній реєстр Puro без
# перевірки, що транзакція не revert-нулась.
#
#   :confirmed → confirm_biomass_passport! + re-enqueue оркестратора
#                (PuroEarthPassportWorker побачить :confirmed і відкриє Phase 2)
#   :reverted  → fail_biomass_passport! (термінал; re-anchor = console-рішення)
#   :pending   → raise (normal poll) / escalate_biomass_passport! (final)
#
# Polling вичерпано → ФІНАЛЬНИЙ receipt re-check (прецедент ARCH.66 / MintingRollback:
# tx міг замайнитись в останній ретрай — сліпий escalate записав би підтверджений
# on-chain анкер у :manual_review назавжди). RPC-глюк на re-check → escalate.
#
# [Polygon ≠ L1]: без reorg-depth gate — дзеркало BlockchainConfirmationWorker
# (перший receipt = вердикт), НЕ EthereumAnchor (64-блокова finality L1-печатки).
# Re-broadcast НІКОЛИ: поллер лише читає receipt; дубль-анкер на crash-retry
# детермінований (same payloadHash) і безпечний — reconcile-only.
class PuroEarthConfirmationWorker
  include ApplicationWeb3Worker

  # web3_low: не money-path (кошти не заблоковані — на відміну від mint-tracту),
  # Polygon швидкий. 10 ретраїв ≈ 15-20 хв горизонт (дзеркало BlockchainConfirmationWorker);
  # `unique_for` = Enterprise-шим (no-op без sidekiq-ent) — exactly-once реально тримає
  # with_lock+status-гард переходів моделі.
  sidekiq_options queue: "web3_low", retry: 10, unique_for: 10.minutes

  sidekiq_retries_exhausted do |msg, _ex|
    record = MaintenanceRecord.find_by(id: msg["args"].first)
    next unless record&.biomass_passport_sent?

    begin
      new.resolve!(record, final: true)
    rescue StandardError => e
      Rails.logger.warn "🌿 [Puro.earth] final re-check failed для record ##{record.id} " \
                        "(#{e.class}: #{e.message}) — escalate."
      record.escalate_biomass_passport!
    end
  end

  def perform(record_id)
    record = MaintenanceRecord.find_by(id: record_id)
    return unless record&.biomass_passport_sent?

    resolve!(record, final: false)
  end

  # `final: false` (нормальний полл) → не-готовий = raise (Sidekiq retry).
  # `final: true` (retries вичерпано) → не-готовий = escalate (людська звірка).
  def resolve!(record, final:)
    receipt = within_rpc_limit do
      Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
                             .eth_get_transaction_receipt(record.biomass_passport_tx_hash)
    end

    case Web3::EvmReceiptClassifier.classify(receipt)
    when :confirmed
      # Re-enqueue оркестратора лише для переможця гонки (перехід відбувся) —
      # він ідемпотентний і сам, але дубль-джоба була б шумом.
      if record.confirm_biomass_passport!
        Rails.logger.info "🌿 [Puro.earth] Passport anchor confirmed on-chain " \
                          "(record ##{record.id}, tx #{record.biomass_passport_tx_hash}) — Phase 2 відкрито."
        PuroEarthPassportWorker.perform_async(record.id)
      end
    when :reverted
      if record.fail_biomass_passport!
        Rails.logger.error "🛑 [Puro.earth] anchorPassport REVERTED on-chain " \
                           "(record ##{record.id}, tx #{record.biomass_passport_tx_hash}) → :failed. " \
                           "Re-anchor = console: скинути tx_hash+status і re-enqueue PuroEarthPassportWorker."
      end
    else
      resolve_pending!(record, final: final)
    end
  end

  private

  def resolve_pending!(record, final:)
    raise "⏳ Puro passport tx #{record.biomass_passport_tx_hash} ще в мемпулі — retry." unless final

    if record.escalate_biomass_passport!
      Rails.logger.warn "🌿 [Puro.earth] polling вичерпано для record ##{record.id} → :manual_review " \
                        "(звірити tx #{record.biomass_passport_tx_hash} на polygonscan; " \
                        "console confirm_biomass_passport! / fail_biomass_passport!)."
    end
  end
end
