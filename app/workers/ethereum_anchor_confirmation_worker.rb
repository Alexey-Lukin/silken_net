# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# ⚓ ETHEREUM L1 ANCHOR CONFIRMATION (ARCH.66 — The Seal Finalizer)
# = ===================================================================
# `StateAnchorService#anchor_to_l1!` broadcast'ить storeStateRoot і ставить :sent — але НІЩО
# не опитувало receipt → anchor НІКОЛИ не :confirmed (fire-and-forget). scopes successful/
# latest_confirmed вічно порожні, block_number/gas_used не заповнюються, double-anchor guard
# деградує до тижневого таймера (завислий :sent після 7д випадає з guard → ризик подвійного
# state_root, якщо старий tx приземлиться).
#
# Цей поллер довершує lifecycle (дзеркало CeloConfirmationWorker, L1-специфіка):
#   :confirmed + finalized       → confirm!(block, gas)
#   :confirmed + shallow/no-block → «ще не готово» (raise на normal / escalate на final)
#   :reverted                    → mark_failed! (+ reverted-counter лише для переможця гонки)
#   :pending                     → raise (normal) / escalate (final)
# Polling вичерпано → ФІНАЛЬНИЙ receipt re-check (дзеркало `MintingRollbackService`: tx міг
# замайнитись в останній ретрай — сліпий escalate записав би підтверджений-on-chain anchor
# у :manual_review назавжди). RPC-глюк на фінальному re-check → rescue → escalate (не :sent-limbo).
#
# [L1 ≠ Polygon/Celo]:
#   • Фіксований polling-інтервал + ~3год горизонт (100-Gwei cap стопорить включення на години —
#     money-path 15-20хв дав би хибну ескалацію).
#   • Reorg-depth gate (finality, не перший receipt) — І на фінальному re-check: «фінальна
#     печатка» не запечатується на sub-finality блоці навіть коли retries вичерпано (slow-inclusion
#     міг замайнити tx в останні хвилини на глибині < 64) → замість сліпого confirm → escalate.
#   • Re-broadcast НІКОЛИ (поллер лише читає receipt): розштовхати застряглий tx = людський
#     same-nonce gas-bump. nonce персиститься перед broadcast [ARCH.66 companion] → навіть
#     resume-re-send іде на тому ж слоті (replace/nonce-too-low), не N+1 — але авто-re-send немає.
class EthereumAnchorConfirmationWorker
  include ApplicationWeb3Worker

  # web3_low (той самий пріоритет, що тижневий anchor-cron; не час-критично).
  # Фіксований retry_in ~3хв × 60 ретраїв ≈ 3год горизонт (НЕ exponential — той роздувся б
  # у дні). `unique_for` = Enterprise-шим (no-op без sidekiq-ent) — exactly-once реально тримає
  # `with_lock`+status-гард у переходах моделі, НЕ unique_for.
  sidekiq_options queue: "web3_low", retry: 60, unique_for: 3.hours
  sidekiq_retry_in { |_count, _exception| 180 }

  # Глибина підтверджень перед :confirmed. Post-Merge Ethereum фіналізує на 2 епохах (~64 блоки
  # ≈ 13хв) — глибший reorg неможливий без >⅓-stake slashing-катастрофи. ENV-tunable; 0 = confirm
  # на першому receipt (dev/testnet, де finality лагає).
  DEFAULT_MIN_CONFIRMATIONS = 64

  # broadcast прошов, але receipt не приземлився за ~3год → ФІНАЛЬНИЙ re-check (tx міг замайнитись
  # в останній ретрай), і лише все ще не-готовий → escalate. RPC-глюк тут → rescue → escalate
  # (дзеркало MintingRollbackService — не лишати :sent-limbo до 6-год sweeper).
  sidekiq_retries_exhausted do |msg, _ex|
    anchor = EthereumAnchor.find_by(id: msg["args"].first)
    next unless anchor&.status_sent?

    begin
      new.resolve!(anchor, final: true)
    rescue *ApplicationWeb3Worker::RPC_TRANSIENT_ERRORS => e
      Rails.logger.warn "⚓ [ARCH.66] final re-check RPC-fail для ##{anchor.id} (#{e.message}) — escalate."
      anchor.escalate_to_review!("Final receipt re-check failed (RPC: #{e.class}) — доля невідома, звірити на etherscan.")
    rescue StandardError => e
      # [LOW-2] Не-RPC виняток (програмний баг / несподіване) — теж escalate (не :sent-limbo, який
      # sweeper re-arm'ив би нескінченно з тим самим багом), АЛЕ чесний reason + error-лог: не
      # маскуємо баг під «RPC».
      Rails.logger.error "🛑 [ARCH.66] final re-check UNEXPECTED (#{e.class}: #{e.message}) для ##{anchor.id} — escalate + перевірити баг."
      anchor.escalate_to_review!("Final receipt re-check failed (unexpected #{e.class}) — доля невідома, звірити на etherscan + перевірити баг.")
    end
  end

  def perform(anchor_id)
    anchor = EthereumAnchor.find_by(id: anchor_id)
    return unless anchor&.status_sent?

    resolve!(anchor, final: false)
  end

  # Опитує receipt і рухає anchor у термінальний стан.
  # `final: false` (нормальний полл) → не-готовий = `raise` (Sidekiq retry).
  # `final: true` (retries вичерпано) → не-готовий = `escalate_to_review!` (людська звірка).
  def resolve!(anchor, final:)
    receipt = within_rpc_limit do
      Web3::RpcConnectionPool.client_for("ALCHEMY_ETHEREUM_RPC_URL").eth_get_transaction_receipt(anchor.tx_hash)
    end

    case Web3::EvmReceiptClassifier.classify(receipt)
    when :confirmed
      confirm_anchor!(anchor, receipt, final: final)
    when :reverted
      # [LOW-A2] reverted-counter інкрементимо ЛИШЕ якщо перехід відбувся — інакше 2 паралельні
      # поллери (INFO-7 resume + sweeper) рахували б один on-chain revert двічі.
      if anchor.mark_failed!("storeStateRoot reverted on-chain (root-колізія / <6 днів / gas / contract-logic)")
        SilkenNet::Metrics::ETHEREUM_ANCHOR_REVERTED_TOTAL.increment
        Rails.logger.error "🛑 [ARCH.66] Anchor ##{anchor.id} storeStateRoot REVERTED on-chain → :failed."
      end
    else
      resolve_pending!(anchor, final: final)
    end
  end

  private

  def confirm_anchor!(anchor, receipt, final:)
    # [LOW-1] Розгортаємо envelope тим самим прийомом, що EvmReceiptClassifier (приймає wrapped
    # {"result"=>…} І flat {"status"=>…}) — інакше flat-receipt дав би nil["blockNumber"] crash.
    result = receipt.is_a?(Hash) && receipt.key?("result") ? receipt["result"] : receipt
    block_num = hex_to_i(result["blockNumber"])
    gas_used  = hex_to_i(result["gasUsed"])

    # [LOW-3] Аномальний :confirmed без blockNumber — не привід confirm'ити без finality.
    # [LOW-A3] Недостатня глибина (< MIN_CONFIRMATIONS) — теж НЕ запечатуємо, І на final re-check
    # («фінальна печатка» не сміє осісти на sub-finality блоці навіть коли retries вичерпано).
    # Обидва → resolve_pending! (raise на normal / escalate на final). ⚠️ Стеля: на final RPC-лаг
    # eth_block_number або last-minute-mine (shallow) → spurious escalate здорового tx → recoverable
    # оператор-`confirm!` з :manual_review (MEDIUM-A1); рідко, свідома ціна seal-safety.
    return resolve_pending!(anchor, final: final) if block_num.nil? || !anchor_finalized?(block_num)

    # [LOW-4] Лог лише якщо перехід відбувся (confirm! → false при програній гонці = no-op).
    if anchor.confirm!(block_num, gas_used)
      Rails.logger.info "⚓ [ARCH.66] Anchor ##{anchor.id} state-root запечатано на L1 " \
                        "(block #{block_num}, gas #{gas_used})."
    end
  end

  # Чи receipt-блок достатньо глибокий для finality (default 64 ≈ 2 епохи). ENV 0 = off
  # (dev/testnet). latest-block RPC недоступний → консервативно false (не доводимо finality →
  # raise/escalate, не сліпий confirm).
  def anchor_finalized?(block_num)
    min_conf = ENV.fetch("ETHEREUM_ANCHOR_MIN_CONFIRMATIONS", DEFAULT_MIN_CONFIRMATIONS).to_i
    return true unless min_conf.positive?

    latest = within_rpc_limit do
      Web3::RpcConnectionPool.client_for("ALCHEMY_ETHEREUM_RPC_URL").eth_block_number&.dig("result")&.then { |v| v.to_i(16) }
    end
    return false unless latest

    (latest - block_num) >= min_conf
  end

  # hex-string ("0x…") → Integer; вже-Integer (flat/legacy receipt) → as-is; nil → nil.
  def hex_to_i(value)
    return if value.nil?

    value.is_a?(Integer) ? value : value.to_i(16)
  end

  # anchor ще не готовий до seal (мемпул-pending / аномальний receipt / sub-finality глибина).
  def resolve_pending!(anchor, final:)
    raise "⏳ Anchor ##{anchor.id} ще не готовий до seal (pending / не finalized) — retry." unless final

    # [Sonnet-1/LOW-4] warn лише якщо escalate відбувся (не при програній гонці no-op).
    if anchor.escalate_to_review!(
      "Anchor confirmation polling exhausted — не досягнуто finality/confirmation за poll-SLA, " \
      "доля ambiguous; звірити storeStateRoot на etherscan (gas-bump same-nonce / console confirm!)."
    )
      Rails.logger.warn "⚓ [ARCH.66] Anchor ##{anchor.id} polling вичерпано → :manual_review."
    end
  end
end
