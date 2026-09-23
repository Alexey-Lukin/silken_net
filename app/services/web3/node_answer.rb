# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Web3
  # = ===================================================================
  # 🗣️ ВУЗОЛ ВІДПОВІВ ПРО НАШ ЗАПИТ ⊥ ПРОВАЙДЕР ЗЛАМАВСЯ [ARCH.62, 2026-09-23]
  # = ===================================================================
  # Один дім питання, яке доти ставили ЧОТИРИ місця кожне своїм словником:
  # `BlockchainMintingService#transact_error_pre_broadcast?` · `Celo::CommunityRewardService`
  # (дві регулярки) · `Ethereum::StateAnchorService` · і обидва circuit breaker'и, які
  # цього питання не ставили зовсім. Ціна розходження виміряна: газ-лімітну родину
  # (нижче) 2026-09-05 вивчив лише класифікатор мінту — Celo її не знав. (L1-якір читає
  # лише `ALREADY_SUBMITTED`: решту його відмов підіймає нагору, тож ця родина йому байдужа.)
  #
  # Дві множини, і межа між ними — безпека, не стиль:
  #   * `REJECTED` — вузол ВІДКИНУВ кадр на валідації чи виконанні, у мемпул він не
  #     потрапив → безпечно `fail!` і відправити знову. Сюди ж газ-лімітна родина:
  #     Amoy відповідав дослівно `Transaction gas limit is too low, try 74494!`, і поки
  #     вона не мала імені, детермінована відмова ДО броадкасту їхала як ambiguous —
  #     44 мінти в `manual_review` з порожнім хешем (виміряно на canopy 2026-09-05).
  #   * `ALREADY_SUBMITTED` — tx під цим nonce УЖЕ подано (наша попередня чи ця сама),
  #     тож вона могла полетіти → ambiguous, ⛔ ніколи не сліпий re-send (double-spend).
  #   🔴 Межа між ними тримається РІШЕННЯМ, не даними: текст, що збігається з обома
  #   (майбутня «transaction underpriced» — підрядок «replacement transaction
  #   underpriced»), `rejected?` НЕ є — неоднозначність домінує.
  #
  # ⚠️ `rejected?`/`already_submitted?` судять ТЕКСТ, а не клас, і це несуче: наш
  # власний `Web3::KeySigner::InsufficientGasReserve` (`StandardError`) несе маркер
  # `insufficient funds` саме для того, щоб читатись як вирок ноди — класова перевірка
  # тут зробила б гард виробником `manual_review`-лімбу.
  #
  # 🔑 `answered?` — питання breaker'ів, і воно ВУЖЧЕ: чи НАЙБЛИЖЧА мережева причина в
  # ланцюгу — JSON-RPC-відповідь вузла (`Eth::Client::RpcError`) з однієї з множин.
  # Транспортний збій, піднятий усередині rescue відповіді (його `cause` — та відповідь),
  # лишається збоєм: пошук зупиняється на першому транспорті. Така відповідь доводить,
  # що провайдер ЗДОРОВИЙ — він розібрав наш запит і сказав про нього правду. `RpcError < IOError`, тож без цього предиката кожна з них
  # рахувалась збоєм провайдера: три поспіль — breaker відкритий на всіх вузлах і
  # `sn-alert-circuit-breaker` будить оператора на здоровій інфраструктурі.
  # ⚠️ Стеля: множини — ALLOWLIST. JSON-RPC-помилку, якої тут немає («upstream
  # timeout», «header not found», «internal error»), breaker і далі рахує збоєм — і
  # це свідомий бік помилки: шлюз, що вже переслав tx, теж відповідає JSON-RPC-помилкою,
  # тож невідоме лишається провайдерським, а не нашим (гоча `web3-pipeline` #40).
  module NodeAnswer
    module_function

    REJECTED = /revert|insufficient funds|intrinsic gas|gas required exceeds|gas limit is too low|exceeds block gas limit|invalid sender|out of gas/i

    ALREADY_SUBMITTED = /nonce too low|already known|replacement transaction underpriced|already imported/i

    # Найближча причина цього роду — транспорт, не відповідь (`Net::*Timeout < Timeout::Error`,
    # `Errno::* < SystemCallError`; `RpcError < IOError` перевіряється ДО цього переліку).
    TRANSPORT_ERRORS = [ IOError, SocketError, SystemCallError, Timeout::Error ].freeze

    def rejected?(error)
      text = error.message.to_s
      REJECTED.match?(text) && !ALREADY_SUBMITTED.match?(text)
    end

    def already_submitted?(error)
      ALREADY_SUBMITTED.match?(error.message.to_s)
    end

    def answered?(error)
      rpc = rpc_error_in(error)
      !rpc.nil? && (rejected?(rpc) || already_submitted?(rpc))
    end

    def rpc_error_in(error)
      return nil if error.nil?
      return error if error.is_a?(Eth::Client::RpcError)
      return nil if TRANSPORT_ERRORS.any? { |klass| error.is_a?(klass) }

      rpc_error_in(error.cause)
    end
  end
end
