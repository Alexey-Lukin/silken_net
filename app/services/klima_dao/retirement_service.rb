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

        # Повторна перевірка після блокування (Race Condition Protection)
        if @wallet.balance < @amount_to_retire
          raise InsufficientBalanceError,
                "Баланс змінився під час транзакції (Доступно: #{@wallet.balance}, Потрібно: #{@amount_to_retire})"
        end

        @wallet.decrement!(:balance, @amount_to_retire)
        @wallet.increment!(:esg_retired_balance, @amount_to_retire)

        create_retirement_transaction(tx_hash)
      end

      Rails.logger.info "🌿 [KlimaDAO] Погашено #{@amount_to_retire} SCC для Wallet ##{@wallet.id}. TX: #{tx_hash}"
    end

    private

    def validate!
      # Guard Clause: Перевірка типу токена
      unless @wallet.blockchain_transactions.exists?(token_type: :carbon_coin)
        raise InvalidTokenTypeError,
              "Wallet ##{@wallet.id} не має carbon_coin транзакцій. Погашення доступне лише для SCC."
      end

      # Guard Clause: Перевірка достатності балансу
      if @wallet.balance < @amount_to_retire
        raise InsufficientBalanceError,
              "Недостатньо коштів (Доступно: #{@wallet.balance}, Потрібно: #{@amount_to_retire})"
      end
    end

    def execute_blockchain_retirement
      client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
      oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

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

      amount_in_wei = (BigDecimal(@amount_to_retire.to_s) * 10**TOKEN_DECIMALS).to_i

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
