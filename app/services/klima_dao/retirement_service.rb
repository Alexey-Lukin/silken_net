# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"
require "bigdecimal"

module KlimaDao
  # =========================================================================
  # 🌿 KLIMA DAO RETIREMENT SERVICE (ESG Carbon Credit Retirement)
  # =========================================================================
  # Інтегрує інфраструктуру KlimaDAO на Polygon для офіційного погашення
  # (retirement) вуглецевих кредитів SCC. Коли організація хоче довести свою
  # еко-нейтральність для ESG-звітності, вона спалює токени через KlimaDAO
  # і отримує криптографічний доказ погашення.
  #
  # Потік:
  #   1. Перевірка балансу та типу токена (Guard Clause)
  #   2. Approve KlimaDAO контракту на витрату SCC
  #   3. Виклик retire(uint256) на KlimaDAO Retirement контракті
  #   4. Оновлення балансів у БД (balance ↓, esg_retired_balance ↑)
  #   5. Запис BlockchainTransaction з аудитом
  # =========================================================================
  class RetirementService
    # ABI для ERC-20 approve та KlimaDAO retire
    APPROVE_ABI = '[{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}]'
    RETIRE_ABI  = '[{"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"retire","outputs":[],"stateMutability":"nonpayable","type":"function"}]'

    TOKEN_DECIMALS = 18

    class InsufficientBalanceError < StandardError; end
    class InvalidTokenTypeError < StandardError; end
    class UnresolvedSemanticsError < StandardError; end

    # 🔴 [ARCH.95] FAIL-CLOSED до присуду. Тракт сьогодні МЕРТВИЙ (`KlimaRetirementWorker`
    # не має жодного enqueue-викликача поза спекою — виміряно), і саме тому три
    # незалежні розходження в ньому лишались невидимими. Кожне з них озброїлось би
    # ПЕРШОЮ ж миттю дротування, а два з трьох мутують необоротні поверхні:
    #
    #   1. ОДИНИЦЯ. Один скаляр трактується двома одиницями в одному методі:
    #      on-chain шле `amount × 10**18` (тобто МОНЕТИ), а в БД робить
    #      `decrement!(:balance, amount)` (тобто БАЛИ). За курсом 10 000:1 половини
    #      розходяться на чотири порядки — в обидва боки, і один із них палить
    #      реальних SCC у 10 000× більше, необоротно.
    #
    #   2. НАПРЯМОК. Запис іде БЕЗ `sourceable`, з ДОДАТНИМ `amount` і
    #      `token_type: :carbon_coin`, тож `BlockchainTransaction.net_minted_supply`
    #      (дискримінатор `sourceable_type IS DISTINCT FROM 'NaasContract'`) рахує
    #      ВИЛУЧЕННЯ з обігу як ЕМІСІЮ. А цей One-Home годує дві незворотні
    #      поверхні: поле `total_scc_supply` тижневого L1-якоря (`05_04 §3`) і базу
    #      розміру спалення (`05_05 §3`) — тобто погашення завищувало б розмір
    #      майбутнього слешингу.
    #
    #   3. GROSS-СЕМАНТИКА. `decrement!(:balance, …)` — єдине в застосунку місце,
    #      де `balance` СПАДАЄ, а `04_01 §6` визначає його як gross-лічильник
    #      («усе, що дерево заробило за життя»). Наслідок для доказу: перше поле
    #      L1-якоря = `Wallet.sum(:balance)`, тож погашення тихо переписало б
    #      офчейн-леджер балів заднім числом.
    #
    # Три осі не лікуються поодинці — фікс одної без інших дає ту саму
    # половинчастість, що вже коштувала пів дня на `total_sfc` (§Guard-craft #35).
    # Гард знято НЕ буде, доки присуд не ухвалено; знімати його = свідома дія,
    # а не побічний ефект дротування. → `00_07` ARCH.95.
    def self.semantics_resolved? = false

    def initialize(wallet, amount_to_retire)
      @wallet = wallet
      @amount_to_retire = BigDecimal(amount_to_retire.to_s)
    end

    def retire_carbon!
      validate!

      # 1. WEB3: Виконуємо блокчейн-операції ЗА МЕЖАМИ DB-транзакції,
      #    щоб не тримати довгі локи під час RPC-запитів.
      tx_hash = execute_blockchain_retirement

      # 2. DB: Атомарне оновлення балансів та створення аудит-запису
      ActiveRecord::Base.transaction do
        @wallet.lock!

        # Повторна перевірка після блокування (Race Condition Protection).
        # [ARCH.56] available_balance, НЕ balance: locked-частина зарезервована
        # pending-мінтом — retire повз неї впирався в wallets_balance_invariants
        # CHECK ПІСЛЯ необоротного on-chain burn (money-burned-without-record).
        if @wallet.available_balance < @amount_to_retire
          raise InsufficientBalanceError,
                "Баланс змінився під час транзакції (Доступно: #{@wallet.available_balance}, Потрібно: #{@amount_to_retire})"
        end

        @wallet.decrement!(:balance, @amount_to_retire)
        @wallet.increment!(:esg_retired_balance, @amount_to_retire)

        create_retirement_transaction(tx_hash)
      end

      Rails.logger.info "🌿 [KlimaDAO] Погашено #{@amount_to_retire} SCC для Wallet ##{@wallet.id}. TX: #{tx_hash}"
    end

    private

    def validate!
      # [ARCH.95] Перед будь-якою перевіркою балансу — гард семантики (шапка класу).
      unless self.class.semantics_resolved?
        raise UnresolvedSemanticsError,
              "🛑 [ARCH.95] ESG-погашення заблоковано: одиниця (`monety` vs `бали`), напрямок " \
              "у `net_minted_supply` і gross-семантика `balance` НЕ вирішені. Тракт мертвий " \
              "(нуль enqueue-викликачів), тож блокування нічого не ламає. Присуд → `00_07` ARCH.95."
      end

      # Guard Clause: Перевірка типу токена
      unless @wallet.blockchain_transactions.exists?(token_type: :carbon_coin)
        raise InvalidTokenTypeError,
              "Wallet ##{@wallet.id} не має carbon_coin транзакцій. Погашення доступне лише для SCC."
      end

      # Guard Clause: достатність ДОСТУПНОГО балансу (мінус locked, [ARCH.56])
      if @wallet.available_balance < @amount_to_retire
        raise InsufficientBalanceError,
              "Недостатньо коштів (Доступно: #{@wallet.available_balance}, Потрібно: #{@amount_to_retire})"
      end
    end

    def execute_blockchain_retirement
      client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
      # [INF.22] Dedicated Klima-підписант (легасі спільний ORACLE_PRIVATE_KEY retired) —
      # E.2-ізоляція blast-radius. Ключ інжектиться при активації Klima-шляху (06_04 §2.1).
      oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_KLIMA_PRIVATE_KEY"))

      scc_contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
      klima_contract_address = ENV.fetch("KLIMA_RETIREMENT_CONTRACT")

      scc_contract = Eth::Contract.from_abi(
        name: "SilkenCarbonCoin",
        address: scc_contract_address,
        abi: APPROVE_ABI
      )

      klima_contract = Eth::Contract.from_abi(
        name: "KlimaRetirement",
        address: klima_contract_address,
        abi: RETIRE_ABI
      )

      amount_in_wei = (@amount_to_retire * 10**TOKEN_DECIMALS).to_i

      # Step 1: Approve KlimaDAO контракту на витрату SCC
      client.transact(
        scc_contract, "approve", klima_contract_address, amount_in_wei,
        sender_key: oracle_key, legacy: false
      )

      # Step 2: Виклик retire на KlimaDAO контракті
      tx_hash = client.transact(
        klima_contract, "retire", amount_in_wei,
        sender_key: oracle_key, legacy: false
      )

      tx_hash
    end

    def create_retirement_transaction(tx_hash)
      @wallet.blockchain_transactions.create!(
        amount: @amount_to_retire,
        token_type: :carbon_coin,
        status: :sent,
        tx_hash: tx_hash,
        to_address: ENV.fetch("KLIMA_RETIREMENT_CONTRACT"),
        notes: "🌿 ESG Retirement via KlimaDAO: #{@amount_to_retire} SCC погашено для вуглецевої нейтральності."
      )
    end
  end
end
