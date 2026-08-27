# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Web3
  # [SEC.18 / DPIA захід M6 проти R7] Вільний текст → скінченна множина КОДІВ.
  #
  # Навіщо: `BlockchainTransaction#error_message` несе `e.message` довільного
  # винятку (чужий RPC, Kredis, HTTP-тіло), і саме він їхав у `AuditLog.metadata`,
  # тобто в ПУБЛІЧНИЙ незворотний IPFS-пін. Запінене не відкликається, тож
  # персональне чи секретне, потрапивши туди, стає нестиральним фізично.
  #
  # Форма ухвалена присудом (⚖️ 2026-08-27, делеговано founder'ом) з трьох
  # кандидатів — truncate ⊥ redaction за патернами ⊥ класифікація в код:
  #   * truncate ріже ДОВЖИНУ, не природу — 500 символів PII лишаються PII;
  #   * redaction за патернами **fail-OPEN за побудовою**: що не збіглося з
  #     патерном, те їде далі — а поверхня незворотна, тож дефолт мусить бути
  #     протилежний;
  #   * класифікація — єдина fail-CLOSED форма: назовні виходить лише те, що
  #     ми самі назвали, а невідоме стає `:unknown` і не несе жодного байта
  #     чужого тексту.
  #
  # ⛔ Класифікатор НІКОЛИ не повертає фрагмент вхідного рядка — тільки символ
  # із переліку нижче. Це і є інваріант: додаючи гілку, не витягуй підрядок.
  #
  # Прецеденти тієї ж форми в дереві: `Web3::EvmReceiptClassifier` (невідомий
  # status → `:reverted`) і `InsurancePayoutWorker` (`message_key` від машинного
  # символу + скалярні params замість готового англійського речення чужого сервісу).
  #
  # ⚠️ Стеля оголошена: КОД — це «якого роду відмова», ніколи «що саме сталось».
  # Повний текст лишається в `blockchain_transactions.error_message` (локально,
  # під retention/erasure) і в Sentry; сюди він більше не доїжджає. Тобто
  # діагностика не втрачена — вона переадресована, і адреса є в самому AuditLog
  # (`auditable_type`/`auditable_id`).
  module TransactionErrorClassifier
    module_function

    # Порядок несучий: перша збіжність виграє, тож вужчі форми стоять ВИЩЕ.
    # `broadcast_ambiguous` перший свідомо — це double-spend-лімбо (кошти
    # заблоковані, стан на ланцюгу невідомий), і сплутати його з простим
    # `evm_revert` означало б занизити тяжкість найдорожчого стану money-path.
    RULES = [
      [ :broadcast_ambiguous, /ambiguous|після broadcast|мемпул|стан на блокчейн/i ],
      [ :insufficient_funds,  /insufficient funds/i ],
      [ :evm_revert,          /evm revert|execution reverted|reverted/i ],
      [ :lock_timeout,        /lock-?timeout|locktimeout/i ],
      [ :rpc_rejected,        /rejected/i ],
      [ :reserve_hold,        /reserve-?gate/i ],
      [ :stuck_timeout,       /stuck|завис/i ],
      [ :stale_unconfirmed,   /stale|не підтвердж/i ]
    ].freeze

    # @param message [String, nil] сирий `error_message`
    # @return [Symbol] `:none` коли тексту немає; інакше код із `RULES`, або
    #   `:unknown` — і саме `:unknown` є дефолтом, а не «пропустити як є».
    def classify(message)
      text = message.to_s.strip
      return :none if text.empty?

      RULES.each { |code, pattern| return code if pattern.match?(text) }
      :unknown
    end
  end
end
